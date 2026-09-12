"""Final publication authorization is separate from a provisional source inventory."""
import copy
import json
import unittest
from source_publication import validate_publication, digest
from source_publication_fixture import publication_files


class SourcePublicationTests(unittest.TestCase):
    def setUp(self):
        files=publication_files()
        self.manifest=files['native-source-manifest.json']
        self.publication=json.loads(files['native-source-publication.json'])
        self.pin={'archiveSha256':'9'*64,'ffmpegCommit':'7'*10}

    def validate(self):
        return validate_publication(self.manifest,json.dumps(self.publication).encode(),self.pin,'42.11.3')

    def test_finalized_publication_binds_manifest_assets_and_runtime(self):
        self.assertEqual(digest(self.manifest),self.validate()['manifest'])

    def test_absent_or_provisional_publication_does_not_authorize(self):
        for publication in ({},{'publication_verified':True},json.loads(self.manifest),
                dict(self.publication,publication_verified=False),dict(self.publication,publication_verified=1)):
            with self.subTest(publication=publication),self.assertRaises(ValueError):
                validate_publication(self.manifest,json.dumps(publication).encode(),self.pin,'42.11.3')

    def test_wrong_manifest_download_archive_or_runtime_rejects(self):
        original=copy.deepcopy(self.publication)
        for field,value in [('source_page','https://other.invalid'),('release_url','https://other.invalid'),
                ('assets',[]),('verified_at_utc','2026-09-12T00:00:00')]:
            with self.subTest(field=field):
                self.publication=dict(original,**{field:value})
                with self.assertRaises(ValueError):self.validate()
        self.publication=copy.deepcopy(original)
        for field,value in [('sha256','0'*64),('bytes',True),('url','https://other.invalid')]:
            with self.subTest(field=field):
                self.publication=copy.deepcopy(original);self.publication['assets'][0][field]=value
                with self.assertRaises(ValueError):self.validate()
        self.publication=copy.deepcopy(original);self.publication['manifest']['sha256']='0'*64
        with self.assertRaises(ValueError):self.validate()
        self.publication=original;self.pin['archiveSha256']='0'*64
        with self.assertRaises(ValueError):self.validate()


if __name__=='__main__':unittest.main()
