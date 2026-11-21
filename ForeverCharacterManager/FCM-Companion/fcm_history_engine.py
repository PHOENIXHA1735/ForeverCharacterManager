"""Pinned pure statistics. Caller supplies eligible UTC rows; no storage or permissions."""
from collections import defaultdict
from datetime import datetime,timedelta,timezone
from zoneinfo import ZoneInfo
import statistics,math
UTC=timezone.utc
DAY=86400
REVISION='fcm-statistics-2.0.0'
def local_date(timestamp, zone):
    """Calendar date in the configured zone; stored UTC timestamps stay intact."""
    return datetime.fromtimestamp(timestamp, UTC).astimezone(zone).date()


def window_start(now, days, zone):
    """Inclusive local midnight for N dates including today (23/25h DST safe)."""
    first = local_date(now, zone) - timedelta(days=days - 1)
    return int(datetime.combine(first, datetime.min.time(), tzinfo=zone).timestamp())


def timing(rows, daily, zone):
    result = {}
    for mode in ('weekday', 'hour'):
        buckets = defaultdict(list)
        for row in rows:
            local = datetime.fromtimestamp(row[2], UTC).astimezone(zone)
            key = local.weekday() if mode == 'weekday' else local.hour
            day = local.date()
            buckets[key].append((row[4] / daily[day], local.date().isoformat()))
        result[mode] = {str(k): {'relative': statistics.mean(v[0] for v in values), 'observations': len(values), 'days': len(set(v[1] for v in values)), 'adequate': len(values) >= 10 and len(set(v[1] for v in values)) >= (4 if mode == 'weekday' else 5)} for k, values in buckets.items()}
    return result


def calculate(observations, now, windows, baseline, zone=None):
    zone=zone or ZoneInfo("America/Los_Angeles")
    grouped = defaultdict(list)
    # Prefer a personal scan when the exact same market/item/timestamp is present twice.
    seen = set()
    for row in sorted(observations, key=lambda r:(r[0],r[1],r[2],0 if r[3]=='scan' else 1)):
        key = row[:3]
        if key in seen: continue
        seen.add(key); grouped[row[:2]].append(row)
    markets = defaultdict(dict)
    for (market, item), rows in grouped.items():
        days = defaultdict(list)
        for row in rows: days[local_date(row[2], zone)].append(row[4])
        daily = {day: statistics.mean(values) for day, values in days.items()}
        result_windows = {}
        for n in windows:
            first = local_date(now, zone) - timedelta(days=n - 1)
            vals = [value for day, value in daily.items() if day >= first]
            result_windows[str(n)] = {'average': statistics.mean(vals) if vals else None, 'days': len(vals), 'coverage': min(1, len(vals) / n)}
        # The newest observation is the current price, even when it came from
        # a personal AH scan after the provider's most recent price table.
        # Demand is not measured by personal scans; carry forward a recent
        # provider estimate without substituting its older price for the scan.
        current = rows[-1]
        provider = [r for r in rows if r[3] == 'table']
        recent_provider = provider[-1] if provider and now - provider[-1][2] <= 7 * DAY else None
        demand = current[7] if current[7] is not None else (recent_provider[7] if recent_provider else None)
        age = now - current[2]; average = result_windows[str(baseline)]['average']
        recent_start = local_date(now, zone) - timedelta(days=6)
        previous_start = recent_start - timedelta(days=7)
        recent = [v for d, v in daily.items() if d >= recent_start]
        previous = [v for d, v in daily.items() if previous_start <= d < recent_start]
        trend = (statistics.mean(recent) / statistics.mean(previous) - 1) * 100 if recent and previous else None
        volatility = statistics.pstdev(daily.values()) / average if len(daily) > 1 else None
        confidence = 'low'
        if len(daily) >= 14 and age <= DAY: confidence = 'moderate'
        if len(daily) >= 60 and age <= 3600 and (volatility or 0) < .3: confidence = 'high'
        markets[market][str(item)] = dict(current=current[4], currentUtc=current[2], currentSource=current[3], low=current[5], supply=current[6], demand=demand, ageSeconds=age, windows=result_windows, minimum=min(r[4] for r in rows), maximum=max(r[4] for r in rows), comparisonPct=(current[4] / average - 1) * 100, observedDays=len(daily), observations=len(rows), confidence=confidence, volatility=volatility, trendPct=trend, timing=timing(rows, daily, zone))
    return dict(markets)
