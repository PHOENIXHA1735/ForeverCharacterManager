# Offline regression tests

From the repository root with `texlua` installed:

```
texlua tests/parse.lua
texlua tests/qa_regressions_v092.lua
texlua tests/qa_v092_identity.lua
texlua tests/qa_crafting_professions_v090.lua
texlua tests/qa_gathering_v091.lua
texlua tests/qa_bag_capacity_v091.lua
python3 tests/qa_overnight_catalog.py
```

These tests cover Lua parsing, binding API and gear behavior, identity / faction / ruleset migration, and per-recipe profession assignment with safe SavedVariables repair. They use mock APIs and do not replace in-game verification.

The gathering harness checks zone-map ID aliases (41 / 1438), map pins and
minimap behavior. The bag harness validates slot counts from reference data,
real client-tooltip-style input, safe unknowns, preview text and hover.

The Python overnight-catalog check verifies the 56 daily 15-minute Pacific
trigger slots (including DST wall-clock boundaries), shared manual/build/
scheduled budget, throttling and separation from AH requests. It does not
execute PowerShell or register a Windows task; real Windows/ForeverDB
integration must still be tested.
