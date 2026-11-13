# Offline regression tests

From the repository root with `texlua` installed:

```
texlua tests/parse.lua
texlua tests/qa_regressions_v092.lua
texlua tests/qa_v092_identity.lua
```

These tests cover Lua parsing, binding API and gear behavior, plus identity / faction / ruleset migration. They use mock APIs and do not replace in-game verification.
