import io
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import prepare_capture as prepare
import capture_checks as checks


class ArtifactTests(unittest.TestCase):
    def test_historical_binding_blocks_before_any_download_or_output_creation(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(checks,'CAPTURE_PRODUCT','CutQuay'),patch.object(prepare,'gh_json',side_effect=AssertionError('network called')),patch.object(prepare.subprocess,'check_output',side_effect=AssertionError('checkout read')):
            output=Path(directory)/'output'
            with self.assertRaisesRegex(ValueError,'await a newly qualified exact package'):
                prepare.main(output,Path(directory)/'qualified')
            self.assertFalse(output.exists())

    def run_archive(self,entries,*,members=None,limit=100000,change=None):
        buffer=io.BytesIO()
        with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED) as archive:
            for name,data in entries:archive.writestr(name,data)
        raw=buffer.getvalue()
        info={'id':42,'name':'fixture','expired':False,'size_in_bytes':len(raw),
            'workflow_run':{'id':int(checks.RUN),'head_sha':checks.SOURCE}}
        if change:info.update(change)
        def download(*args,**kwargs):kwargs['stdout'].write(raw)
        with tempfile.TemporaryDirectory() as directory,patch.object(prepare,'gh_json',return_value=info),patch.object(prepare.subprocess,'run',side_effect=download):
            target=Path(directory)/'artifact';prepare.artifact(42,'fixture',target,limit,members)
            return {p.relative_to(target).as_posix():p.read_bytes() for p in target.rglob('*') if p.is_file()}

    def test_production_download_extraction_requires_exact_store_members_and_current_artifact(self):
        self.assertEqual({'package.msix':b'package','release-ready.json':b'{}'},self.run_archive(
            [('package.msix',b'package'),('release-ready.json',b'{}')],members=['package.msix','release-ready.json']))
        with self.assertRaisesRegex(ValueError,'unexpected files'):
            self.run_archive([('package.msix',b'package'),('private.pfx',b'secret')],members=['package.msix','release-ready.json'])
        for change in ({'expired':True},{'id':43},{'workflow_run':{'id':int(checks.RUN),'head_sha':'a'*40}}):
            with self.subTest(change=change),self.assertRaisesRegex(ValueError,'artifact identity'):
                self.run_archive([('one.json',b'{}')],change=change)

    def test_actual_zip_link_escape_and_expansion_are_rejected(self):
        link=zipfile.ZipInfo('linked');link.external_attr=(stat.S_IFLNK|0o777)<<16
        for entries in [[('../escape',b'x')],[(link,b'target')],[('large.json',b'x'*1000000)]]:
            with self.subTest(entries=str(entries)[:40]),self.assertRaises(ValueError):
                self.run_archive(entries,limit=20000)


if __name__=='__main__':unittest.main()
