"""Synthetic fixtures only. No installed addon or private data access."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from zoneinfo import ZoneInfo
import hashlib
import json

SOURCE = Path(__file__).resolve().parents[1] / 'ForeverCharacterManager/FCM-Companion/fcm_history.py'
spec = importlib.util.spec_from_file_location('history', SOURCE)
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
M = 'forever/normal/alliance/us'
NOW = 1800000000


class HistoryTests(unittest.TestCase):
    def test_literal_safety(self):
        self.assertEqual(h.LuaData('AHledgerDB = { ["scans"] = {}, n = 4, a=true }').database()['n'], 4)
        for text in ('AHledgerDB = os.execute("bad")', 'AHledgerDB={} os.execute("bad")'):
            with self.assertRaises(ValueError): h.LuaData(text).database()

    def test_table_original_timestamp_not_rolling_average(self):
        text = 'AHledgerData["'+M+'"] = { updated = 1800000000, count = 1, text = [==[AHL1|'+M+'|1800000000|1\n1:100:90:20:999:888:1:9999:40]==] }'
        row = list(h.tables(text))[0]
        self.assertEqual(row, (M, 1, NOW, 'table', 100, 90, 20, 4))

    def test_scan_weighted_median_and_market(self):
        text = 'AHledgerDB={scans={{realm="Synthetic PvP",faction="Horde",region="eu",full=true,ts=1800000000,data="1:2:200:0:1;1:10:2000:0:1;2:1:0:5:1"}}}'
        rows = list(h.scans(text))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][:5], ('forever/pvp/horde/eu', 1, NOW, 'scan', 200))
        self.assertEqual(rows[0][6], 12)

    def test_daily_equal_weight_windows_missing_days(self):
        db = h.connect(':memory:')
        # Two observations on day A, one on day B: average daily values, not 3 samples.
        rows = [(M, 1, NOW-100, 'table', 100, 80, 2, 5), (M,1,NOW-200,'table',300,80,2,5), (M,1,NOW-h.DAY-100,'table',400,80,2,5), (M,1,NOW-366*h.DAY,'table',99999,80,2,5)]
        db.executemany('INSERT INTO observations VALUES(?,?,?,?,?,?,?,?)', rows)
        s = h.summarize(db, NOW, ZoneInfo('America/Los_Angeles'))[M]['1']
        self.assertEqual(s['windows']['365']['average'], 300)
        self.assertEqual(s['observedDays'], 2)
        self.assertEqual(s['minimum'], 100)
        self.assertEqual(s['maximum'], 400)
        self.assertEqual(s['confidence'], 'low')
        self.assertEqual(s['trendPct'], None)
        self.assertTrue(all(not b['adequate'] for b in s['timing']['hour'].values()))

    def test_faction_region_separation_and_dedup(self):
        db = h.connect(':memory:')
        rows = [(M,1,NOW,'table',100,80,2,5), ('forever/normal/horde/us',1,NOW,'table',900,800,2,5), ('forever/normal/alliance/eu',1,NOW,'table',700,600,2,5)]
        db.executemany('INSERT OR IGNORE INTO observations VALUES(?,?,?,?,?,?,?,?)', rows * 2)
        summaries = h.summarize(db,NOW,ZoneInfo('America/Los_Angeles'))
        self.assertEqual(len(summaries),3)
        self.assertEqual(summaries[M]['1']['observations'],1)
        self.assertEqual(summaries[M]['1']['current'],100)

    def test_365_boundaries_and_freshness(self):
        db=h.connect(':memory:')
        for age in (0,7,30,90,180,364,365):
            db.execute('INSERT INTO observations VALUES(?,?,?,?,?,?,?,?)',(M,1,NOW-age*h.DAY,'table',100,90,1,None))
        s=h.summarize(db,NOW,ZoneInfo('America/Los_Angeles'))[M]['1']
        self.assertEqual([s['windows'][str(n)]['days'] for n in h.WINDOWS],[1,2,3,4,6])
        self.assertEqual(s['ageSeconds'],0)

    def test_archive_integrity_and_incremental_import(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'MarketTables').mkdir(); (root/'RawScans').mkdir()
            p=root/'MarketTables'/'synthetic.lua'
            text='AHledgerData["'+M+'"] = { updated = 1800000000, count = 1, text = [[1:100:90:20:999:888:1:9999:40]] }'
            p.write_text(text,encoding='utf-8')
            Path(str(p)+'.json').write_text(json.dumps({'sha256':hashlib.sha256(p.read_bytes()).hexdigest().upper(),'sourceLength':len(p.read_bytes())}))
            db=h.connect(':memory:')
            self.assertEqual(h.import_archives(db,root,NOW),(1,0))
            self.assertEqual(h.import_archives(db,root,NOW),(0,0))
            p.write_text(text+'x')
            self.assertEqual(h.import_archives(db,root,NOW),(0,1))

    def test_local_timezone_dst(self):
        zone=ZoneInfo('America/Los_Angeles')
        a=h.datetime(2026,11,1,8,30,tzinfo=h.UTC).astimezone(zone)
        b=h.datetime(2026,11,1,9,30,tzinfo=h.UTC).astimezone(zone)
        self.assertEqual(a.hour,b.hour)
        self.assertNotEqual(a.utcoffset(),b.utcoffset())

    def test_supported_weekday_and_hour_evidence(self):
        zone=ZoneInfo('America/Los_Angeles')
        rows=[]
        for day in range(70):
            for hour in (8,9):
                ts=NOW-day*h.DAY-hour*3600
                rows.append((M,1,ts,'table',100 if hour==8 else 200,90,2,5))
        daily={r[2]//h.DAY:150 for r in rows}
        timing=h.timing(rows,daily,zone)
        self.assertTrue(all(b['adequate'] for b in timing['weekday'].values()))
        self.assertGreaterEqual(sum(b['adequate'] for b in timing['hour'].values()),2)
        self.assertEqual(sum(b['observations'] for b in timing['weekday'].values()),140)

    def test_private_publication_paths(self):
        import runpy
        private=runpy.run_path(str(Path(__file__).parent/'check_private_paths.py'))['private']
        for p in ('ForeverCharacterManager/AHHistory/RawScans/a.lua','ForeverCharacterManager/AHledger/AHledger.lua','ForeverCharacterManager/AHHistory.generated.lua','ForeverCharacterManager/a.sqlite3','ForeverCharacterManager/FCM-Companion/key.dpapi'):
            self.assertTrue(private(p),p)
        self.assertFalse(private('ForeverCharacterManager/GoldAdvisor.lua'))


if __name__=='__main__': unittest.main()
