"""Exercise the actual unsigned Store exporter with real tiny MSIX payloads."""
import copy
import json
import shutil
import tempfile
from pathlib import Path
import unittest
import zipfile
from unittest.mock import patch

from test_msix_qualification import QualificationFixture, sha
import msix_qualification as msix
import export_store_package as export
from store_workflow_fixture import workflow_fixture, json_bytes


class StoreExportTests(QualificationFixture):
    def setUp(self):
        super().setUp()
        self.evidence = self.source / 'build-evidence'
        self.install = self.evidence / 'msix-store-install'
        self.install.mkdir(parents=True)
        self.run_id, self.attempt = '123456', '1'
        self.package = self.root / 'Cliptern.Store_1.0.1.0_x64.msix'
        self.record = msix.stage_release(self.release, self.artwork, self.root / 'stage', self.commit,
            self.source, self.electron, self.checksums, 'store')
        self.write_package()
        self.record['containerVerification'] = msix.verify_msix(self.package, self.record['payload'], 'store')
        self.record['unpackedVerification'] = {'verifiedPayloadFiles': len(self.record['payload'])}
        self.full_name = '1659hashfunction.CutQuay_1.0.1.0_x64__r3hxytd7jt6c4'
        self.workflow, self.workflow_records = workflow_fixture(self.source, self.commit,
            self.record['runtime'], self.record['payload'], self.full_name)
        self.native = {'source_commit':self.commit, 'workflow_run_id':self.run_id, 'workflow_run_attempt':self.attempt,
            'windows_native_startup':True, 'window_title':'Cliptern 1.0.1',
            'executable_sha256':self.record['payload']['Cliptern.exe']['sha256'].upper(),
            'generated_notices_sha256':sha((self.source/'licenses.txt').read_bytes())}
        self.receipt = {'source_commit':self.commit, 'workflow_run_id':self.run_id, 'workflow_run_attempt':self.attempt,
            'identity_mode':'store', 'identity':msix.STORE_IDENTITY, 'qualification_identity_only':False,
            'store_identity_used':True, 'add_appx_completed':True, 'registration_ownership_established':True,
            'package_full_name':self.full_name, 'owned_package_full_name':self.full_name,
            'activated_process_package_full_name':self.full_name, 'diagnostic_process_package_full_name':self.full_name,
            'unsigned_package_sha256':self.record['containerVerification']['package']['sha256'],
            'unsigned_package_unchanged':True, 'executable_sha256':self.native['executable_sha256'].lower(),
            'diagnostic_clean_close_verified':True, 'clean_close_verified':True, 'uninstall_verified':True,
            'installation_qualification_passed':True, 'export_workflow_tested':True,
            'preflight_package_full_names':[], 'residual_package_full_names':[],
            'primary_error':None, 'cleanup_errors':[], 'evidence_errors':[], 'certificate_private_key_exported':False,
            'media_worker':self.workflow['verification_worker'], 'consumer_export_workflow':self.workflow,
            'workflow_acceptance':False, 'license_clearance_claimed':False, 'public_release':False}
        self.output = self.root / 'store-upload'
        self.write_evidence()

    def write_package(self, extra=None):
        with zipfile.ZipFile(self.package,'w') as z:
            for name in self.record['payload']: z.write(self.root/'stage'/name,name)
            z.writestr('[Content_Types].xml','types')
            z.writestr('AppxBlockMap.xml','blocks')
            if extra: z.writestr(extra,b'unexpected')

    def write_evidence(self):
        for name, value in self.workflow_records.items():
            path = self.install/name
            path.parent.mkdir(exist_ok=True, parents=True)
            path.write_bytes(json_bytes(value))
        for path,value in [(self.evidence/'msix-store-package-record.json',self.record),
            (self.evidence/'windows-startup.json',self.native),
            (self.install/'installation-qualification.json',self.receipt),
            (self.install/'consumer-workflow.json',self.workflow)]:
            path.write_text(json.dumps(value))

    def run_export(self):
        # Only network publication and git checkout are substituted. Real source,
        # ASAR, Electron, media, notice and MSIX verification all execute.
        with patch.object(msix,'validate_source_checkout'), patch.object(export,'fetch_manifest',
                return_value=(self.source/'Release/native-source-manifest.json').read_bytes()):
            return export.export_store_package(self.package,self.source,self.release,self.artwork,
                self.electron,self.checksums,self.output,self.commit,self.run_id,self.attempt)

    def test_only_verified_unsigned_store_package_and_separate_receipt_are_exported(self):
        receipt=self.run_export()
        self.assertEqual({export.PACKAGE_NAME,'release-ready.json'}, {p.name for p in self.output.iterdir()})
        self.assertEqual(self.package.read_bytes(), (self.output/export.PACKAGE_NAME).read_bytes())
        self.assertTrue(receipt['store_upload_ready'])
        self.assertFalse(self.receipt['workflow_acceptance'])
        self.assertFalse(self.record['licenseClearanceClaimed'])
        for name in ('workflow-export/consumer-export-report.json', 'verify-media/probe-output-native.json',
                'workflow-reopen/driver.json', 'generate-media/media-worker-ready.json'):
            self.assertEqual(export.digest((self.install/name).read_bytes()),
                receipt['evidence']['build-evidence/msix-store-install/'+name])

    def test_failed_or_stale_receipts_never_create_export_directory(self):
        cases=[('source_commit','2'*40),('workflow_run_id','previous'),('workflow_run_attempt','2'),
            ('identity_mode','qualification'),('unsigned_package_sha256','0'*64),('installation_qualification_passed',False),
            ('installation_qualification_passed',1),('uninstall_verified',False),('clean_close_verified',False),
            ('export_workflow_tested',False),('registration_ownership_established',False),
            ('residual_package_full_names',['foreign']),('cleanup_errors',['cleanup failed']),
            ('evidence_errors',['write failed']),('primary_error','failed'),('certificate_private_key_exported',True),
            ('owned_package_full_name','foreign'),('activated_process_package_full_name','foreign')]
        original=copy.deepcopy(self.receipt)
        for field,value in cases:
            with self.subTest(field=field,value=value):
                self.receipt=copy.deepcopy(original);self.receipt[field]=value;self.write_evidence()
                with self.assertRaises(ValueError): self.run_export()
                self.assertFalse(self.output.exists())

    def test_workflow_or_native_binding_failure_rejects(self):
        self.workflow['reopen_ui']['persistedRecipeApplied']=False
        self.write_evidence()
        with self.assertRaises(ValueError): self.run_export()
        self.workflow['reopen_ui']['persistedRecipeApplied']=True
        self.native['executable_sha256']='0'*64
        self.write_evidence()
        with self.assertRaises(ValueError): self.run_export()
        self.assertFalse(self.output.exists())

    def test_signed_package_or_changed_payload_rejects(self):
        for extra in ['AppxSignature.p7x','foreign.exe']:
            with self.subTest(extra=extra):
                self.write_package(extra)
                with self.assertRaises(ValueError): self.run_export()
                self.assertFalse(self.output.exists())

    def test_coherent_package_receipts_cannot_replace_current_release_or_add_signing_material(self):
        original = copy.deepcopy(self.record)
        for relative in ('Cliptern.exe', 'Assets/StoreLogo.png', 'temporary/private-key.pfx', 'AppxSignature.p7x'):
            with self.subTest(relative=relative):
                if self.output.exists(): shutil.rmtree(self.output)
                self.record = copy.deepcopy(original)
                path = self.root/'stage'/relative
                before = path.read_bytes() if path.exists() else None
                path.parent.mkdir(exist_ok=True, parents=True);path.write_bytes(b'coherent foreign payload')
                self.record['payload'][relative] = export.digest(path.read_bytes())
                self.write_package()
                # Deliberately fabricate mutually consistent package receipts;
                # only an independently rebuilt current-source allowlist catches this.
                self.record['containerVerification'] = {'verifiedPayloadFiles': len(self.record['payload']),
                    'metadata': ['AppxBlockMap.xml', '[Content_Types].xml'], 'package': export.digest(self.package.read_bytes())}
                self.record['unpackedVerification'] = {'verifiedPayloadFiles': len(self.record['payload'])}
                self.receipt['unsigned_package_sha256'] = self.record['containerVerification']['package']['sha256']
                self.write_evidence()
                with self.assertRaises(ValueError): self.run_export()
                self.assertFalse(self.output.exists())
                if before is None: path.unlink()
                else: path.write_bytes(before)

    def test_inconsistent_consumer_facts_cannot_be_hidden_by_passed_flags(self):
        cases = [('input', lambda: self.workflow['export_ui'].update(inputHash={'bytes':456,'sha256':'0'*64})),
            ('trim', lambda: self.workflow_records['workflow-export/consumer-export-report.json']['segments'][0].update(requestedEnd=8)),
            ('recipe', lambda: self.workflow['export_ui']['recipe'].update(outFormat='avi')),
            ('duration', lambda: self.workflow['media']['probe']['format'].update(duration='999')),
            ('streams', lambda: self.workflow['media']['probe'].update(streams=[])),
            ('broker', lambda: self.workflow['export_ui'].update(brokerProcessId=-1)),
            ('helper', lambda: self.workflow['generation_worker'].update(helper_sha256='0'*64)),
            ('worker_result', lambda: self.workflow_records['verify-media/media-worker-result.json'].update(primary_error='failed')),
            ('decoder', lambda: self.workflow_records['verify-media/decode-output-native.json'].update(exit_code=1))]
        baseline = copy.deepcopy((self.workflow, self.workflow_records))
        for name, mutate in cases:
            with self.subTest(name=name):
                if self.output.exists(): shutil.rmtree(self.output)
                self.workflow, self.workflow_records = copy.deepcopy(baseline)
                self.receipt['consumer_export_workflow'] = self.workflow
                self.receipt['media_worker'] = self.workflow['verification_worker']
                mutate()
                # Keep all container/summary/raw-report receipts coherent so
                # the operation constraints, not a stale digest, reject it.
                self.workflow['export_ui']['reportHash'] = export.digest(json_bytes(
                    self.workflow_records['workflow-export/consumer-export-report.json']))
                self.write_evidence()
                with self.assertRaises(ValueError): self.run_export()
                self.assertFalse(self.output.exists())

    def test_standalone_required_evidence_cannot_be_omitted(self):
        for name in ('workflow-export/export-ui-result.json', 'workflow-export/saved-recipe.json',
            'verify-media/media-worker-authorized.json', 'verify-media/probe-output-native.json'):
            with self.subTest(name=name):
                if self.output.exists(): shutil.rmtree(self.output)
                self.write_evidence();(self.install/name).unlink()
                with self.assertRaises(ValueError): self.run_export()
                self.assertFalse(self.output.exists())

    def test_missing_or_unpublished_source_record_rejects(self):
        path=self.source/'Release/native-source-publication.json'
        original=path.read_bytes();path.unlink()
        with self.assertRaises(ValueError): self.run_export()
        value=json.loads(original);value['publication_verified']=False;path.write_text(json.dumps(value))
        with self.assertRaises(ValueError): self.run_export()
        self.assertFalse(self.output.exists())

    def test_different_remote_manifest_rejects(self):
        with patch.object(msix,'validate_source_checkout'), patch.object(export,'fetch_manifest',return_value=b'changed'):
            with self.assertRaises(ValueError):
                export.export_store_package(self.package,self.source,self.release,self.artwork,self.electron,self.checksums,
                    self.output,self.commit,self.run_id,self.attempt)
        self.assertFalse(self.output.exists())

    def test_receipt_changed_during_copy_leaves_no_upload(self):
        original_copy=export.shutil.copyfileobj
        def copy_then_change_receipt(incoming,target,length):
            original_copy(incoming,target,length)
            (self.install/'installation-qualification.json').write_text('{}')
        with patch.object(export.shutil,'copyfileobj',side_effect=copy_then_change_receipt):
            with self.assertRaises(ValueError):self.run_export()
        self.assertFalse(self.output.exists())

    def test_consumed_worker_record_changed_during_copy_leaves_no_upload(self):
        original_copy=export.shutil.copyfileobj
        def copy_then_change_worker(incoming,target,length):
            original_copy(incoming,target,length)
            (self.install/'generate-media/media-worker-ready.json').write_text('{}')
        with patch.object(export.shutil,'copyfileobj',side_effect=copy_then_change_worker):
            with self.assertRaisesRegex(ValueError, 'evidence changed'): self.run_export()
        self.assertFalse(self.output.exists())

    def test_original_electron_license_and_source_notice_are_required(self):
        for relative in ('LICENSES.chromium.html','resources/NATIVE-SOURCES.txt'):
            path=self.release/relative;original=path.read_bytes();path.write_bytes(b'changed notice')
            with self.subTest(relative=relative),self.assertRaises(ValueError):self.run_export()
            path.write_bytes(original)
        self.assertFalse(self.output.exists())

    def test_output_collision_is_preserved(self):
        self.output.mkdir();(self.output/'unowned.txt').write_text('preserve')
        with self.assertRaises(ValueError): self.run_export()
        self.assertEqual('preserve',(self.output/'unowned.txt').read_text())


class WorkflowEvidenceTests(unittest.TestCase):
    """Exercise the production boundary directly for independent coherent mutations."""
    def setUp(self):
        temporary = tempfile.TemporaryDirectory();self.addCleanup(temporary.cleanup)
        self.source = Path(temporary.name)
        self.commit = '1'*40
        self.runtime = {'media': {'version': 'n8.1.2-fixture', 'configuration': '--enable-gpl --enable-shared --extra-version=20260910'}}
        self.payload = {name: {'bytes': 3, 'sha256': str(i)*64} for i, name in enumerate(
            ('Cliptern.exe', 'resources/ffmpeg.exe', 'resources/ffprobe.exe'), 1)}
        self.workflow, self.records = workflow_fixture(self.source, self.commit, self.runtime, self.payload, export.PACKAGE_FULL_NAME)
        self.records['workflow-export/consumer-export-report.json']['effective']['ffmpegVersion'] += '-20260910'
        self.helpers = {name:export.digest((self.source/'script/msix'/name).read_bytes())['sha256']
            for name in ('qualify-msix-install.ps1', 'workflow-functions.ps1', 'workflowUi.mjs')}

    def validate(self):
        self.workflow['export_ui']['reportHash'] = export.digest(json_bytes(self.records['workflow-export/consumer-export-report.json']))
        return export.validate_workflow(self.workflow, self.commit, export.PACKAGE_FULL_NAME, self.payload, self.runtime,
            self.records.__getitem__, lambda name:json_bytes(self.records[name]), self.helpers)

    def test_complete_evidence_with_pinned_extra_version_passes(self):
        self.validate()

    def test_native_identity_unavailable_only_after_observed_exit_still_passes(self):
        row = self.records['verify-media/decode-output-native.json']
        for key, field in [('image', 'process_image_path'), ('package', 'package_full_name')]:
            row[field] = None
            row['process_identity'][key] = {'status':'unavailable_after_observed_exit', 'value':None,
                'process_exit_observed':True, 'error':{'type':'System.ComponentModel.Win32Exception', 'message':'Process exited', 'native_error_code':6}}
        self.validate()
        row['process_identity']['image']['process_exit_observed'] = False
        with self.assertRaisesRegex(ValueError, 'without observed exit'): self.validate()

    def test_coherent_media_trim_recipe_and_runtime_mutations_are_rejected(self):
        cases = [
            ('trim', lambda: self.records['workflow-export/consumer-export-report.json']['segments'][0].update(requestedEnd=8)),
            ('command_trim', lambda: self.records['workflow-export/consumer-export-report.json']['commands'][0].__setitem__(1, '0.000000')),
            ('recipe', lambda: self.workflow['export_ui']['recipe'].update(outFormat='avi')),
            ('version', lambda: self.records['workflow-export/consumer-export-report.json']['effective'].update(ffmpegVersion='n8.1.2-fixture-other')),
            ('config', lambda: self.records['workflow-export/consumer-export-report.json']['effective'].update(ffmpegConfiguration='--disable-gpl')),
            ('duration', lambda: self.workflow['media']['probe']['format'].update(duration='8')),
            ('missing_stream', lambda: self.workflow['media']['probe']['streams'].pop()),
            ('codec', lambda: self.workflow['media']['probe']['streams'][0].update(codec_name='hevc')),
            ('reopen_duration', lambda: self.workflow['reopen_ui'].update(reopenedDuration=999)),
            ('ui_trim', lambda: self.records['workflow-export/trim-entered.json']['inputs'][0].update(value='00:00:00.000')),
            ('saved_recipe_selection', lambda: self.records['workflow-reopen/persisted-recipe-reapplied.json']['selects'][0].update(value='current')),
        ]
        baseline = copy.deepcopy((self.workflow, self.records))
        for name, mutate in cases:
            with self.subTest(name=name):
                self.workflow, self.records = copy.deepcopy(baseline)
                mutate()
                # Keep standalone probe stdout and nested media mutually
                # consistent; wrong media must fail the actual trim contract.
                self.records['verify-media/probe-output-native.json']['stdout'] = json.dumps(self.workflow['media']['probe'])
                with self.assertRaises(ValueError): self.validate()

    def test_worker_driver_and_native_provenance_mutations_are_rejected(self):
        cases = [
            ('helper', lambda: self.workflow['generation_worker'].update(helper_sha256='0'*64)),
            ('workflow_helper', lambda: self.workflow['verification_worker'].update(workflow_helper_sha256='0'*64)),
            ('authorization_pid', lambda: self.records['generate-media/media-worker-authorized.json'].update(process_id=987)),
            ('nonce', lambda: self.records['verify-media/media-worker-result.json'].update(nonce='0'*32)),
            ('input', lambda: self.records['verify-media/media-worker-result.json'].update(input_sha256='0'*64)),
            ('worker_failure', lambda: self.records['generate-media/media-worker-result.json'].update(cleanup_errors=['failure'])),
            ('driver_source', lambda: self.records['workflow-export/driver.json'].update(driver_sha256='0'*64)),
            ('driver_pid', lambda: self.records['workflow-export/driver.json'].update(broker_process_id=12345)),
            ('driver_loopback', lambda: self.records['workflow-reopen/driver.json'].update(loopback_listener_verified=False)),
            ('driver_recipe_config', lambda: self.records['workflow-reopen/driver.json']['arguments'].__setitem__(3, '--config-dir=D:\\another-config')),
            ('exe_hash', lambda: self.records['workflow-export/loaded-modules.json'][0].update(sha256='0'*64)),
            ('native_hash', lambda: self.records['verify-media/decode-output-native.json'].update(executable_sha256='0'*64)),
            ('native_arguments', lambda: self.records['verify-media/decode-output-native.json']['arguments'].remove('-xerror')),
            ('native_exit', lambda: self.records['verify-media/decode-output-native.json'].update(exit_code=1)),
            ('native_image', lambda: self.records['verify-media/decode-output-native.json']['process_identity']['image'].update(value=r'C:\foreign\ffmpeg.exe')),
        ]
        baseline = copy.deepcopy((self.workflow, self.records))
        for name, mutate in cases:
            with self.subTest(name=name):
                self.workflow, self.records = copy.deepcopy(baseline);mutate()
                with self.assertRaises(ValueError): self.validate()


if __name__ == '__main__': unittest.main()
