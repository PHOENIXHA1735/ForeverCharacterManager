from pathlib import Path
import json, re, subprocess, sys, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]

class ImportTests(unittest.TestCase):
    def test_staging_replay_and_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp)
            incoming=base/'in'
            incoming.mkdir()
            for kind in ('herbalism','mining','fishing'):
                document=dict(data=dict(profession=kind,zones=[dict(mapId=1,name='Fixture Zone',skill=1,noEscapeSkill=25,nodes=[],pools=[],loot=[],caughtInForever=[])],
                    nodes=[dict(name='Fixture Resource',objectIds=[123],skill=1,alsoGives=[],topZones=[])],pools=['Fixture Pool'],
                    url='https://foreverdb.net/profession/'+kind),
                    meta=dict(build='1.60.1.70959',attribution='ForeverDB',client='invented-client'))
                (incoming/(kind+'.json')).write_text(json.dumps(document))
            importer=ROOT/'ForeverCharacterManager/FCM-Companion/import_foreverdb_gathering.py'
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

    def test_gather_toolbar_bounds(self):
        ui=(ROOT/'ForeverCharacterManager/UI.lua').read_text(encoding='utf8')
        first=('Distance','Pins','Rim','Size')
        second=('World','Category')
        for buttons, y in ((first,109),(second,138)):
            self.assertIn(f'self.gather{buttons[0]}Button:SetPoint("TOPLEFT",panel,"TOPLEFT",14,-{y})',ui)
            for previous,button in zip(buttons,buttons[1:]):
                self.assertIn(f'self.gather{button}Button:SetPoint("LEFT",self.gather{previous}Button,"RIGHT",8,0)',ui)
            widths=[int(re.search(r'self.gather'+button+r'Button=button\(panel,"[^"]+",(\d+),25',ui)[1])
                    for button in buttons]
            for window in (1000,1010,1500):
                self.assertLess(14+sum(widths)+8*(len(widths)-1),window-171-22)
        self.assertEqual(ui.count('gathering and -170 or hasSecondToolbar'),1)
        self.assertLess(ui.index('14,contentTop)'),ui.index('self.gatherWorldButton:SetShown(gathering)'))
        self.assertLess(ui.index('-15,contentTop)'),ui.index('self.gatherWorldButton:SetShown(gathering)'))
        self.assertLess(138+25,170)
        self.assertNotIn('self.gatherSkillButton',ui)
        self.assertIn('Fishing - Schools & Pools',ui)
        self.assertIn('Fishing - Oil Spills & Wreckage',ui)
        self.assertIn('Gathering Filters',ui)
        self.assertIn('self:MakeMenu(self.gatherCategoryButton,entries,270,false)',ui)
        self.assertIn('self.gatherMoreButton=button',ui)


if __name__=='__main__':
    unittest.main()
