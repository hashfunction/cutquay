"""Download only fixed existing artifacts and licensed film; do not build any app."""
# Copyright 2026 Trieflow LLC. MIT.
import argparse
from datetime import datetime,timezone
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time
from urllib.request import Request,urlopen
import zipfile

import capture_checks as checks


def gh_json(endpoint):
    result=subprocess.run(['gh','api',endpoint],check=True,capture_output=True,timeout=30)
    checks.require(len(result.stdout)<=1024*1024,'GitHub metadata exceeds bound')
    return json.loads(result.stdout)


def write_json(path,value):
    with Path(path).open('x',encoding='utf-8') as stream:json.dump(value,stream,indent=2);stream.write('\n')


def artifact(number,name,root,max_bytes,exact_members=None):
    endpoint=f'repos/hashfunction/cutquay/actions/artifacts/{number}'
    info=gh_json(endpoint)
    checks.require(info['id']==number and info['name']==name and info['expired'] is False
        and info['workflow_run']['id']==int(checks.RUN) and info['workflow_run']['head_sha']==checks.SOURCE
        and 0<info['size_in_bytes']<=max_bytes,'Pinned artifact identity/size differs')
    archive=root.with_suffix('.zip')
    with archive.open('xb') as stream:
        # gh handles the authenticated GitHub -> signed artifact redirect without
        # forwarding a repository token to arbitrary user-controlled hosts.
        subprocess.run(['gh','api',endpoint+'/zip'],stdout=stream,check=True,timeout=120)
    checks.require(archive.stat().st_size<=max_bytes,'Artifact download exceeds bound')
    root.mkdir()
    try:
        with zipfile.ZipFile(archive) as incoming:
            entries=incoming.infolist();names=[entry.filename for entry in entries]
            checks.require(len(names)==len(set(names)) and len(names)<=300,'Duplicate/oversized artifact inventory')
            if exact_members is not None:checks.require(set(names)==set(exact_members),'Store artifact has unexpected files')
            checks.require(sum(e.file_size for e in entries)<=max_bytes,'Expanded artifact exceeds bound')
            for entry in entries:
                checks.relative_path(entry.filename)
                checks.require(not entry.is_dir() and not stat.S_ISLNK(entry.external_attr>>16),'Artifact must contain regular files')
                target=root/entry.filename;target.parent.mkdir(parents=True,exist_ok=True)
                with incoming.open(entry) as source,target.open('xb') as dest:shutil.copyfileobj(source,dest,1048576)
    finally:archive.unlink()
    return info


def film(destination):
    deadline=time.monotonic()+120;size=0
    with urlopen(Request(checks.MEDIA_URL,headers={'User-Agent':'CutQuay-marketing-capture/1.0'}),timeout=20) as source,destination.open('xb') as target:
        checks.require(source.status==200 and source.url==checks.MEDIA_URL,'Licensed film download redirected or failed')
        while chunk:=source.read(1048576):
            size+=len(chunk)
            checks.require(size<=checks.MEDIA['bytes'] and time.monotonic()<deadline,'Film download exceeds bound')
            target.write(chunk)
    checks.validate_media(checks.digest(destination))


def main(output,qualified):
    checks.require(sys.platform=='win32' and os.environ.get('CI')=='true'
        and os.environ.get('GITHUB_REPOSITORY')=='hashfunction/cutquay','Screenshot inputs require isolated CutQuay Windows CI')
    commit=subprocess.check_output(['git','-C',str(qualified),'rev-parse','HEAD'],text=True).strip()
    checks.require(commit==checks.SOURCE,'Qualified source checkout differs')
    checks.msix._reject_link(output.parent);output.mkdir()
    run=gh_json(f'repos/hashfunction/cutquay/actions/runs/{checks.RUN}')
    store=output/'store';metadata=output/'metadata'
    package_artifact=artifact(10291595359,'CutQuay-Store-unsigned',store,280000000,[checks.PACKAGE_NAME,'release-ready.json'])
    metadata_artifact=artifact(10291385779,'CutQuay-Windows-qualification',metadata,16000000)
    checks.verify_inputs(store/checks.PACKAGE_NAME,store/'release-ready.json',metadata,qualified,run)
    write_json(output/'qualified-run.json',run)
    media=output/'Spring - Blender Foundation.webm';film(media)
    write_json(output/'media-attribution.json',checks.ATTRIBUTION)
    write_json(output/'capture-inputs.json',{'schema_version':1,'purpose':'marketing screenshots only',
        'consumer_acceptance':False,'capture_source_commit':os.environ['GITHUB_SHA'],
        'capture_run_id':os.environ['GITHUB_RUN_ID'],'qualified_source_commit':checks.SOURCE,
        'qualified_run_id':checks.RUN,'qualified_run_attempt':'1','unsigned_package':checks.PACKAGE,
        'package_artifact':package_artifact,'metadata_artifact':metadata_artifact,
        'readiness_receipt':checks.digest(store/'release-ready.json'),'attribution':checks.ATTRIBUTION,
        'verified_at_utc':datetime.now(timezone.utc).isoformat()})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--qualified-source',type=Path,required=True)
    args=parser.parse_args();main(args.output,args.qualified_source)
