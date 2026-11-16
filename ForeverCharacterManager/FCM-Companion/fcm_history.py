"""Private local AH observations. Parses data, never executes Lua or contacts a server."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import statistics
from zoneinfo import ZoneInfo

UTC = timezone.utc
DAY = 86400
WINDOWS = (7, 30, 90, 180, 365)
MARKET = re.compile(r"forever/(normal|pvp|rp|rppvp|hardcore)/(alliance|horde)/(us|eu|cn|kr)")


class LuaData:
    """Small bounded parser for SavedVariables literals; calls and expressions fail closed."""
    def __init__(self, text):
        self.text, self.pos = text, 0

    def ws(self):
        while self.pos < len(self.text):
            m = re.compile(r'\s+|--[^\n]*').match(self.text, self.pos)
            if not m:
                return
            self.pos += len(m[0])

    def take(self, token):
        self.ws()
        if self.text.startswith(token, self.pos):
            self.pos += len(token)
            return True
        return False

    def need(self, token):
        if not self.take(token):
            raise ValueError('Unsupported Lua data syntax')

    def value(self, depth=0):
        self.ws()
        if depth > 40:
            raise ValueError('Lua nesting limit')
        if self.pos >= len(self.text):
            raise ValueError('Truncated Lua')
        if self.take('{'):
            out, index = {}, 1
            while not self.take('}'):
                self.ws()
                if self.take('['):
                    key = self.value(depth + 1)
                    self.need(']'); self.need('=')
                    out[key] = self.value(depth + 1)
                else:
                    m = re.compile(r'([A-Za-z_]\w*)\s*=').match(self.text, self.pos)
                    if m:
                        self.pos += len(m[0])
                        out[m[1]] = self.value(depth + 1)
                    else:
                        out[index] = self.value(depth + 1); index += 1
                if not self.take(',') and not self.take(';'):
                    self.need('}'); break
            return out
        if self.text[self.pos] in '\"\'':
            quote = self.text[self.pos]; self.pos += 1; out = []
            escapes = {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '\"': '\"', "'": "'"}
            while self.pos < len(self.text):
                c = self.text[self.pos]; self.pos += 1
                if c == quote:
                    return ''.join(out)
                if c == '\\':
                    if self.pos >= len(self.text):
                        raise ValueError('Truncated escape')
                    m = re.compile(r'\d{1,3}').match(self.text, self.pos)
                    if m:
                        code = int(m[0])
                        if code > 255: raise ValueError('Invalid escape')
                        out.append(chr(code)); self.pos += len(m[0]); continue
                    c = self.text[self.pos]; self.pos += 1
                    c = escapes.get(c, c)
                out.append(c)
            raise ValueError('Unclosed Lua string')
        m = re.compile(r'\[(=*)\[').match(self.text, self.pos)
        if m:
            self.pos += len(m[0]); end = self.text.find(']' + m[1] + ']', self.pos)
            if end < 0: raise ValueError('Unclosed long string')
            result = self.text[self.pos:end]
            self.pos = end + len(m[1]) + 2
            return result.removeprefix('\n')
        m = re.compile(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?').match(self.text, self.pos)
        if m:
            self.pos += len(m[0]); v = float(m[0])
            if not math.isfinite(v): raise ValueError('Nonfinite number')
            return int(v) if v.is_integer() else v
        for token, value in [('true', True), ('false', False), ('nil', None)]:
            if self.take(token): return value
        raise ValueError('Nonliteral Lua rejected')

    def database(self):
        self.need('AHledgerDB'); self.need('=')
        value = self.value()
        self.ws()
        if self.pos != len(self.text): raise ValueError('Trailing code rejected')
        return value


def ruleset(realm):
    words = set(re.findall(r'\w+', realm.lower()))
    if 'hardcore' in words: return 'hardcore'
    pvp = bool(words & {'pvp', 'jcj', 'jxj'})
    rp = bool(words & {'rp', 'jdr', 'gdr', 'rol'})
    if pvp and rp: return 'rppvp'
    if pvp: return 'pvp'
    if rp: return 'rp'
    if words & {'normal', 'pve'}: return 'normal'
    # Unknown realm names cannot safely establish market identity.
    return None


def tables(text):
    pattern = r'AHledgerData\["([^"\n]+)"\]\s*=\s*\{\s*updated\s*=\s*(\d+),\s*count\s*=\s*(\d+),\s*text\s*=\s*\[(=*)\[(.*?)\]\4\]\s*\}'
    for m in re.finditer(pattern, text, re.S):
        market, ts, count, _, payload = m.groups()
        if not MARKET.fullmatch(market): continue
        payload = payload.strip()
        lines = re.split(r'[;\n]+', payload)
        if lines[0].startswith('AHL1|'):
            header = lines.pop(0).split('|')
            if len(header) != 4 or header[1] != market or header[2] != ts or header[3] != count:
                raise ValueError('Table header mismatch')
        rows = [line.strip() for line in lines if line.strip()]
        if len(rows) != int(count): raise ValueError('Table row count mismatch')
        for line in rows:
            if not re.fullmatch(r'\d+(?::\d*){7,8}', line): raise ValueError('Malformed table row')
            fields = line.split(':')
            item = int(fields[0])
            price = int(fields[1]) if fields[1] else 0
            low = int(fields[2]) if fields[2] else None
            supply = int(fields[3]) if fields[3] else None
            pace = int(fields[8]) / 10 if len(fields) > 8 and fields[8] else None
            # Columns 5-8 are rolling statistics, deliberately never observations.
            if item > 0 and price > 0:
                yield (market, item, int(ts), 'table', price, low, supply, pace)


def scans(text):
    db = LuaData(text).database()
    for scan in db.get('scans', {}).values():
        if not isinstance(scan, dict) or scan.get('full') is not True: continue
        rule = ruleset(str(scan.get('realm', '')))
        faction = str(scan.get('faction', '')).lower()
        region = str(scan.get('region', '')).lower()
        market = f'forever/{rule}/{faction}/{region}'
        if not MARKET.fullmatch(market): continue
        ts = int(scan.get('ts', 0))
        data = scan.get('data', '')
        if not isinstance(data, str): continue
        by_item = defaultdict(lambda: defaultdict(int))
        for listing in re.split(r'[;\n]+', data):
            if not listing: continue
            if not re.fullmatch(r'\d+:\d+:\d+:\d+:\d+', listing): raise ValueError('Malformed scan listing')
            item, stack, buyout, bid, duration = map(int, listing.split(':'))
            if item > 0 and stack > 0 and buyout > 0:
                by_item[item][buyout / stack] += stack
        for item, units in by_item.items():
            total = sum(units.values()); cumulative = 0
            for price, qty in sorted(units.items()):
                cumulative += qty
                if cumulative >= math.ceil(total / 2): break
            yield (market, item, ts, 'scan', price, min(units), total, None)


def connect(path):
    db = sqlite3.connect(path)
    db.execute('CREATE TABLE IF NOT EXISTS archives(hash TEXT PRIMARY KEY)')
    db.execute('CREATE TABLE IF NOT EXISTS observations(market TEXT,item INTEGER,ts INTEGER,kind TEXT,price REAL,low REAL,supply REAL,pace REAL, PRIMARY KEY(market,item,ts,kind))')
    db.execute('CREATE TABLE IF NOT EXISTS sale_archives(hash TEXT PRIMARY KEY)')
    db.execute('CREATE TABLE IF NOT EXISTS sales(source TEXT,seq INTEGER,ts INTEGER,item INTEGER,qty INTEGER,gross INTEGER,cut INTEGER,deposit INTEGER,PRIMARY KEY(source,seq,ts,item))')
    return db


def import_sales(db, history, now):
    for path in sorted((history / 'RawScans').rglob('*.lua')):
        try:
            content=path.read_bytes()
            digest=hashlib.sha256(content).hexdigest().upper()
            meta=json.loads(Path(str(path)+'.json').read_text(encoding='utf-8-sig'))
            if meta['sha256']!=digest or meta['sourceLength']!=len(content): continue
            marker='v2:'+digest
            if db.execute('SELECT 1 FROM sale_archives WHERE hash=?',(marker,)).fetchone(): continue
            data=LuaData(content.decode('utf-8-sig')).database()
            with db:
                for event in data.get('ledger',{}).values():
                    if not isinstance(event,dict) or event.get('k')!='sale': continue
                    seq,ts,item,qty,gross,cut,deposit=(int(event.get(k,0)) for k in ('s','t','id','q','p','cut','dep'))
                    if min(seq,qty,gross)<=0 or item<0 or min(cut,deposit)<0 or cut>gross or not 946684800<=ts<=now: continue
                    # Account-scoped only: the ledger format has no market identity.
                    db.execute('INSERT OR IGNORE INTO sales VALUES(?,?,?,?,?,?,?,?)',(meta['sourceId'],seq,ts,item,qty,gross,cut,deposit))
                db.execute('INSERT INTO sale_archives VALUES(?)',(marker,))
        except (ValueError,KeyError,TypeError,OSError,UnicodeError):
            continue


def personal_sales(db, now, zone):
    result={}
    for item,events,qty,gross,cut,deposit,latest in db.execute('SELECT item,COUNT(*),SUM(qty),SUM(gross),SUM(cut),SUM(deposit),MAX(ts) FROM sales WHERE ts>? AND ts<=? GROUP BY item',(now-365*DAY,now)):
        result[str(item)]=dict(events=events,units=qty,gross=gross,cut=cut,netProceeds=gross-cut,refundedDeposits=deposit,latestRecordedUtc=latest,latestRecordedLocal=datetime.fromtimestamp(latest,UTC).astimezone(zone).isoformat())
    return result


def import_archives(db, history, now):
    imported = rejected = 0
    for folder, reader in [('MarketTables', tables), ('RawScans', scans)]:
        for path in sorted((history / folder).rglob('*.lua')):
            try:
                content = path.read_bytes()
                digest = hashlib.sha256(content).hexdigest().upper()
                meta = json.loads(Path(str(path) + '.json').read_text(encoding='utf-8-sig'))
                if meta['sha256'] != digest or meta['sourceLength'] != len(content): raise ValueError('Archive checksum mismatch')
                if db.execute('SELECT 1 FROM archives WHERE hash=?', (digest,)).fetchone(): continue
                rows = list(reader(content.decode('utf-8-sig')))
                if not rows: raise ValueError('No supported observations')
                with db:
                    for row in rows:
                        if not 946684800 <= row[2] <= now: raise ValueError('Invalid observation timestamp')
                        db.execute('INSERT OR IGNORE INTO observations VALUES(?,?,?,?,?,?,?,?)', row)
                    db.execute('INSERT INTO archives VALUES(?)', (digest,))
                imported += 1
            except (ValueError, KeyError, TypeError, OSError, UnicodeError):
                # Leave all originals intact; record only filenames and generic status locally.
                rejected += 1
                (history / 'Quarantine').mkdir(exist_ok=True)
                (history / 'Quarantine' / (path.name + '.rejected.txt')).write_text('Unsupported or invalid archive; original preserved.\n', encoding='utf-8')
    return imported, rejected


def timing(rows, daily, zone):
    result = {}
    for mode in ('weekday', 'hour'):
        buckets = defaultdict(list)
        for row in rows:
            local = datetime.fromtimestamp(row[2], UTC).astimezone(zone)
            key = local.weekday() if mode == 'weekday' else local.hour
            day = row[2] // DAY
            buckets[key].append((row[4] / daily[day], local.date().isoformat()))
        result[mode] = {str(k): {'relative': statistics.mean(v[0] for v in values), 'observations': len(values), 'days': len(set(v[1] for v in values)), 'adequate': len(values) >= 10 and len(set(v[1] for v in values)) >= (4 if mode == 'weekday' else 5)} for k, values in buckets.items()}
    return result


def summarize(db, now, zone):
    grouped = defaultdict(list)
    # Prefer a personal scan when the exact same market/item/timestamp is present twice.
    query = 'SELECT * FROM observations WHERE ts>? AND ts<=? ORDER BY market,item,ts,CASE kind WHEN "scan" THEN 0 ELSE 1 END'
    seen = set()
    for row in db.execute(query, (now - 365 * DAY, now)):
        key = row[:3]
        if key in seen: continue
        seen.add(key); grouped[row[:2]].append(row)
    markets = defaultdict(dict)
    for (market, item), rows in grouped.items():
        days = defaultdict(list)
        for row in rows: days[row[2] // DAY].append(row[4])
        daily = {day: statistics.mean(values) for day, values in days.items()}
        windows = {}
        for n in WINDOWS:
            window_days = defaultdict(list)
            for r in rows:
                if r[2] > now - n * DAY: window_days[r[2] // DAY].append(r[4])
            vals = [statistics.mean(v) for v in window_days.values()]
            windows[str(n)] = {'average': statistics.mean(vals) if vals else None, 'days': len(vals), 'coverage': min(1, len(vals) / n)}
        latest = rows[-1]
        provider = [r for r in rows if r[3] == 'table']
        current = provider[-1] if provider else latest
        age = now - current[2]; average = windows['365']['average']
        recent = [v for d, v in daily.items() if d * DAY > now - 7 * DAY]
        previous = [v for d, v in daily.items() if now - 14 * DAY < d * DAY <= now - 7 * DAY]
        trend = (statistics.mean(recent) / statistics.mean(previous) - 1) * 100 if recent and previous else None
        volatility = statistics.pstdev(daily.values()) / average if len(daily) > 1 else None
        confidence = 'low'
        if len(daily) >= 14 and age <= DAY: confidence = 'moderate'
        if len(daily) >= 60 and age <= 3600 and (volatility or 0) < .3: confidence = 'high'
        markets[market][str(item)] = dict(current=current[4], currentUtc=current[2], currentSource=current[3], low=current[5], supply=current[6], demand=current[7], ageSeconds=age, windows=windows, minimum=min(r[4] for r in rows), maximum=max(r[4] for r in rows), comparisonPct=(current[4] / average - 1) * 100, observedDays=len(daily), observations=len(rows), confidence=confidence, volatility=volatility, trendPct=trend, timing=timing(rows, daily, zone))
    return dict(markets)


def lua(value):
    if value is None: return 'nil'
    if value is True: return 'true'
    if value is False: return 'false'
    if isinstance(value, str): return json.dumps(value, ensure_ascii=True)
    if isinstance(value, (int, float)):
        if not math.isfinite(value): raise ValueError('Nonfinite output')
        return format(value, '.10g')
    if isinstance(value, dict): return '{' + ','.join('[' + lua(str(k)) + ']=' + lua(v) for k, v in value.items() if v is not None) + '}'
    if isinstance(value, list): return '{' + ','.join(lua(v) for v in value) + '}'
    raise TypeError(type(value))


def atomic(path, text):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(text, encoding='utf-8'); temp.replace(path)


def compact(data, allowed):
    packed, timing_data = {}, {}
    for market, items in data['markets'].items():
        if market not in allowed: continue
        lines = []
        for item, s in items.items():
            values = [item, s['current'], s['currentUtc'], s['low'], s['supply'], s['demand']]
            values += [s['windows'][str(n)]['average'] for n in WINDOWS]
            values += [s['windows'][str(n)]['days'] for n in WINDOWS]
            values += [s['minimum'], s['maximum'], s['comparisonPct'], s['observedDays'], s['observations'], s['volatility'], s['trendPct'], {'low': 1, 'moderate': 2, 'high': 3}[s['confidence']]]
            values += [1 if s['currentSource']=='table' else 2]
            lines.append(','.join('' if v is None else str(v) if isinstance(v,str) else format(v,'.10g') for v in values))
            buckets = {mode: {k: v for k, v in buckets.items() if v['adequate']} for mode, buckets in s['timing'].items()}
            if any(buckets.values()): timing_data.setdefault(market, {})[item] = buckets
        packed[market] = '\n'.join(lines)
    result = dict(schema=1, generatedUtc=data['generatedUtc'], timezone=data['timezone'], packed=packed, timing=timing_data, personalSales=data.get('personalSales',{}))
    return '-- Private local FCM history. Never distribute.\nFCM_AHHistory=' + lua(result) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--addon', type=Path, required=True)
    parser.add_argument('--timezone', default='America/Los_Angeles')
    parser.add_argument('--market', help='Export this market and opposite faction; never mixes regions/rulesets')
    args = parser.parse_args()
    zone = ZoneInfo(args.timezone)
    history = args.addon / 'AHHistory'
    if not (args.addon / 'ForeverCharacterManager.toc').is_file(): raise ValueError('FCM missing')
    now = int(datetime.now(UTC).timestamp())
    with connect(history / 'Parsed' / 'observations.sqlite3') as db:
        imported, rejected = import_archives(db, history, now)
        import_sales(db, history, now)
        markets = summarize(db, now, zone)
        sales=personal_sales(db,now,zone)
    data = dict(schema=1, generatedUtc=now, timezone=args.timezone, markets=markets,personalSales=sales)
    atomic(history / 'Index' / 'summary.json', json.dumps(data, separators=(',', ':')))
    market = args.market
    if not market:
        settings = args.addon / 'FCM-Companion' / 'settings.json'
        if settings.exists(): market = json.loads(settings.read_text(encoding='utf-8-sig')).get('market', '').replace('.', '/')
    if not market or not MARKET.fullmatch(market): raise ValueError('Explicit valid export market required')
    game, rule, faction, region = market.split('/')
    allowed = {f'{game}/{rule}/{f}/{region}' for f in ('alliance','horde')}
    # Packed numbers, only the configured ruleset/region pair; decoded lazily by FCM.
    atomic(args.addon / 'AHHistory.generated.lua', compact(data, allowed))
    print(json.dumps(dict(imported=imported, rejected=rejected, markets=len(markets), items=sum(map(len, markets.values())))))
    if rejected: raise SystemExit(2)


if __name__ == '__main__': main()
