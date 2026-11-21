"""Run real Store → staged Lua → TOC → Provider → Gold Advisor on invented observations."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'ForeverCharacterManager'
sys.path.insert(0, str(ADDON / 'FCM-Companion'))
from public_history_stage import stage
from public_intake import personal_archive
from public_store import Store

MARKET = 'forever/normal/alliance/us'
NOW = 1800043200


def fixture(root, now):
    store = root / 'history'
    store.mkdir()
    binding = root / 'binding.json'
    Store.initialize(store, binding)
    writer = Store(store, binding)
    def row(market, price, stamp, provenance='personal_scan'):
        return dict(market=market, item=424242, price=price, low=price-10,
                    supply=9, ts=stamp, provenance=provenance, source='synthetic-public30')
    rows = [row(MARKET, 120, now-60), row(MARKET, 80, now-8*86400),
            row(MARKET, 400, now-30*86400),
            row('forever/normal/horde/us', 200, now-50),
            row('forever/pvp/alliance/eu', 300, now-50)]
    writer.update(rows, now)
    return writer, row


LUA = """
local addon, generated, stamp = ...
local now = tonumber(stamp)
time = function() return now end
local f = {db={settings={}}}
function f:Now() return now end
function f:AuctionMarketFor(ch) return ch.market end
for _,toc in ipairs({'ForeverCharacterManager.toc','ForeverCharacterManager_Camelot.toc'}) do
  local seen = false
  for line in io.lines(addon..'/'..toc) do
    line=line:gsub('%s+$','')
    if line=='PublicHistory.generated.lua' then
      assert(loadfile(generated))('FCM',f); seen=true
    elseif line=='HistoryProvider.lua' then
      assert(seen); assert(loadfile(addon..'/'..line))('FCM',f)
    elseif line=='GoldAdvisor.lua' then
      assert(f.HistoryProvider); assert(loadfile(addon..'/'..line))('FCM',f)
    end
  end
  local ch={market='forever/normal/alliance/us'}
  local g=f.GoldAdvisor
  local q=g:Prices(ch)[424242]
  assert(q.current==120 and q.stamp==now-60 and q.currentSource=='scan')
  assert(q.averages[7]==120 and q.averages[30]==100 and q.averages[365]==nil)
  assert(not q.recommendationsAllowed)
  assert(g:Item(424242,q,ch).action=='NO CLEAR RECOMMENDATION')
  assert(g:Prices({market='forever/normal/horde/us'})[424242].current==200)
  assert(g:Prices({market='forever/pvp/alliance/eu'})[424242].current==300)
  assert(g:Prices({market='forever/normal/alliance/eu'})[424242]==nil)
  assert(g:Prices({market='forever/pvp/alliance/us'})[424242]==nil)
end
local h=f.HistoryProvider
local g=f.GoldAdvisor
local ch={market='forever/normal/alliance/us'}
local data=FCM_PublicHistory
f.db.settings.historyProvider={providerID='FCMPrivateHistory'}
assert(next((g:Prices(ch)))==nil)
f.db.settings.historyProvider=nil
data.authorizations={[2]={}}
assert(next((g:Prices(ch)))==nil and h.status=='Invalid authorization array')
data.authorizations={}
now=data.validUntil
assert(next((g:Prices(ch)))==nil)
now=tonumber(stamp)
FCM_PublicHistory=nil
FCM_AHHistory={schema=1,packed={}}
assert(next((g:Prices(ch)))==nil)
"""


def run_lua(root, generated, now, addon=ADDON):
    arguments = (addon.as_posix(), generated.as_posix(), str(now))
    exe = shutil.which('lua5.1')
    if exe:
        program = root / 'verify.lua'
        program.write_text(LUA, encoding='utf-8')
        subprocess.run([exe, str(program), *arguments], check=True)
    else:
        from lupa.lua51 import LuaRuntime
        LuaRuntime().execute(LUA, *arguments)


class PublisherTests(unittest.TestCase):
    def test_synthetic_archive_and_sidecar(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            raw = ('AHledgerDB={scans={{full=true,realm="Normal",faction="Alliance",region="US",'
                   f'ts={NOW-60},count=1,data="424242:2:240:0:0"}}}}}}\n').encode()
            digest = hashlib.sha256(raw).hexdigest().upper()
            archive = root / f'fixture_{digest}.lua'
            archive.write_bytes(raw)
            origin = '/synthetic/SavedVariables/AHledger.lua'
            metadata = dict(schema=1, kind='RawScans', source=origin,
                            sourceId=hashlib.sha256(origin.lower().encode()).hexdigest()[:16].upper(),
                            file=archive.name, sourceLength=len(raw), sha256=digest)
            sidecar = archive.with_suffix('.lua.json')
            sidecar.write_text(json.dumps(metadata), encoding='utf-8')
            rows = personal_archive(archive)
            self.assertEqual(len(rows), 1)
            self.assertEqual((rows[0]['market'], rows[0]['ts'], rows[0]['price']), (MARKET, NOW-60, 120))
            metadata['sha256'] = '0' * 64
            sidecar.write_text(json.dumps(metadata), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'digest mismatch'):
                personal_archive(archive)

    def test_publisher_and_gold(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            store, row = fixture(root, NOW)
            output = root / 'candidate.lua'
            receipt = stage(store, output, NOW, display_only=True)
            self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), receipt['sha256'])
            run_lua(root, output, NOW)
            with self.assertRaisesRegex(ValueError, 'expired'):
                stage(store, root / 'expired.lua', receipt['validUntil'])
            with self.assertRaisesRegex(ValueError, 'provider intake denied'):
                store.update([row(MARKET, 50, NOW-10, 'provider_snapshot')], NOW)
            active = store.root / store.state()['current'] / 'PublicHistory.generated.lua'
            active.write_bytes(active.read_bytes() + b'-- corrupt')
            with self.assertRaisesRegex(ValueError, 'Generation hash mismatch'):
                stage(store, root / 'invalid.lua', NOW)
            self.assertFalse((root / 'invalid.lua').exists())

    @unittest.skipUnless(sys.platform == 'win32', 'Windows PowerShell publication')
    def test_windows_publication_and_preservation(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            now = int(time.time())
            store, _ = fixture(root, now)
            addon = root / 'ForeverCharacterManager'
            companion = addon / 'FCM-Companion'
            shutil.copytree(ADDON / 'FCM-Companion', companion)
            for name in ('ForeverCharacterManager.toc', 'ForeverCharacterManager_Camelot.toc',
                         'HistoryProvider.lua', 'GoldAdvisor.lua', 'PublicHistory.generated.lua'):
                shutil.copyfile(ADDON / name, addon / name)
            generated = addon / 'PublicHistory.generated.lua'
            original = generated.read_bytes()
            unrelated = addon / 'AHHistory.generated.lua'
            unrelated.write_bytes(b'-- unrelated fixture only')
            engine = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0'
            env = dict(os.environ, PSModulePath=str(engine / 'Modules'))
            subprocess.run([str(engine / 'powershell.exe'), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                            str(companion / 'Publish-FCMPublicHistory.ps1'), '-Python', sys.executable,
                            '-Root', str(store.root), '-Binding', str(store.bound.binding), '-DisplayOnly'], check=True, env=env)
            self.assertEqual(generated.with_suffix('.lua.bak').read_bytes(), original)
            self.assertEqual(unrelated.read_bytes(), b'-- unrelated fixture only')
            candidate = root / 'expected.lua'
            stage(store, candidate, now, display_only=True)
            self.assertEqual(generated.read_bytes(), candidate.read_bytes())


if __name__ == '__main__':
    unittest.main()
