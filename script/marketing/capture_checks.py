"""Pinned, read-only provenance checks for marketing captures, never qualification."""
# Copyright 2026 Trieflow LLC. MIT.
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'msix'))
import msix_qualification as msix

SOURCE='1f2d10d8237e684d5c04113c6c9fe3f199f2f5e6'
RUN='34681628290'
# Exact Cliptern package verified from successful Windows run34681628290.
CAPTURE_PRODUCT='Cliptern'
LOCKED_IDENTITY={'packageName': '1659hashfunction.CutQuay', 'publisher': 'CN=B6A2631A-FD32-45CC-AE12-82466975F528', 'publisherDisplayName': 'hashfunction', 'version': '1.0.1.0', 'architecture': 'x64', 'applicationId': 'CutQuay', 'executable': 'Cliptern.exe', 'deviceFamily': 'Windows.Desktop', 'minVersion': '10.0.19041.0', 'maxVersionTested': '10.0.26100.0', 'capability': 'runFullTrust'}
PACKAGE_NAME='Cliptern_1.0.1.0_x64.msix'
FULL_NAME='1659hashfunction.CutQuay_1.0.1.0_x64__r3hxytd7jt6c4'
PACKAGE={'bytes':260378239,'sha256':'db4cfd8eb24999260ce23557026c398701a536c2110db6f69950cc53dab34dfa'}
MEDIA={'bytes':81781205,'sha256':'d691a199035cc7d295210b286f8f6734893c7d4358d228081af6f0da98a56343'}
MEDIA_URL='https://upload.wikimedia.org/wikipedia/commons/a/a5/Spring_-_Blender_Open_Movie.webm'
ATTRIBUTION={'title':'Spring (2019)','creator':'Andy Goralczyk / Blender Foundation',
    'credit':'© Blender Foundation | cloud.blender.org/spring','license':'CC BY 4.0',
    'license_url':'https://creativecommons.org/licenses/by/4.0/',
    'official_license_url':'https://studio.blender.org/projects/spring/pages/about/',
    'distribution_page':'https://commons.wikimedia.org/wiki/File:Spring_-_Blender_Open_Movie.webm',
    'download_url':MEDIA_URL,'original':MEDIA,
    'use':'Unmodified source imported into Cliptern; 376–400 second selection exported losslessly. Real app screenshots include selected film frames. No endorsement implied.'}


def require(value,message):
    if not value:raise ValueError(message)


def digest(path):
    with msix._regular_stream(Path(path)) as stream:
        h=hashlib.sha256();size=0
        for chunk in iter(lambda:stream.read(1048576),b''):h.update(chunk);size+=len(chunk)
    return {'bytes':size,'sha256':h.hexdigest()}


def read_json(path):
    with msix._regular_stream(Path(path)) as stream:data=stream.read(16*1024*1024+1)
    require(len(data)<=16*1024*1024,'Oversized capture evidence')
    return json.loads(data.decode('utf-8-sig'))


def relative_path(name):
    require(isinstance(name,str) and name and '\\' not in name and ':' not in name
        and not name.startswith('/') and all(p not in ('','.','..') for p in name.split('/')),
        'Unsafe evidence/archive path')
    require(str(PurePosixPath(name))==name,'Noncanonical evidence/archive path')
    return name


def validate_receipts(ready,installed,run):
    require(run.get('id')==int(RUN) and run.get('head_sha')==SOURCE and type(run.get('run_attempt')) is int and run['run_attempt']==1
        and run.get('conclusion')=='success' and run.get('repository',{}).get('full_name')=='hashfunction/cutquay'
        and run.get('path')=='.github/workflows/windows.yml','Pinned successful qualification run differs')
    require(type(ready.get('schema_version')) is int and ready['schema_version']==1 and ready.get('product')==CAPTURE_PRODUCT
        and ready.get('store_upload_ready') is True and ready.get('public_release') is False
        and ready.get('identity')==LOCKED_IDENTITY
        and ready.get('unsigned_package')==dict(PACKAGE,name=PACKAGE_NAME),'Pinned unsigned Store readiness receipt differs')
    for receipt in (ready,installed):
        require(receipt.get('source_commit')==SOURCE and receipt.get('workflow_run_id')==RUN
            and receipt.get('workflow_run_attempt')=='1','Qualified package source/run differs')
    require(installed.get('identity_mode')=='store' and installed.get('package_full_name')==FULL_NAME
        and installed.get('unsigned_package_sha256')==PACKAGE['sha256'],'Qualified installation identity differs')
    for key in ('installation_qualification_passed','export_workflow_tested','uninstall_verified','clean_close_verified'):
        require(installed.get(key) is True,'Retained qualification is incomplete: '+key)
    for key in ('cleanup_errors','evidence_errors','residual_package_full_names'):
        require(installed.get(key)==[],'Retained qualification has unresolved state: '+key)
    require(installed.get('primary_error') is None and installed.get('certificate_private_key_exported') is False,
        'Retained qualification failed or leaked private signing inputs')
    require(isinstance(ready.get('evidence'),dict) and ready['evidence'],'Retained qualification evidence is absent')


def verify_evidence(ready,metadata,source):
    for name,expected in ready['evidence'].items():
        relative_path(name)
        actual=Path(metadata)/name.removeprefix('build-evidence/') if name.startswith('build-evidence/') else Path(source)/name
        require(digest(actual)==expected,'Retained evidence bytes differ: '+name)


def validate_media(actual):require(actual==MEDIA,'Pinned licensed source media differs')


def assert_current_capture_binding():
    require(CAPTURE_PRODUCT=='Cliptern' and LOCKED_IDENTITY==msix.STORE_IDENTITY,
        'Cliptern screenshots await a newly qualified exact package; historical CutQuay binding is retained')


def verify_inputs(package,ready_path,metadata,source,run):
    assert_current_capture_binding()
    require(digest(package)==PACKAGE,'Exact qualified package bytes differ')
    ready=read_json(ready_path);installed=read_json(Path(metadata)/'msix-store-install/installation-qualification.json')
    validate_receipts(ready,installed,run);verify_evidence(ready,metadata,source)
    record=read_json(Path(metadata)/'msix-store-package-record.json')
    require(record['sourceCommit']==SOURCE and record['identityMode']=='store' and record['identity']==LOCKED_IDENTITY,
        'Qualified package record identity differs')
    require(msix.verify_msix(Path(package),record['payload'],'store')==record['containerVerification'],
        'Actual unsigned container differs from retained exact payload')
    return record


if __name__=='__main__':
    import argparse
    import subprocess
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--inputs',type=Path,required=True);parser.add_argument('--qualified-source',type=Path,required=True)
    args=parser.parse_args()
    require(subprocess.check_output(['git','-C',str(args.qualified_source),'rev-parse','HEAD'],text=True).strip()==SOURCE,'Qualified source checkout differs')
    verify_inputs(args.inputs/'store'/PACKAGE_NAME,args.inputs/'store/release-ready.json',args.inputs/'metadata',args.qualified_source,read_json(args.inputs/'qualified-run.json'))
    validate_media(digest(args.inputs/'Spring - Blender Foundation.webm'))
    print('Verified fixed existing package, qualification receipt/evidence and licensed film; no new qualification claim.')
