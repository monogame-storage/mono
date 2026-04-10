# Mono — Claude Code Project Instructions

## Project
Mono is a constraint-driven fantasy game console (160x144, 16 grayscale colors, 16x16 sprites, Lua 5.4 via Wasmoon).

## Project Stage: ALPHA (Engine Development)

Current focus: engine development + first-party game for Play Store release.

### Stage Rules
- NO backward compatibility — break anything freely
- NO deprecation warnings or migration guides
- NO defensive coding for external consumers
- API changes are expected and encouraged
- Optimize for speed of iteration, not stability

### Stage Roadmap
```
ALPHA   (now)  Engine development     — no external users, break freely
BETA           Online editor          — API stabilization begins
GAMMA          Publishing system      — backward compatibility starts
PUBLIC         User pages & community — stability required
```

## Rules

### When AI makes a mistake
- First, fix the root cause — if the API is confusing, rename it; if a return type is ambiguous, change it
- Only document in `docs/AI-PITFALLS.md` when the root cause cannot be fixed (e.g. Lua language limitations, Wasmoon quirks)
- We are in ALPHA — prefer changing the engine over teaching AI to work around bad design

### Before adding or renaming a demo
Read `demo/README.md` or use `/mono-new-demo`. Do not guess file names or portal registration.

### Git
- Commit messages: imperative, concise, with Co-Authored-By
- Don't amend — always new commits
- PR that addresses a GitHub issue: always include `Closes #N` in PR body so merging auto-closes the issue
