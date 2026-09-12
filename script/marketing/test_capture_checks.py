import copy
import json
from pathlib import Path
import tempfile
import unittest

import capture_checks as checks


class CaptureChecksTests(unittest.TestCase):
    def test_historical_package_cannot_authorize_renamed_capture(self):
        self.assertEqual('CutQuay_1.0.0.0_x64.msix',checks.PACKAGE_NAME)
        self.assertEqual('CutQuay.exe',checks.LOCKED_IDENTITY['executable'])
        self.assertEqual('1.0.0.0',checks.LOCKED_IDENTITY['version'])
        with self.assertRaisesRegex(ValueError,'await a newly qualified exact package'):
            checks.assert_current_capture_binding()
        with self.assertRaisesRegex(ValueError,'await a newly qualified exact package'):
            checks.verify_inputs(None,None,None,None,None)

    def fixture(self):
        ready={'schema_version':1,'product':'CutQuay','store_upload_ready':True,'public_release':False,
            'source_commit':checks.SOURCE,'workflow_run_id':checks.RUN,'workflow_run_attempt':'1',
            'identity':checks.LOCKED_IDENTITY,'unsigned_package':dict(checks.PACKAGE,name=checks.PACKAGE_NAME),
            'evidence':{'build-evidence/msix-store-package-record.json':{'bytes':2,'sha256':'0'*64}}}
        installed={'source_commit':checks.SOURCE,'workflow_run_id':checks.RUN,'workflow_run_attempt':'1',
            'identity_mode':'store','package_full_name':checks.FULL_NAME,'unsigned_package_sha256':checks.PACKAGE['sha256'],
            'installation_qualification_passed':True,'export_workflow_tested':True,'uninstall_verified':True,
            'clean_close_verified':True,'certificate_private_key_exported':False,'primary_error':None,
            'cleanup_errors':[],'evidence_errors':[],'residual_package_full_names':[]}
        run={'id':int(checks.RUN),'head_sha':checks.SOURCE,'run_attempt':1,'conclusion':'success',
            'repository':{'full_name':'hashfunction/cutquay'},'path':'.github/workflows/windows.yml'}
        return ready,installed,run

    def test_pinned_package_and_receipt_reject_mode_run_partial_and_type_confusion(self):
        ready,installed,run=self.fixture()
        checks.validate_receipts(ready,installed,run)
        changes=[(0,'source_commit','a'*40),(0,'store_upload_ready',1),(0,'identity',{}),
            (1,'export_workflow_tested',False),(1,'unsigned_package_sha256','1'*64),
            (1,'cleanup_errors',['failed']),(1,'certificate_private_key_exported',True),
            (2,'conclusion','failure'),(2,'run_attempt',2),(2,'run_attempt',True)]
        for index,key,value in changes:
            rows=copy.deepcopy((ready,installed,run));rows[index][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):checks.validate_receipts(*rows)

    def test_actual_evidence_bytes_and_paths_are_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);metadata=root/'metadata';source=root/'source'
            metadata.mkdir();source.mkdir();(metadata/'receipt.json').write_bytes(b'{}')
            ready={'evidence':{'build-evidence/receipt.json':checks.digest(metadata/'receipt.json')}}
            checks.verify_evidence(ready,metadata,source)
            (metadata/'receipt.json').write_bytes(b'{ }')
            with self.assertRaisesRegex(ValueError,'evidence'):checks.verify_evidence(ready,metadata,source)
            for invalid in ('../escape','build-evidence/../../escape','C:/other','/absolute'):
                with self.subTest(invalid=invalid),self.assertRaises(ValueError):checks.verify_evidence({'evidence':{invalid:{}}},metadata,source)

    def test_media_pin_rejects_same_size_replacement(self):
        checks.validate_media(checks.MEDIA)
        for changed in (dict(checks.MEDIA,sha256='0'*64),dict(checks.MEDIA,bytes=checks.MEDIA['bytes']-1)):
            with self.assertRaises(ValueError):checks.validate_media(changed)

    def test_archive_member_paths_cannot_escape_download_root(self):
        for name in ('../x','C:/x','a/../../x','a\\x','/x','./x'):
            with self.subTest(name=name),self.assertRaises(ValueError):checks.relative_path(name)
        self.assertEqual('build-evidence/receipt.json',checks.relative_path('build-evidence/receipt.json'))


if __name__=='__main__':unittest.main()
