from pathlib import Path
import copy, json, re, subprocess, sys, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'ForeverCharacterManager/FCM-Companion'))
from build_gather_reference import validate

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
                if kind=='fishing':
                    document['data']['zones'][0]['loot']=[dict(name='Raw Winter Squid',itemId=13755,
                        waterType='freshwater')]
                    document['data']['zones'][0]['caughtInForever']=[dict(name='Raw Winter Squid',
                        itemId=13755,waterType='ocean',seasonWindow=dict(start='09-23',end='03-19'))]
                (incoming/(kind+'.json')).write_text(json.dumps(document))
            importer=ROOT/'ForeverCharacterManager/FCM-Companion/import_foreverdb_gathering.py'
            output=base/'staged'
            def run(target):
                return subprocess.run([sys.executable,'-B',str(importer),str(incoming),str(target)],
                                      capture_output=True,text=True)
            self.assertEqual(run(output).returncode,0)
            old=(output/'GatheringReferenceData.lua').read_bytes()
            self.assertNotIn(b'invented-client',old)
            normalized=json.loads((output/'gathering-reference.json').read_text(encoding='utf8'))
            zone=next(r for r in normalized['resources']
                if r['category']=='fishing' and r['name']=='Zone fishing reference: Fixture Zone')
            by_source={item['sourceID']:item for item in zone['loot']
                if item['itemID']==13755}
            self.assertEqual(by_source['foreverdb-fishing-classic']['verificationStatus'],
                'classic_reference')
            observed=by_source['foreverdb-fishing-observed']
            self.assertEqual(observed['verificationStatus'],'forever_observed')
            self.assertEqual(observed['waterType'],'ocean')
            self.assertEqual(observed['seasonWindow'],
                dict(start='09-23',end='03-19'))
            # A season of observed catches is not evidence of seasonal
            # exclusivity; the UI must keep any season rule qualified.
            source_input={k:v for k,v in normalized.items()
                if k not in ('contentSHA256','recordCount','categoryCounts')}
            self.assertEqual(validate(source_input)['recordCount'],len(normalized['resources']))
            for bad_field,bad_value in (
                ('waterType','arbitrary ocean from zone name'),
                ('verificationStatus','verified because it has a loot table'),
                ('seasonWindow',dict(start='13-10',end='03-19')),
            ):
                changed=copy.deepcopy(source_input)
                entry=next(r for r in changed['resources']
                    if r['category']=='fishing' and r['name']=='Zone fishing reference: Fixture Zone')
                target=next(item for item in entry['loot']
                    if item['sourceID']=='foreverdb-fishing-observed')
                target[bad_field]=bad_value
                with self.assertRaises(ValueError):validate(changed)
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
        self.assertIn('Fishing - Fish',ui)
        self.assertIn('{"Fishing - Fish","fishing","fish"}',ui)
        self.assertIn('Fishing - Schools & Pools',ui)
        self.assertIn('Fishing - Oil Spills & Wreckage',ui)
        self.assertIn('Gathering Filters',ui)
        self.assertIn('self:MakeMenu(self.gatherCategoryButton,entries,270,false)',ui)
        self.assertIn('self.gatherMoreButton=button',ui)
        self.assertNotIn('Import GatherMate2',ui)
        self.assertNotIn('ImportGatherMate(',ui)
        self.assertIn('self.gatherMoreButton:SetPoint("TOPRIGHT",detailPanel,"BOTTOMRIGHT",-8,-8)',ui)
        gathering=(ROOT/'ForeverCharacterManager/Gathering.lua').read_text(encoding='utf8')
        self.assertNotIn('function FCM:ImportGatherMate()',gathering)
        self.assertIn('local function visibleGatherNode(node)',gathering)

        self.assertIn('self:RenderGatherMaterialPanel(selected.gatherResource,ch,self.gatherShowAllDetails)',ui)
        self.assertIn('rows[#rows].gatherResource=resource',ui)
        self.assertIn('self:HideGatherMaterialPanel()',ui)
        for toc in ('ForeverCharacterManager.toc','ForeverCharacterManager_Camelot.toc'):
            content=(ROOT/'ForeverCharacterManager'/toc).read_text(encoding='utf8')
            self.assertIn('GatherDetailModel.lua',content)
            self.assertIn('GatherDetailUI.lua',content)
            self.assertLess(content.index('GatherBrowser.lua'),content.index('GatherDetailModel.lua'))
            self.assertLess(content.index('UI.lua'),content.index('GatherDetailUI.lua'))
        renderer=(ROOT/'ForeverCharacterManager/GatherDetailUI.lua').read_text(encoding='utf8')
        self.assertIn('section(model.sourceHeading,sources)',renderer)
        self.assertIn('POTENTIAL SOURCE ZONES',renderer)
        self.assertIn('YOUR GATHERING HISTORY',renderer)



if __name__=='__main__':
    unittest.main()
