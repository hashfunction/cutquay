"""Retain only a fully qualified unsigned Store MSIX and a separate readiness receipt."""
# Copyright 2026 Trieflow LLC. MIT.
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import sys
from urllib.request import Request, urlopen

import msix_qualification as msix
from source_publication import MANIFEST_URL, SOURCE_FILES, digest, require, validate_publication
from store_workflow_evidence import validate_workflow

PACKAGE_NAME = 'Cliptern_1.0.1.0_x64.msix'
PACKAGE_FULL_NAME = '1659hashfunction.CutQuay_1.0.1.0_x64__r3hxytd7jt6c4'


def read_bytes(path):
    try:
        with msix._regular_stream(path) as stream:
            value=stream.read(16*1024*1024+1)
        require(len(value)<=16*1024*1024, 'Oversized release evidence')
        return value
    except OSError as error:
        raise ValueError(f'Required release evidence is unavailable: {path}') from error


def fetch_manifest():
    with urlopen(Request(MANIFEST_URL,headers={'User-Agent':'CutQuay-source-verification'}),timeout=30) as response:
        require(response.status==200, 'Published source manifest is unavailable')
        value=response.read(1024*1024+1)
    require(len(value)<=1024*1024, 'Published source manifest is oversized')
    return value


def expected_payload(current, artwork_data):
    # Packaging receipts cannot grant an arbitrary file membership in the
    # upload. Rebuild the complete allowlist from independently checked inputs.
    payload = dict(current)
    assets = {}
    for name, size in (('StoreLogo.png', 50), ('Square44x44Logo.png', 44), ('Square150x150Logo.png', 150)):
        relative = f'Assets/{name}'
        require(relative not in payload, 'Release collides with generated Store artwork')
        payload[relative] = digest(msix.resize_png(artwork_data, size))
        assets[relative] = dict(payload[relative], pixels=[size, size])
    require('AppxManifest.xml' not in payload, 'Release collides with generated Store manifest')
    payload['AppxManifest.xml'] = digest(msix.create_manifest('store'))
    return payload, assets


def export_store_package(package, source, release, artwork, electron_archive, checksums, output, commit, run_id, attempt):
    package,source,release,artwork,electron_archive,checksums,output=map(Path,
        (package,source,release,artwork,electron_archive,checksums,output))
    require(re.fullmatch('[0-9a-f]{40}',commit or '') and re.fullmatch('[1-9][0-9]*',run_id or '')
        and re.fullmatch('[1-9][0-9]*',attempt or ''), 'Exact source, run and attempt are required')
    require(not os.path.lexists(output), 'Store export output already exists')
    msix._reject_link(output.parent)
    msix.validate_source_checkout(source,commit)
    evidence_bytes={}
    def raw(relative):
        value=read_bytes(source/relative)
        require(relative not in evidence_bytes or evidence_bytes[relative]==value, 'Qualification evidence changed while reading')
        evidence_bytes[relative]=value
        return value
    def load(relative):
        value=raw(relative)
        try: return json.loads(value.decode('utf-8-sig'))
        except (UnicodeDecodeError,json.JSONDecodeError) as error: raise ValueError(f'Invalid release evidence: {relative}') from error
    try:
        record=load('build-evidence/msix-store-package-record.json')
        native=load('build-evidence/windows-startup.json')
        installed=load('build-evidence/msix-store-install/installation-qualification.json')
        workflow=load('build-evidence/msix-store-install/consumer-workflow.json')
        for receipt in (native,installed):
            require(receipt.get('source_commit')==commit and receipt.get('workflow_run_id')==run_id
                and receipt.get('workflow_run_attempt')==attempt, 'Receipt source/run/attempt differs')
        require(record.get('sourceCommit')==commit and record.get('identityMode')=='store'
            and record.get('identity')==msix.STORE_IDENTITY and record.get('storeIdentityUsed') is True
            and record.get('qualificationIdentityOnly') is False and record.get('signed') is False,
            'Only the exact unsigned Store identity may be exported')
        require(installed.get('identity_mode')=='store' and installed.get('identity')==msix.STORE_IDENTITY
            and installed.get('qualification_identity_only') is False and installed.get('store_identity_used') is True,
            'Store installation identity differs')
        for key in ('windows_native_startup',): require(native.get(key) is True, 'Native Windows startup did not pass')
        require(native.get('window_title')=='Cliptern 1.0.1', 'Native startup title differs')
        for key in ('add_appx_completed','registration_ownership_established','unsigned_package_unchanged',
                    'diagnostic_clean_close_verified','clean_close_verified','uninstall_verified',
                    'installation_qualification_passed','export_workflow_tested'):
            require(installed.get(key) is True, f'Store qualification gate did not pass: {key}')
        for key in ('package_full_name','owned_package_full_name','activated_process_package_full_name','diagnostic_process_package_full_name'):
            require(installed.get(key)==PACKAGE_FULL_NAME, f'Package ownership differs: {key}')
        for key in ('preflight_package_full_names','residual_package_full_names','cleanup_errors','evidence_errors'):
            require(installed.get(key)==[], f'Store qualification contains unresolved evidence: {key}')
        require(installed.get('primary_error') is None and installed.get('certificate_private_key_exported') is False,
            'Qualification failed or exported private signing material')
        require(installed.get('consumer_export_workflow')==workflow, 'Consumer receipt differs from completed installation')
        require(installed['media_worker']==workflow['verification_worker'], 'Installation final media worker differs')
        current=msix.inventory_tree(release)
        require(record['releaseInput']==current, 'Release runtime changed after packaging')
        require(record['runtime']==msix.validate_runtime(release,source,electron_archive,checksums,current,artwork),
            'Runtime/source provenance changed after packaging')
        exe=current['Cliptern.exe']['sha256']
        require(native['executable_sha256'].lower()==exe==installed['executable_sha256'], 'Native and installed executable hashes differ')
        require(native['generated_notices_sha256']==digest(read_bytes(source/'licenses.txt'))['sha256'], 'Generated notices changed after native qualification')
        artwork_data=read_bytes(artwork)
        payload,assets=expected_payload(current,artwork_data)
        require(record['payload']==payload and record['assets']==assets and record['artworkSource']==digest(artwork_data),
            'Package payload differs from current release/generated Store manifest/artwork allowlist')
        helpers={name:digest(raw('script/msix/'+name))['sha256']
            for name in ('qualify-msix-install.ps1','workflow-functions.ps1','workflowUi.mjs')}
        prefix='build-evidence/msix-store-install/'
        validate_workflow(workflow,commit,PACKAGE_FULL_NAME,payload,record['runtime'],
            lambda name:load(prefix+name),lambda name:raw(prefix+name),helpers)
        container=msix.verify_msix(package,payload,'store')
        require(container==record['containerVerification'] and container['package']['sha256']==installed['unsigned_package_sha256'],
            'Unsigned MSIX differs from installed qualification input')
        require(record['unpackedVerification']=={'verifiedPayloadFiles':len(payload)}, 'Exact SDK unpack verification is missing')
        source_files={name:read_bytes(source/'Release'/name) for name in SOURCE_FILES}
        for name,data in source_files.items():
            require(record['payload'].get('resources/'+name)==digest(data), 'Package source notice/publication differs')
        pin=load('Release/ffmpeg-build.json')
        publication=validate_publication(source_files['native-source-manifest.json'],source_files['native-source-publication.json'],
            pin,record['runtime']['electron']['version'])
        require(fetch_manifest()==source_files['native-source-manifest.json'], 'Remote published manifest differs from finalized source record')
        def verify_inputs_unchanged():
            for relative,data in evidence_bytes.items(): require(read_bytes(source/relative)==data, 'Qualification evidence changed during export')
            for name,data in source_files.items(): require(read_bytes(source/'Release'/name)==data, 'Source publication changed during export')
            require(msix.inventory_tree(release)==current, 'Release runtime changed during export')
            require(read_bytes(artwork)==artwork_data, 'Artwork changed during export')
            msix.validate_source_checkout(source,commit)
        # Recheck consumed inputs after the network request and after the copy.
        verify_inputs_unchanged()
        ready={'schema_version':1,'product':'Cliptern','store_upload_ready':True,'submitted':False,'public_release':False,
            'source_commit':commit,'application_source_url':f'https://github.com/hashfunction/cutquay/tree/{commit}',
            'workflow_run_id':run_id,'workflow_run_attempt':attempt,
            'workflow_url':f'https://github.com/hashfunction/cutquay/actions/runs/{run_id}',
            'generated_at_utc':datetime.now(timezone.utc).isoformat(),'identity':msix.STORE_IDENTITY,
            'unsigned_package':dict(container['package'],name=PACKAGE_NAME),
            'native_source_publication':publication,'evidence':{name:digest(data) for name,data in evidence_bytes.items()}}
        output.mkdir()
        try:
            with msix._regular_stream(package) as incoming, (output/PACKAGE_NAME).open('xb') as target:
                shutil.copyfileobj(incoming,target,1024*1024)
            require(msix.verify_msix(output/PACKAGE_NAME,payload,'store')==container, 'Retained unsigned package bytes changed')
            verify_inputs_unchanged()
            msix._write_new(output/'release-ready.json',msix._canonical_json(ready))
        except Exception:
            # This invocation exclusively owns these files; no readiness survives failure.
            for name in (PACKAGE_NAME,'release-ready.json'):
                (output/name).unlink(missing_ok=True)
            output.rmdir()
            raise
        return ready
    except (KeyError,TypeError,AttributeError,OSError) as error:
        raise ValueError('Incomplete Store qualification evidence') from error


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('package','source','release','artwork','electron-archive','checksums','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    require(sys.platform=='win32' and os.environ.get('CI')=='true' and os.environ.get('GITHUB_REPOSITORY')=='hashfunction/cutquay',
        'Store export requires the disposable Cliptern Windows workflow')
    export_store_package(args.package,args.source,args.release,args.artwork,args.electron_archive,args.checksums,args.output,
        os.environ.get('GITHUB_SHA'),os.environ.get('GITHUB_RUN_ID'),os.environ.get('GITHUB_RUN_ATTEMPT'))
    print('PASS: exact unsigned Store package retained after native, installed workflow, cleanup and source-publication verification')


if __name__=='__main__':
    try: main()
    except Exception as error:
        print(f'Store export refused: {error}',file=sys.stderr);sys.exit(1)
