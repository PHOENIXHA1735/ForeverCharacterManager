"""Literal parsers retained for synthetic/verified ingestion adapters; no storage discovery."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone, timedelta
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
