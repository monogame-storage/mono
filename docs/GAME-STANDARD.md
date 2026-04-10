# Mono Game Standard

Recommended structure and input contract for Mono games, so players learn the controls once and apply them across every game we ship.

**Scope:** new games only. Existing demos are grandfathered. API-showcase demos (`engine-test`, `shader-test`, etc.) are permanently exempt — they are not games.

---

## Scene structure (recommendation)

Every game should have at minimum:

- A **title / entry scene** — shown on boot, waits for the player to start the game
- A **main gameplay scene** — the actual game loop
- Optional end-state scenes — game over, clear, win, etc.

**Scene names are free-form.** Call them `title` + `game`, `intro` + `play`, `menu` + `world` — whatever fits. The engine does not treat any scene name specially.

Entry file is `main.lua` (see `demo/README.md`), which calls `go("<your-title-scene>")` in `_start`.

Example layout:

```
demo/my-game/
├── main.lua       ← entry, boots into the title scene
├── title.lua      ← title screen
├── game.lua       ← main gameplay
└── gameover.lua   ← end state (optional)
```

---

## Physical button layout

```
[D-PAD]    [SELECT]  [START]    [B]  [A]
                                 left right
```

| Button | Semantic meaning |
|--------|------------------|
| **A**      | positive / confirm |
| **B**      | negative / cancel |
| **START**  | begin the game / resume |
| **SELECT** | pause (engine default) |

B is physically on the left, A on the right (Nintendo convention).

---

## Input contract

Two rules are universal across every standard-conforming Mono game:

### 1. START begins the game

On the title scene, pressing START must start the game. Games read `btnp("start")` themselves in the title scene's `_update` and call `go("<gameplay-scene>")`.

Games may use START for additional actions in other scenes (retry on game over, next level on clear, etc.), but the **begin** role on the title scene is fixed.

### 2. SELECT pauses (engine default)

By default the engine handles SELECT:

- Player presses SELECT → engine sets the global paused flag, freezes the game loop, draws the pause overlay.
- Player presses SELECT again → engine resumes.

Games that want to use SELECT for inventory, minimap, weapon switch, custom menus, or any other meta function may declare override:

```lua
function _start()
  select_override(true)   -- engine stops handling SELECT
  -- ... game reads btnp("select") itself from here on
end
```

**Consequence of override:** the game loses the default pause and is responsible for its own pause (or explicitly forgoes pause). This is intentional — the game owns SELECT and accepts what that means.

---

## Conventions

- **Use `btnp()` (press edge) for all scene transitions.** Never `btn()` (hold) — input from a scene's final frame would bleed into the next scene's first frame and trigger immediate re-transition.
- **Touch input is a valid scene transition signal.** A tap on the title screen is equivalent to pressing START if the game wants to support touch-only devices.
- **A may be an optional alternate start** on the title screen (some players prefer the A button). START must still work.

---

## Visual contract

- **Blinking "PRESS START"** on the title screen is allowed and recommended — single line of text, simple on/off blink. Classic arcade pattern, does not count as a tutorial overlay.
- **No other on-screen instructions for start or pause.** Players are expected to press SELECT to pause (it just works) and START to begin.
- **Pause overlay is engine-provided** for consistency. Games that override SELECT must provide their own visual if they implement a custom pause.

---

## Engine API

### `select_override(enabled)`

| Argument | Type | Effect |
|----------|------|--------|
| `enabled` | bool | `true`: engine stops handling SELECT; game reads `btnp("select")` directly. `false`: revert to engine default (pause toggle). |

Calling `select_override(true)` also clears any active pause state. Typical usage is a one-time call in `_start`.

### Pause state (default)

When `select_override` is **not** set, the engine:

1. Toggles an internal `paused` flag on each SELECT press edge.
2. Skips the `_update` call while `paused` is true.
3. Draws a blinking `PAUSED` overlay at the center of the screen.
4. Still calls `_draw` each frame so the game remains visible under the overlay.

Pause state resets on engine reload (`API.stop` → boot).

---

## Rationale

- **Predictability** — across every Mono game, START begins and SELECT pauses. Two rules, universal.
- **Zero-effort consistency** — games that do nothing inherit the full pause behavior.
- **Minimal constraint** — scene names, file count, and internal structure are the game's choice. The standard pins down only the two buttons that matter for cross-game consistency.
- **Opt-in override** — advanced games can take over SELECT for meta functions without the engine fighting them.
- **Minimalist aesthetic** — the only visual concession is a blinking "PRESS START" on the title screen.
