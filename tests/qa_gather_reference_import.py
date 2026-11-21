from pathlib import Path
import json, subprocess, sys, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]

class ImportTests(unittest.TestCase):
    def test_staging_replay_and_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp)
            incoming=base/'in'
            incoming.mkdir()
            for kind in ('herbalism','mining','fishing'):
                document=dict(data=dict(profession=kind,zones=[],nodes=[],pools=[],
                    url='https://foreverdb.net/profession/'+kind),
                    meta=dict(build='1.60.1.70959',attribution='ForeverDB',client='invented-client'))
                (incoming/(kind+'.json')).write_text(json.dumps(document))
            importer=ROOT/'tools/import_foreverdb_gathering.py'
            output=base/'staged'
            def run(target):
                return subprocess.run([sys.executable,'-B',str(importer),str(incoming),str(target)],
                                      capture_output=True,text=True)
            self.assertEqual(run(output).returncode,0)
            old=(output/'GatheringReferenceData.lua').read_bytes()
            self.assertNotIn(b'invented-client',old)
            self.assertIn('Unchanged',run(output).stdout)
            (incoming/'mining.json').write_text('{')
            invalid=base/'invalid'
            self.assertNotEqual(run(invalid).returncode,0)
            self.assertFalse(invalid.exists())
            self.assertEqual((output/'GatheringReferenceData.lua').read_bytes(),old)

if __name__=='__main__':
    unittest.main()
