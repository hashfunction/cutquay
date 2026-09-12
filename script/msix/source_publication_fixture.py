"""Tiny publication records for tests; never production release authorization."""
import json
from source_publication import ASSET_NAMES, DOWNLOAD_URL, MANIFEST_URL, RELEASE_URL, SOURCE_PAGE, digest


def publication_files():
    assets=[{'name':name,'bytes':100,'sha256':'8'*64} for name in sorted(ASSET_NAMES)]
    manifest={'schema_version':1,'product':'CutQuay','source_only':True,'source_page':SOURCE_PAGE,
        'assets':assets, 'command_line_ffmpeg':{'commit':'7'*40,'binary_archive_sha256':'9'*64,'license':'GPL-3.0'},
        'electron_ffmpeg':{'electron_version':'42.11.3','normal_electron_configuration':{
            'target_os':'win','target_cpu':'x64','ffmpeg_branding':'Chrome','proprietary_codecs':True,
            'CONFIG_GPL':0,'CONFIG_NONFREE':0,'CONFIG_VERSION3':0}}}
    raw=json.dumps(manifest).encode()
    publication={'schema_version':1,'product':'CutQuay','publication_verified':True,
        'source_page':SOURCE_PAGE,'release_url':RELEASE_URL,'verified_at_utc':'2026-09-12T00:00:00Z',
        'manifest':dict(digest(raw),url=MANIFEST_URL),
        'assets':[dict(asset,url=DOWNLOAD_URL+asset['name']) for asset in assets]}
    return {'native-source-manifest.json':raw,'native-source-publication.json':json.dumps(publication).encode()}
