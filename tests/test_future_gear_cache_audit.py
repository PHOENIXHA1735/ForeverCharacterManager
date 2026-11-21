"""Synthetic tests only; no copyrighted/private item records."""
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))
from future_gear_cache_audit import audit


class CacheAuditTests(unittest.TestCase):
    def test_fixture_counts(self):
        content = '''local _, FCM = ...
do local r = FCM.externalData.items[100] or {}
r.name = "Synthetic Armor"
r.requiredLevel = "29"
r.slotID = "Chest"
r.classID = "4"
FCM.externalData.items[100]=r end
do local r = FCM.externalData.items[101] or {}
r.name = "Synthetic Material"
r.requiredLevel = "29"
r.slotID = "Non-equippable"
FCM.externalData.items[101]=r end
FCM.externalData.recipes[400]={name="Synthetic Pattern",resultID=100,skill=125,reagents={}}
FCM.externalData.recipes[401]={name="No output",resultID=0,skill=75,reagents={}}
FCM.externalData.dungeons[5] = {name="Synthetic Instance",kind="",lootIDs={100,},bosses={},dungeonLoot={}}
'''
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'fake.generated.lua'
            path.write_text(content)
            result = audit(path)
        self.assertEqual(result['items'], 2)
        self.assertEqual(result['recipes'], 2)
        self.assertEqual(result['instances'], 1)
        self.assertEqual(result['recipes_with_known_equipment_output'], 1)
        self.assertEqual(result['window_26_30']['equipment_references'], 1)
        self.assertEqual(result['window_26_30']['unique_equipment_recipe_outputs'], 1)
        self.assertEqual(result['instances_with_boss_loot'], 0)
        self.assertEqual(result['classified_instances'], 0)
        self.assertEqual(result['items_with_stats'], 0)

    def test_mismatched_item_blocks_are_rejected(self):
        content = '''do local r = FCM.externalData.items[1] or {}
r.slotID = "Head"
FCM.externalData.items[2]=r end
'''
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'bad.generated.lua'
            path.write_text(content)
            with self.assertRaises(ValueError):
                audit(path)


if __name__ == '__main__':
    unittest.main()
