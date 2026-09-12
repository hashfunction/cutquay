"""Behavioral tests for the disposable CutQuay MSIX qualification package.

Copyright 2026 Trieflow LLC. MIT licensed.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch
import struct
import zlib
import unittest
import zipfile

import msix_qualification as msix
from source_publication_fixture import publication_files


def sha(data):
	return hashlib.sha256(data).hexdigest()


class QualificationFixture(unittest.TestCase):
	def setUp(self):
		self.temporary = tempfile.TemporaryDirectory()
		self.addCleanup(self.temporary.cleanup)
		self.root = Path(self.temporary.name)
		self.source = self.root / 'source'
		self.source.mkdir()
		self.release = self.root / 'release'
		self.release.mkdir()
		self.commit = '1' * 40
		self.artwork = self.source / 'icon.png'
		self.artwork.write_bytes((Path(__file__).resolve().parents[2] / 'icon-build/app-512.png').read_bytes())
		self.source_files = {
			'package.json': json.dumps({'name':'cutquay','productName':'CutQuay','version':'1.0.0',
				'main':'./out/main/index.js','devDependencies':{'electron':'42.11.3'}}).encode(),
			'yarn.lock': b'locked fixture', 'LICENSE':b'application license', 'NOTICE':b'application notice',
			'licenses.txt':b'dependency notices', 'Release/THIRD-PARTY-NOTICES.txt':b'third party notices',
			'Release/FFmpeg-LICENSE.txt':b'ffmpeg notice', 'src/renderer/src/icon.svg':(Path(__file__).resolve().parents[2]/'src/renderer/src/icon.svg').read_bytes(),
			'out/main/index.js':b'application entry', 'out/renderer/index.html':b'application renderer',
			'locales/en/translation.json':b'{}',
		}
		self.media = {f'resources/{name}': ('pinned ' + name).encode() for name in ('ffmpeg.exe','ffprobe.exe','avcodec-62.dll','avdevice-62.dll','avfilter-11.dll','avformat-62.dll','avutil-60.dll','swresample-6.dll','swscale-9.dll')}
		pin = {'version':'n8.1.2-fixture', 'platform':'win32-x64', 'archiveSha256':'9'*64, 'ffmpegCommit':'7'*10,
			'configureStringsExtractedFromBinaries':['--enable-gpl --enable-shared'],
			'files':[{'path':'bin/'+Path(name).name,'sizeBytes':len(data),'sha256':sha(data)} for name,data in self.media.items()]}
		self.source_files['Release/ffmpeg-build.json'] = json.dumps(pin).encode()
		self.native_sources=publication_files()
		self.native_sources['NATIVE-SOURCES.txt']=(Path(__file__).resolve().parents[2]/'Release/NATIVE-SOURCES.txt').read_bytes()
		self.source_files.update({'Release/'+name:data for name,data in self.native_sources.items()})
		for name, data in self.source_files.items():
			path = self.source / name
			path.parent.mkdir(parents=True, exist_ok=True)
			path.write_bytes(data)
		self.electron = self.root / 'electron-v42.11.3-win32-x64.zip'
		self.runtime = {name: ('electron '+name).encode() for name in (
			'LICENSE','LICENSES.chromium.html','chrome_100_percent.pak','chrome_200_percent.pak',
			'icudtl.dat','resources.pak','v8_context_snapshot.bin','libEGL.dll','libGLESv2.dll',
			'd3dcompiler_47.dll','ffmpeg.dll','vk_swiftshader.dll','vk_swiftshader_icd.json','vulkan-1.dll','locales/en-US.pak')}
		with zipfile.ZipFile(self.electron, 'w') as archive:
			for name,data in self.runtime.items(): archive.writestr(name,data)
			archive.writestr('electron.exe',b'original executable')
			archive.writestr('version','42.11.3')
			archive.writestr('resources/default_app.asar',b'default app')
		self.checksums = self.root / 'SHASUMS256.txt'
		self.checksums.write_text(sha(self.electron.read_bytes())+' *'+self.electron.name+'\n')
		files = {('LICENSE.electron.txt' if name == 'LICENSE' else name):data for name,data in self.runtime.items()}
		files.update(self.media)
		files.update({'resources/'+name:data for name,data in self.native_sources.items()})
		files.update({'CutQuay.exe':b'branded executable', 'resources/FFmpeg-LICENSE.txt':b'ffmpeg notice',
			'resources/locales/en/translation.json':b'{}'})
		for name,data in files.items():
			path = self.release / name
			path.parent.mkdir(parents=True, exist_ok=True)
			path.write_bytes(data)
		self.make_asar()

	def make_asar(self):
		asar_source = self.root / 'asar-input'
		if asar_source.exists(): shutil.rmtree(asar_source)
		asar_source.mkdir()
		for name in list(self.source_files):
			if name in ('yarn.lock','src/renderer/src/icon.svg') or name.startswith('locales/'): continue
			path = asar_source / name
			path.parent.mkdir(parents=True, exist_ok=True)
			path.write_bytes((self.source / name).read_bytes())
		module = Path(__file__).resolve().parents[2] / 'node_modules/@electron/asar'
		subprocess.run(['node','-e',"require(process.argv[1]).createPackage(process.argv[2],process.argv[3]).catch(e=>{console.error(e);process.exit(1)})",
			str(module),str(asar_source),str(self.release/'resources/app.asar')], check=True, capture_output=True)

	def stage(self):
		return msix.stage_release(self.release, self.artwork, self.root/'stage', self.commit,
			self.source, self.electron, self.checksums)


class ManifestTests(QualificationFixture):
	def test_store_manifest_uses_only_the_allowlisted_store_identity(self):
		data = msix.create_manifest(identity_mode='store')
		identity = msix.validate_manifest(data, identity_mode='store')
		self.assertEqual('1659hashfunction.CutQuay', identity['packageName'])
		self.assertEqual('CN=B6A2631A-FD32-45CC-AE12-82466975F528', identity['publisher'])
		self.assertEqual('hashfunction', identity['publisherDisplayName'])
		self.assertEqual('CutQuay', identity['applicationId'])
		self.assertEqual('1.0.0.0', identity['version'])
		self.assertEqual('Windows.Desktop', identity['deviceFamily'])
		self.assertIn(b'<PublisherDisplayName>hashfunction</PublisherDisplayName>', data)
		self.assertNotIn(b'Qualification', data)

	def test_identity_modes_cannot_be_confused_or_extended(self):
		for mode, other in [('qualification', 'store'), ('store', 'qualification')]:
			data = msix.create_manifest(identity_mode=mode)
			with self.assertRaisesRegex(ValueError, 'identity'):
				msix.validate_manifest(data, identity_mode=other)
		for mode in ('', 'Store', 'custom', None):
			with self.assertRaisesRegex(ValueError, 'identity mode'):
				msix.create_manifest(identity_mode=mode)
			with self.assertRaisesRegex(ValueError, 'identity mode'):
				msix.validate_manifest(msix.create_manifest(), identity_mode=mode)

	def test_store_manifest_rejects_identity_display_and_capability_mutations(self):
		data = msix.create_manifest(identity_mode='store')
		for before, after in (
			(b'1659hashfunction.CutQuay', b'Trieflow.CutQuay.Qualification'),
			(b'CN=B6A2631A-FD32-45CC-AE12-82466975F528', b'CN=CutQuay-CI-Qualification'),
			(b'>hashfunction<', b'>Trieflow LLC<'),
			(b'Version="1.0.0.0"', b'Version="2.0.0.0"'),
			(b'ProcessorArchitecture="x64"', b'ProcessorArchitecture="arm64"'),
			(b'Id="CutQuay"', b'Id="Other"'),
			(b'CutQuay.exe', b'other.exe'),
			(b'Windows.Desktop', b'Windows.Universal'),
			(b'runFullTrust', b'internetClient'),
		):
			with self.subTest(before=before), self.assertRaises(ValueError):
				msix.validate_manifest(data.replace(before, after), identity_mode='store')

	def test_manifest_has_only_qualification_identity_and_required_capability(self):
		manifest = msix.validate_manifest(msix.create_manifest())
		self.assertEqual(msix.QUALIFICATION_IDENTITY, manifest)
		text = msix.create_manifest().decode('utf-8')
		for absent in ('Protocol', 'FileTypeAssociation', 'com:Extension', 'uap:Extension', 'Registry'):
			self.assertNotIn(absent, text)

	def test_manifest_rejects_extra_capability_and_wrong_executable(self):
		data = msix.create_manifest()
		with self.assertRaisesRegex(ValueError, 'capabilit'):
			msix.validate_manifest(data.replace(b'</Capabilities>', b'<rescap:Capability Name="internetClient"/></Capabilities>'))
		with self.assertRaisesRegex(ValueError, 'executable'):
			msix.validate_manifest(data.replace(b'CutQuay.exe', b'other.exe'))
		with self.assertRaisesRegex(ValueError, 'properties'):
			msix.validate_manifest(data.replace(b'</Properties>', b'<DisplayName>CutQuay</DisplayName></Properties>'))


class StageTests(QualificationFixture):
	def test_both_modes_preserve_runtime_and_keep_release_clearance_false(self):
		records = {}
		for mode in ('qualification', 'store'):
			stage = self.root / mode
			record = msix.stage_release(self.release, self.artwork, stage, self.commit,
				self.source, self.electron, self.checksums, identity_mode=mode)
			self.assertEqual(mode, record['identityMode'])
			self.assertIs(mode == 'qualification', record['qualificationIdentityOnly'])
			self.assertIs(mode == 'store', record['storeIdentityUsed'])
			for flag in ('licenseClearanceClaimed', 'publicRelease', 'signed', 'installationQualificationPassed'):
				self.assertIs(False, record[flag])
			self.assertEqual(record['identity'], msix.validate_manifest((stage/'AppxManifest.xml').read_bytes(), identity_mode=mode))
			records[mode] = record
		self.assertEqual(records['qualification']['releaseInput'], records['store']['releaseInput'])
		self.assertEqual(records['qualification']['runtime'], records['store']['runtime'])
		for mode in ('custom', 'Store'):
			output = self.root / ('invalid-' + mode)
			with self.assertRaisesRegex(ValueError, 'identity mode'):
				msix.stage_release(self.release, self.artwork, output, self.commit,
					self.source, self.electron, self.checksums, identity_mode=mode)
			self.assertFalse(output.exists())

	def test_stage_copies_complete_release_and_records_assets_and_hashes(self):
		record = self.stage()
		stage = self.root / 'stage'
		self.assertEqual(self.commit, record['sourceCommit'])
		self.assertFalse(record['licenseClearanceClaimed'])
		self.assertFalse(record['publicRelease'])
		self.assertEqual((self.release / 'resources/locales/en/translation.json').read_bytes(), (stage / 'resources/locales/en/translation.json').read_bytes())
		self.assertEqual(record['releaseInput'], msix.inventory_tree(self.release))
		self.assertEqual(record['payload'], msix.inventory_tree(stage))
		for name, size in [('StoreLogo.png', 50), ('Square44x44Logo.png', 44), ('Square150x150Logo.png', 150)]:
			data = (stage / 'Assets' / name).read_bytes()
			self.assertEqual((size, size), msix.png_dimensions(data))
			self.assertEqual(sha(data), record['assets'][f'Assets/{name}']['sha256'])

	def test_stage_refuses_existing_output_and_does_not_change_it(self):
		stage = self.root / 'stage'
		stage.mkdir()
		marker = stage / 'owned.txt'
		marker.write_text('preserve')
		with self.assertRaisesRegex(ValueError, 'already exists'):
			msix.stage_release(self.release, self.artwork, stage, self.commit, self.source, self.electron, self.checksums)
		self.assertEqual('preserve', marker.read_text())

	def test_missing_runtime_notices_and_pinned_binaries_are_rejected_before_staging(self):
		for name in ('icudtl.dat','LICENSE.electron.txt','resources/ffprobe.exe','resources/FFmpeg-LICENSE.txt'):
			with self.subTest(name=name):
				path = self.release/name
				original = path.read_bytes()
				path.unlink()
				with self.assertRaises(ValueError): self.stage()
				self.assertFalse((self.root/'stage').exists())
				path.write_bytes(original)

	def test_tampered_runtime_media_and_asar_notice_are_rejected(self):
		for name in ('ffmpeg.dll','resources/avcodec-62.dll','resources/app.asar'):
			path = self.release/name
			original = path.read_bytes()
			path.write_bytes(b'tampered bytes')
			with self.assertRaises(ValueError): self.stage()
			path.write_bytes(original)
		(self.source/'NOTICE').write_bytes(b'changed source notice')
		with self.assertRaisesRegex(ValueError,'ASAR|notice'): self.stage()

	def test_extras_and_changed_electron_checksum_are_rejected(self):
		(self.release/'extra.dll').write_bytes(b'unreviewed')
		with self.assertRaisesRegex(ValueError,'[Uu]nreviewed|[Uu]nexpected'): self.stage()
		(self.release/'extra.dll').unlink()
		self.checksums.write_text('0'*64+' *'+self.electron.name+'\n')
		with self.assertRaisesRegex(ValueError,'checksum'): self.stage()

	def test_asar_metadata_must_match_source_even_when_archive_is_valid(self):
		(self.source/'package.json').write_text(json.dumps({'name':'other','productName':'Other','version':'9.0.0'}))
		with self.assertRaises(ValueError): self.stage()

	def rewrite_media_pin(self, rows):
		pin_path = self.source/'Release/ffmpeg-build.json'
		pin = json.loads(pin_path.read_text())
		pin['files'] = rows
		pin_path.write_text(json.dumps(pin))
		# Keep the actual ASAR source notice consistent: validation must enforce
		# the approved media set independently of a self-consistent reduced pin.
		self.make_asar()

	def test_rejects_reduced_pin_release_and_asar_even_when_self_consistent(self):
		rows = json.loads((self.source/'Release/ffmpeg-build.json').read_text())['files']
		self.rewrite_media_pin([row for row in rows if row['path'] in ('bin/ffmpeg.exe','bin/ffprobe.exe')])
		for row in rows:
			if row['path'].endswith('.dll'): (self.release/'resources'/Path(row['path']).name).unlink()
		with self.assertRaisesRegex(ValueError,'approved.*nine|nine.*approved'):
			self.stage()
		self.assertFalse((self.root/'stage').exists())

	def test_each_required_media_row_cannot_be_removed_with_its_payload(self):
		rows = json.loads((self.source/'Release/ffmpeg-build.json').read_text())['files']
		for dropped in rows:
			with self.subTest(path=dropped['path']):
				path = self.release/'resources'/Path(dropped['path']).name
				original = path.read_bytes()
				path.unlink()
				self.rewrite_media_pin([row for row in rows if row is not dropped])
				with self.assertRaises(ValueError): self.stage()
				self.assertFalse((self.root/'stage').exists())
				path.write_bytes(original)
		self.rewrite_media_pin(rows)

	def test_rejects_substituted_native_pin_and_payload_with_same_row_count(self):
		rows = json.loads((self.source/'Release/ffmpeg-build.json').read_text())['files']
		row = next(row for row in rows if row['path'] == 'bin/avcodec-62.dll')
		row['path'] = 'bin/ffplay.exe'
		(self.release/'resources/avcodec-62.dll').rename(self.release/'resources/ffplay.exe')
		self.rewrite_media_pin(rows)
		with self.assertRaisesRegex(ValueError,'approved.*nine|nine.*approved'):
			self.stage()
		self.assertFalse((self.root/'stage').exists())

	def test_rejects_duplicated_or_malformed_media_membership(self):
		rows = json.loads((self.source/'Release/ffmpeg-build.json').read_text())['files']
		for mutated in (rows + [rows[0]], rows[:-1] + [rows[0]], rows[:-1] + [{'path':['bin/avcodec-62.dll']}], rows[:-1] + [None]):
			with self.subTest(rows=mutated):
				self.rewrite_media_pin(mutated)
				with self.assertRaises(ValueError): self.stage()
				self.assertFalse((self.root/'stage').exists())

	def test_stage_rejects_links_case_aliases_and_unsafe_windows_names(self):
		link = self.release / 'linked.dll'
		try:
			link.symlink_to(self.release / 'libEGL.dll')
		except OSError as error:
			self.skipTest(f'symlink unavailable: {error}')
		with self.assertRaisesRegex(ValueError, 'link|reparse'):
			self.stage()
		link.unlink()
		alias = self.release / 'LIBEGL.dll'
		alias.write_bytes(b'alias')
		if alias.samefile(self.release / 'libEGL.dll'):
			# The default macOS filesystem is case-insensitive; ZIP verification covers
			# the synthetic two-entry alias case independently.
			alias.unlink()
			(self.release / 'libEGL.dll').write_bytes(b'native dependency')
		else:
			with self.assertRaisesRegex(ValueError, 'alias'):
				self.stage()
			alias.unlink()
		(self.release / 'resources/con.txt').write_bytes(b'unsafe')
		with self.assertRaisesRegex(ValueError, 'Windows path'):
			self.stage()

	@unittest.skipUnless(sys.platform == 'win32', 'native junction fixture requires Windows')
	def test_stage_rejects_windows_directory_reparse_point_without_symlink_privilege(self):
		target = self.root / 'junction-target'
		target.mkdir()
		junction = self.release / 'resources/reparse-fixture'
		result = subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(junction), str(target)], capture_output=True, text=True)
		if result.returncode:
			self.skipTest(f'junction creation unavailable: {result.stdout} {result.stderr}')
		self.addCleanup(lambda: junction.exists() and os.rmdir(junction))
		with self.assertRaisesRegex(ValueError, 'reparse'):
			self.stage()

	def test_root_symlinks_and_asar_links_are_rejected(self):
		linked = self.root/'linked-release'
		try: linked.symlink_to(self.release, target_is_directory=True)
		except OSError as error: self.skipTest(str(error))
		with self.assertRaisesRegex(ValueError,'link|reparse'):
			msix.stage_release(linked,self.artwork,self.root/'stage',self.commit,self.source,self.electron,self.checksums)
		asar_input = self.root/'asar-input'
		(asar_input/'linked-notice').symlink_to('NOTICE')
		module = Path(__file__).resolve().parents[2]/'node_modules/@electron/asar'
		subprocess.run(['node','-e',"require(process.argv[1]).createPackage(process.argv[2],process.argv[3]).catch(e=>process.exit(1))",str(module),str(asar_input),str(self.release/'resources/app.asar')],check=True)
		with self.assertRaisesRegex(ValueError,'ASAR.*|link'): self.stage()

	def test_staging_revalidates_actual_source_artwork_and_release_after_copy(self):
		original_copy = shutil.copyfileobj
		for target in (self.source/'NOTICE', self.artwork, self.release/'CutQuay.exe'):
			with self.subTest(target=target):
				before = target.read_bytes()
				changed = []
				def mutate_after_real_copy(src,dst,length=0):
					original_copy(src,dst,length)
					if not changed:
						target.write_bytes(b'changed after initial verification')
						changed.append(True)
				with patch.object(shutil,'copyfileobj',mutate_after_real_copy):
					with self.assertRaises(ValueError): self.stage()
				self.assertFalse((self.root/'stage').exists())
				target.write_bytes(before)

	def test_artwork_must_come_from_the_actual_original_svg(self):
		(self.source/'src/renderer/src/icon.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><rect width="512" height="512" fill="red"/></svg>')
		with self.assertRaisesRegex(ValueError,'Artwork'): self.stage()

	def test_electron_version_and_duplicate_zip_members_are_rejected(self):
		with zipfile.ZipFile(self.electron,'a') as archive: archive.writestr('version','42.11.4')
		self.checksums.write_text(sha(self.electron.read_bytes())+' *'+self.electron.name+'\n')
		with self.assertRaisesRegex(ValueError,'alias|version'): self.stage()

	def test_valid_asar_with_omitted_notice_and_wrong_app_version_is_rejected(self):
		asar_input = self.root/'asar-input'
		module = Path(__file__).resolve().parents[2]/'node_modules/@electron/asar'
		(asar_input/'NOTICE').unlink()
		subprocess.run(['node','-e',"require(process.argv[1]).createPackage(process.argv[2],process.argv[3]).catch(e=>process.exit(1))",str(module),str(asar_input),str(self.release/'resources/app.asar')],check=True)
		with self.assertRaisesRegex(ValueError,'ASAR'): self.stage()
		self.make_asar()
		pack = json.loads((asar_input/'package.json').read_text()); pack['version']='9.0.0'
		(asar_input/'package.json').write_text(json.dumps(pack))
		subprocess.run(['node','-e',"require(process.argv[1]).createPackage(process.argv[2],process.argv[3]).catch(e=>process.exit(1))",str(module),str(asar_input),str(self.release/'resources/app.asar')],check=True)
		with self.assertRaisesRegex(ValueError,'metadata mismatch'): self.stage()



class PackageVerificationTests(QualificationFixture):
	def package(self, mutate=None):
		record = self.stage()
		stage = self.root / 'stage'
		package = self.root / 'fixture.msix'
		with zipfile.ZipFile(package, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
			for path in sorted(stage.rglob('*')):
				if path.is_file():
					data = path.read_bytes()
					relative = path.relative_to(stage).as_posix()
					if mutate and relative == mutate[0]: data = mutate[1]
					archive.writestr(relative, data)
			archive.writestr('[Content_Types].xml', '<Types/>')
			archive.writestr('AppxBlockMap.xml', '<BlockMap/>')
		return package, record

	def test_independent_zip_verifier_accepts_exact_package(self):
		package, record = self.package()
		result = msix.verify_msix(package, record['payload'])
		self.assertEqual(len(record['payload']), result['verifiedPayloadFiles'])

	def test_signature_is_rejected_even_when_expected_payload_claims_it(self):
		package, record = self.package()
		for encoded, decoded in [('AppxSignature.p7x', 'AppxSignature.p7x'),
			('appxsignature.p7x', 'appxsignature.p7x'), ('Appx%53ignature.p7x', 'AppxSignature.p7x')]:
			with self.subTest(encoded=encoded):
				changed = self.root/'signed.msix';shutil.copyfile(package, changed)
				with zipfile.ZipFile(changed, 'a') as archive: archive.writestr(encoded, b'signature')
				expected = dict(record['payload']);expected[decoded] = {'bytes':9,'sha256':sha(b'signature')}
				with self.assertRaisesRegex(ValueError, 'contains a signature'): msix.verify_msix(changed, expected)

	def test_opc_encoded_names_match_exact_decoded_payload_bytes(self):
		package, record = self.package()
		# The Windows 10.0.26100.0 SDK encoded libc++.dll this way in run
		# 34596219976. A literal percent filename must be decoded only once.
		pairs = [('bin/libc%2B%2B.dll', 'bin/libc++.dll'),
			('share/R%C3%A9sum%C3%A9%20note.txt', 'share/Résumé note.txt'),
			('share/literal%2520.txt', 'share/literal%20.txt')]
		with zipfile.ZipFile(package, 'a') as archive:
			for encoded, decoded in pairs:
				data = ('owned bytes for ' + decoded).encode('utf-8')
				archive.writestr(encoded, data)
				record['payload'][decoded] = {'bytes': len(data), 'sha256': sha(data)}
		self.assertEqual(len(record['payload']), msix.verify_msix(package, record['payload'])['verifiedPayloadFiles'])

	def test_opc_decoding_rejects_aliases_traversal_and_malformed_names(self):
		package, record = self.package()
		for name in ('%43utQuay.exe', 'bin%2FCutQuay.exe', 'bin%5cCutQuay.exe',
			'bin/%2e%2e/escaped.txt', '%2Fabsolute.txt', 'share/bad%GG.txt',
			'share/bad%.txt', 'share/bad%FF.txt', 'share/bad%00.txt'):
			with self.subTest(name=name):
				changed = self.root / 'encoded-invalid.msix'
				shutil.copyfile(package, changed)
				with zipfile.ZipFile(changed, 'a') as archive:
					archive.writestr(name, b'unexpected')
				with self.assertRaises(ValueError):
					msix.verify_msix(changed, record['payload'])

	def test_independent_zip_verifier_rejects_tamper_and_manifest_semantics(self):
		package, record = self.package(('CutQuay.exe', b'tampered'))
		with self.assertRaisesRegex(ValueError, 'hash|size'):
			msix.verify_msix(package, record['payload'])
		shutil.rmtree(self.root / 'stage')
		bad = msix.create_manifest().replace(b'runFullTrust', b'internetClient')
		package, record = self.package(('AppxManifest.xml', bad))
		# Bind the tampered bytes to demonstrate that semantic checks are independent of hashes.
		record['payload']['AppxManifest.xml'] = {'bytes': len(bad), 'sha256': sha(bad)}
		with self.assertRaisesRegex(ValueError, 'capabilities'):
			msix.verify_msix(package, record['payload'])

	def test_independent_zip_verifier_rejects_case_alias(self):
		package, record = self.package()
		with zipfile.ZipFile(package, 'a') as archive:
			archive.writestr('CUTQUAY.exe', b'alias')
		with self.assertRaisesRegex(ValueError, 'alias'):
			msix.verify_msix(package, record['payload'])

	def test_independent_zip_verifier_rejects_unexpected_empty_directory(self):
		package, record = self.package()
		with zipfile.ZipFile(package, 'a') as archive:
			archive.writestr('unreviewed-empty/', b'')
		with self.assertRaisesRegex(ValueError, 'directory'):
			msix.verify_msix(package, record['payload'])

	def test_zip_rejects_file_directory_unicode_and_encoded_aliases(self):
		package,record = self.package()
		for name in ('CutQuay.exe/child','cutquay.exe','%43utQuay.exe','resources/app.asar/child',
			'resources/%2e%2e/x','resources/bad%FF','resources/bad%','resources/NUL.txt'):
			with self.subTest(name=name):
				candidate=self.root/'unsafe.msix'; shutil.copyfile(package,candidate)
				with zipfile.ZipFile(candidate,'a') as archive: archive.writestr(name,b'x')
				with self.assertRaises(ValueError): msix.verify_msix(candidate,record['payload'])
		with zipfile.ZipFile(package,'a') as archive:
			archive.writestr('resources/Résumé.txt',b'x')
			archive.writestr('resources/Re%CC%81sume%CC%81.txt',b'x')
		record['payload']['resources/Résumé.txt']={'bytes':1,'sha256':sha(b'x')}
		with self.assertRaisesRegex(ValueError,'alias'): msix.verify_msix(package,record['payload'])

	def test_sdk_unpacked_hashes_reject_changed_missing_and_extra_files(self):
		record=self.stage(); stage=self.root/'stage'
		for name,data in [('CutQuay.exe',b'changed'),('extra.dll',b'unreviewed')]:
			path=stage/name; before=path.read_bytes() if path.exists() else None
			path.write_bytes(data)
			with self.assertRaises(ValueError): msix.verify_unpacked(stage,record['payload'])
			if before is None: path.unlink()
			else: path.write_bytes(before)
		(stage/'resources/app.asar').unlink()
		with self.assertRaises(ValueError): msix.verify_unpacked(stage,record['payload'])



class SourceCheckoutTests(QualificationFixture):
	def test_git_commit_and_dirty_generated_notice_receipt_are_bound(self):
		def git(*args):
			return subprocess.run(['git','-C',str(self.source),*args],check=True,capture_output=True,text=True).stdout.strip()
		(self.source/'.gitignore').write_text('/build-evidence/\n')
		git('init','-q'); git('add','.')
		git('-c','user.name=Qualification Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture')
		commit=git('rev-parse','HEAD')
		msix.validate_source_checkout(self.source,commit)
		with self.assertRaisesRegex(ValueError,'commit'): msix.validate_source_checkout(self.source,'0'*40)
		(self.source/'NOTICE').write_bytes(b'dirty source')
		with self.assertRaisesRegex(ValueError,'checkout'): msix.validate_source_checkout(self.source,commit)
		git('restore','NOTICE')
		(self.source/'licenses.txt').write_bytes(b'generated on Windows')
		(self.source/'build-evidence').mkdir()
		receipt=self.source/'build-evidence/windows-startup.json'
		receipt.write_text(json.dumps({'source_commit':commit,'generated_notices_sha256':sha(b'generated on Windows')}))
		msix.validate_source_checkout(self.source,commit)
		(self.source/'licenses.txt').write_bytes(b'changed after native receipt')
		with self.assertRaisesRegex(ValueError,'receipt'): msix.validate_source_checkout(self.source,commit)



class BuildFlowTests(QualificationFixture):
	def setUp(self):
		super().setUp()
		self.sdk = self.root / 'Windows Kits/10/bin/10.0.26100.0/x64'
		self.sdk.mkdir(parents=True)
		self.makeappx = self.sdk / 'makeappx.exe'
		self.makeappx.write_bytes(b'fixture makeappx')
		self.output = self.root / 'qualification-output'
		self.commands = []

	def fake_sdk(self, command):
		self.commands.append(command)
		if command[1] == 'pack':
			stage = Path(command[command.index('/d') + 1])
			package = Path(command[command.index('/p') + 1])
			with zipfile.ZipFile(package, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
				for path in sorted(stage.rglob('*')):
					if path.is_file(): archive.write(path, path.relative_to(stage).as_posix())
				archive.writestr('[Content_Types].xml', '<Types/>')
				archive.writestr('AppxBlockMap.xml', '<BlockMap/>')
		elif command[1] == 'unpack':
			package = Path(command[command.index('/p') + 1])
			destination = Path(command[command.index('/d') + 1])
			with zipfile.ZipFile(package) as archive: archive.extractall(destination)
		else:
			raise AssertionError(command)

	def test_build_uses_semantic_sdk_pack_unpack_and_writes_false_claims(self):
		result = msix.build_qualification(
			self.release, self.artwork, self.commit, self.makeappx,
			'10.0.26100.0', self.output, self.fake_sdk, self.source, self.electron, self.checksums)
		self.assertEqual(self.output, result)
		self.assertEqual(['pack', 'unpack'], [command[1] for command in self.commands])
		self.assertIn('/v', self.commands[0])
		self.assertNotIn('/nv', self.commands[0])
		self.assertNotIn('/o', self.commands[0])
		record = json.loads((self.output / 'package-record.json').read_text())
		self.assertFalse(record['signed'])
		self.assertFalse(record['installationQualificationPassed'])
		self.assertFalse(record['publicRelease'])
		self.assertEqual(sha(self.makeappx.read_bytes()), record['makeAppx']['sha256'])
		package = self.output / 'CutQuay.Qualification_1.0.0.0_x64.msix'
		self.assertEqual(sha(package.read_bytes()), record['containerVerification']['package']['sha256'])

	def test_store_build_and_independent_verifiers_require_explicit_mode(self):
		msix.build_qualification(self.release, self.artwork, self.commit, self.makeappx,
			'10.0.26100.0', self.output, self.fake_sdk, self.source, self.electron, self.checksums,
			identity_mode='store')
		record = json.loads((self.output/'package-record.json').read_text())
		package = self.output/'CutQuay.Store_1.0.0.0_x64.msix'
		self.assertEqual('store', record['identityMode'])
		self.assertFalse(record['qualificationIdentityOnly'])
		self.assertTrue(record['storeIdentityUsed'])
		self.assertEqual('1659hashfunction.CutQuay', record['identity']['packageName'])
		for flag in ('licenseClearanceClaimed', 'publicRelease', 'signed', 'installationQualificationPassed'):
			self.assertIs(False, record[flag])
		self.assertEqual(sha(package.read_bytes()), record['containerVerification']['package']['sha256'])
		self.assertEqual(len(record['payload']), msix.verify_msix(package, record['payload'], identity_mode='store')['verifiedPayloadFiles'])
		unpacked = self.root/'store-unpacked'
		with zipfile.ZipFile(package) as archive: archive.extractall(unpacked)
		msix.verify_unpacked(unpacked, record['payload'], identity_mode='store')
		with self.assertRaisesRegex(ValueError, 'identity'): msix.verify_msix(package, record['payload'])
		with self.assertRaisesRegex(ValueError, 'identity'): msix.verify_unpacked(unpacked, record['payload'])
		# Even coherent manifest/hash substitution cannot switch the selected mode.
		manifest = msix.create_manifest()
		(unpacked/'AppxManifest.xml').write_bytes(manifest)
		payload = dict(record['payload'], **{'AppxManifest.xml': {'bytes':len(manifest),'sha256':sha(manifest)}})
		changed = self.root/'mode-confused.msix'
		with zipfile.ZipFile(package) as original, zipfile.ZipFile(changed, 'w') as target:
			for info in original.infolist():
				target.writestr(info, manifest if info.filename == 'AppxManifest.xml' else original.read(info))
		with self.assertRaisesRegex(ValueError, 'identity'): msix.verify_msix(changed, payload, identity_mode='store')
		with self.assertRaisesRegex(ValueError, 'identity'): msix.verify_unpacked(unpacked, payload, identity_mode='store')

	def test_build_rechecks_sdk_tool_and_refuses_existing_output(self):
		def changing_sdk(command):
			self.fake_sdk(command)
			if command[1] == 'pack': self.makeappx.write_bytes(b'changed makeappx')
		with self.assertRaisesRegex(ValueError, 'MakeAppx changed'):
			msix.build_qualification(
				self.release, self.artwork, self.commit, self.makeappx,
				'10.0.26100.0', self.output, changing_sdk, self.source, self.electron, self.checksums)
		self.assertFalse(self.output.exists())
		self.output.mkdir()
		marker = self.output / 'owner.txt'
		marker.write_text('preserve')
		with self.assertRaisesRegex(ValueError, 'already exists'):
			msix.build_qualification(
				self.release, self.artwork, self.commit, self.makeappx,
				'10.0.26100.0', self.output, self.fake_sdk, self.source, self.electron, self.checksums)
		self.assertEqual('preserve', marker.read_text())

	def test_build_rejects_makeappx_outside_exact_sdk_tail(self):
		wrong = self.root / '10.0.26100.0/x64/makeappx.exe'
		wrong.parent.mkdir(parents=True)
		wrong.write_bytes(b'fixture makeappx')
		with self.assertRaisesRegex(ValueError, 'SDK.*path'):
			msix.build_qualification(
				self.release, self.artwork, self.commit, wrong,
				'10.0.26100.0', self.output, self.fake_sdk, self.source, self.electron, self.checksums)


if __name__ == '__main__':
	unittest.main()
