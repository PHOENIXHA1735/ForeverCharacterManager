#!/usr/bin/env python3
"""Read-only FCM generated-reference coverage report; never evaluates Lua.

Only aggregate counts are printed. The source cache is not copied or published.
Usage: python tools/future_gear_cache_audit.py ExternalData.generated.lua
"""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import argparse
import json
import re

EQUIP_SLOTS = frozenset('Head Neck Shoulder Back Chest Waist Legs Feet Wrist Hands Finger Trinket'.split()) | {
    'One-Hand', 'Main Hand', 'Off Hand', 'Two-Hand', 'Held In Off-hand',
    'Shield', 'Ranged', 'Thrown', 'Relic'
}
ITEM_HEAD = re.compile(r'^do local r = FCM\.externalData\.items\[(\d+)\] or \{\}$')
ITEM_END = re.compile(r'^FCM\.externalData\.items\[(\d+)\]=r end$')
ITEM_FIELD = re.compile(r'^r\.(\w+)\s*=\s*(.+)$')
RECIPE = re.compile(r'^FCM\.externalData\.recipes\[(\d+)\]=\{')
INSTANCE = re.compile(r'^FCM\.externalData\.dungeons\[(\d+)\]\s*=\s*\{')

def audit(path: Path):
    items, output_ids, instance_ids = {}, [], set()
    counts = Counter()
    item_id, fields = None, None
    digest = sha256()
    with path.open('rb') as stream:
        for raw in stream:
            digest.update(raw)
            line = raw.decode('utf-8-sig').strip()
            if item_id is not None:
                end = ITEM_END.match(line)
                if end:
                    if int(end.group(1)) != item_id:
                        raise ValueError('Item ID mismatch in generated Lua')
                    items[item_id] = fields
                    item_id, fields = None, None
                else:
                    match = ITEM_FIELD.match(line)
                    if match:
                        name, value = match.groups()
                        fields[name] = value.strip('"')
                continue
            head = ITEM_HEAD.match(line)
            if head:
                item_id, fields = int(head.group(1)), {}
                continue
            if RECIPE.match(line):
                counts['recipes'] += 1
                match = re.search(r'(?<!\w)resultID=(\d+)', line)
                if match and int(match.group(1)) > 0:
                    output_ids.append(int(match.group(1)))
                continue
            match = INSTANCE.match(line)
            if match:
                ident = int(match.group(1))
                if ident in instance_ids:
                    raise ValueError('Duplicate instance in generated Lua')
                instance_ids.add(ident)
                counts['instances'] += 1
                if re.search(r'(?<!\w)kind="[^"]+"', line):
                    counts['classified_instances'] += 1
                if re.search(r'(?<!\w)lootIDs=\{\s*\d+', line):
                    counts['instances_with_loot'] += 1
                if re.search(r'(?<!\w)loot=\{\s*\{id=', line):
                    counts['instances_with_boss_loot'] += 1
    if item_id is not None:
        raise ValueError('Unterminated item block')
    equipment = {}
    for id_, field in items.items():
        slot = field.get('slotID')
        if slot not in EQUIP_SLOTS:
            continue
        try:
            level = int(field['requiredLevel'])
        except (KeyError, ValueError):
            continue
        equipment[id_] = level
    known_recipe_outputs = set(output_ids) & equipment.keys()
    def in_window(level_min, level_max):
        return {
            'equipment_references': sum(level_min <= lev <= level_max for lev in equipment.values()),
            'unique_equipment_recipe_outputs': sum(level_min <= equipment[id_] <= level_max for id_ in known_recipe_outputs),
        }
    return {
        'source_sha256': digest.hexdigest(),
        'items': len(items),
        'recipes': counts['recipes'],
        'instances': counts['instances'],
        'items_with_required_level': sum('requiredLevel' in f for f in items.values()),
        'items_with_recognized_slot_and_level': len(equipment),
        'recipes_with_result_id': len(output_ids),
        'recipes_with_known_equipment_output': sum(id_ in equipment for id_ in output_ids),
        'classified_instances': counts['classified_instances'],
        'instances_with_loot': counts['instances_with_loot'],
        'instances_with_boss_loot': counts['instances_with_boss_loot'],
        'items_with_stats': sum(bool(f.get('stats')) for f in items.values()),
        'items_with_explicit_class_mask': sum(bool(f.get('classMask') or f.get('allowableClassMask')) for f in items.values()),
        'items_with_binding': sum(bool(f.get('binding')) for f in items.values()),
        'items_marked_speculative': sum(f.get('speculation') == 'true' for f in items.values()),
        'items_marked_beta': sum(f.get('betaEvent') == 'true' for f in items.values()),
        'window_26_30': in_window(26, 30),
        'window_26_35': in_window(26, 35),
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('generated_lua', type=Path)
    args = parser.parse_args()
    print(json.dumps(audit(args.generated_lua), indent=2, sort_keys=True))

if __name__ == '__main__':
    main()
