"""Validate the finalized native-source publication without changing audit history."""
# Copyright 2026 Trieflow LLC. MIT.
import hashlib
import json
import re
from datetime import datetime

SOURCE_PAGE = 'https://cutquay.trieflow.com/source'
RELEASE_URL = 'https://github.com/hashfunction/cutquay/releases/tag/native-sources-2026-09-10'
DOWNLOAD_URL = 'https://github.com/hashfunction/cutquay/releases/download/native-sources-2026-09-10/'
MANIFEST_URL = DOWNLOAD_URL + 'source-manifest.json'
SOURCE_FILES = ('NATIVE-SOURCES.txt', 'native-source-manifest.json', 'native-source-publication.json')
ASSET_NAMES = {
    'cutquay-electron-ffmpeg-source-42.11.3.tar', 'cutquay-ffmpeg-core-and-build-source.tar',
    'cutquay-ffmpeg-dependency-source-part-1.tar', 'cutquay-ffmpeg-dependency-source-part-2.tar',
}


def require(condition, message):
    if not condition: raise ValueError(message)


def digest(data):
    return {'bytes':len(data), 'sha256':hashlib.sha256(data).hexdigest()}


def valid_digest(value):
    return isinstance(value,dict) and type(value.get('bytes')) is int and value['bytes'] > 0 \
        and isinstance(value.get('sha256'),str) and re.fullmatch('[0-9a-f]{64}',value['sha256'])


def validate_publication(manifest_bytes, publication_bytes, pin, electron_version):
    try:
        manifest=json.loads(manifest_bytes); publication=json.loads(publication_bytes)
        require(type(manifest.get('schema_version')) is int and manifest['schema_version']==1
            and manifest.get('product')=='CutQuay' and manifest.get('source_only') is True
            and manifest.get('source_page')==SOURCE_PAGE, 'Invalid native source manifest')
        require(type(publication.get('schema_version')) is int and publication['schema_version']==1
            and publication.get('product')=='CutQuay' and publication.get('publication_verified') is True
            and publication.get('source_page')==SOURCE_PAGE and publication.get('release_url')==RELEASE_URL,
            'Finalized native source publication is required')
        timestamp=datetime.fromisoformat(publication['verified_at_utc'].replace('Z','+00:00'))
        require(timestamp.utcoffset() is not None and timestamp.utcoffset().total_seconds()==0, 'Publication timestamp must be UTC')
        expected=publication['manifest']
        require(valid_digest(expected) and expected.get('url')==MANIFEST_URL
            and {k:expected[k] for k in ('bytes','sha256')}==digest(manifest_bytes), 'Published manifest digest differs')
        assets=manifest['assets']; published=publication['assets']
        require(isinstance(assets,list) and isinstance(published,list) and len(assets)==len(ASSET_NAMES)
            and len(published)==len(ASSET_NAMES), 'Incomplete published source archives')
        require({a['name'] for a in assets}==ASSET_NAMES and {a['name'] for a in published}==ASSET_NAMES,
            'Unexpected published source archives')
        for asset in assets:
            require(valid_digest(asset), 'Invalid source archive digest')
            remote=next(a for a in published if a['name']==asset['name'])
            require(valid_digest(remote) and remote.get('url')==DOWNLOAD_URL+asset['name']
                and all(remote[k]==asset[k] for k in ('bytes','sha256')), 'Published source archive differs')
        ffmpeg=manifest['command_line_ffmpeg']; electron=manifest['electron_ffmpeg']
        require(ffmpeg['binary_archive_sha256']==pin['archiveSha256']
            and re.fullmatch('[0-9a-f]{40}',ffmpeg['commit'])
            and ffmpeg['commit'].startswith(pin['ffmpegCommit']) and ffmpeg['license']=='GPL-3.0',
            'Published FFmpeg source does not match pinned runtime')
        require(electron['electron_version']==electron_version, 'Published Electron source version differs')
        configuration={'target_os':'win','target_cpu':'x64','ffmpeg_branding':'Chrome','proprietary_codecs':True,
            'CONFIG_GPL':0,'CONFIG_NONFREE':0,'CONFIG_VERSION3':0}
        actual=electron['normal_electron_configuration']
        require(actual==configuration and all(type(actual[k]) is type(v) for k,v in configuration.items()),
            'Published Electron configuration differs')
        return {'manifest':digest(manifest_bytes), 'publication':digest(publication_bytes),
            'release_url':RELEASE_URL, 'source_page':SOURCE_PAGE, 'assets':published}
    except (KeyError,TypeError,AttributeError,StopIteration,json.JSONDecodeError) as error:
        raise ValueError('Incomplete finalized native source publication') from error
