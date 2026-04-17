# Agent #12: THE DARK ROOM - Survival Craft

## Origin
- **Base**: Agent-04 (Horror - tile-based rooms, flashlight, stalker entity, scare system)
- **Absorbed**: Agent-05 (Inventory + Crafting system with item database, grid UI, recipes)

## Concept
A horror survival game where crafting is essential to escape. You wake in a dark cell hunted by a stalking entity. Find scattered components, open your inventory to combine them, and craft the tools you need to unlock doors and survive. The entity keeps moving even while you craft, creating tension between careful resource management and the urgency of escape.

## Crafting Recipes (3)
1. **Flashlight + Batteries = Lit Flashlight** - Restores battery, halves drain rate (survival advantage)
2. **Wire + Rusty Nail = Lockpick** - Opens any locked door (alternate path, bypasses key hunting)
3. **Note (left) + Note (right) = Full Note** - Required to use the exit (win condition)

## Key Mechanics
- **2-bit visuals** (mode 2): 4 shades, flashlight cone lighting, vignette
- **Inventory grid** (4x2): B opens/closes, A selects items, A+A combines two
- **Stalker AI**: Entity patrols rooms, chases on sight, triggers jump scares
- **Battery drain**: Flashlight depletes over time; crafted Lit Flashlight drains slower
- **Lockpick flexibility**: Crafted lockpick opens any locked door, offering alternate routes
- **Entity moves during inventory**: Crafting is not a safe pause - tension persists
- **5 rooms**: Cell, Corridor, Library, Storage, Exit
- **Demo mode**: Auto-plays after idle, auto-crafts recipes, exits on any input
- **Sound design**: Heartbeat proximity, dripping water, creaking, entity footsteps

## Controls
- D-Pad: Move
- A: Interact (pick up items, use doors)
- B: Open/Close inventory
- START: Start game
- SELECT: Pause

## Surface-First Design
Title screen reveals the horror theme with flickering text and ambient eyes. Gameplay immediately puts the player in darkness with flashlight cone lighting. Crafting UI is clean and accessible with slot-based grid.
