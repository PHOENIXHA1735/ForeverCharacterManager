# Offline regression tests

From the repository root with `texlua` installed:

```
texlua tests/parse.lua
texlua tests/qa_regressions_v092.lua
texlua tests/qa_v092_identity.lua
texlua tests/qa_crafting_professions_v090.lua
```

These tests cover Lua parsing, binding API and gear behavior, identity / faction / ruleset migration, and per-recipe profession assignment with safe SavedVariables repair. They use mock APIs and do not replace in-game verification.
