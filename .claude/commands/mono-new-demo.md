---
description: Scaffold a new Mono demo game in demo/<name>/ with a category-aware template
---

Create a new demo scaffold under `demo/` using the helper script:

```bash
./.claude/scripts/mono-new-demo.sh <name> [category]
```

## Categories

Pick the one closest to what the demo should exercise. The template will preload relevant APIs in `_start()` / `_update()`:

| Category | Preloaded APIs in template |
|---|---|
| `graphics` (default) | cls, rectf, circ, text |
| `audio` | wave, note, tone, sfx_stop |
| `sprite` | loadImage, imageWidth, imageHeight, spr, sspr, drawImage |
| `touch` | touch, swipe, touch_pos |
| `scene` | go, scene_name |
| `canvas` | canvas, canvas_w/h/del, blit |

## What it creates

```
demo/<name>/
├── main.lua    — minimal _init/_start/_update/_draw with category-specific stubs
└── README.md   — intent, target APIs, verification command
```

Immediately runs a 10-frame smoke test so scaffolding errors surface right away.

## When to use

- Starting a fresh demo to cover an uncovered API category (see `/mono-verify` coverage section)
- Quickly prototyping an API pattern without writing boilerplate
