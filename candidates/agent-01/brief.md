# THE DARK ROOM — Agent 01 Brief

## Production Coordination Brief (bmad-gds)

### Production Intake
- **Game Type**: Mystery text adventure / narrative exploration
- **Stage**: Wave 1 Prototype
- **Constraint**: 160x120, 2-bit (4 grayscale), single-file, Mono platform
- **Approach**: Text-heavy narrative with rich descriptions, dialogue trees, inventory puzzles

### Priority Decisions

| Priority | Decision | Rationale |
|----------|----------|-----------|
| P0 | Atmospheric text rendering | Core experience is reading — must be legible and moody |
| P0 | Room navigation & state machine | Player must move between rooms seamlessly |
| P0 | Inventory system | Items are the puzzle mechanic |
| P1 | Dialogue / examination system | Rich descriptions build mystery atmosphere |
| P1 | Sound design | Ambient tones and SFX for tension |
| P2 | Typewriter text effect | Enhances narrative pacing |
| P2 | Touch support | Accessibility for touch devices |
| P3 | Multiple endings | Replay value |

### Milestone Planning

**M1 — Core Loop (this build)**
- Title screen with demo mode (7-segment clock)
- 6 interconnected rooms with descriptions
- Inventory: pick up, examine, use items
- Puzzle chain leading to escape
- Pause menu via SELECT
- Sound effects for actions

**M2 — Polish (future)**
- Extended dialogue trees
- More environmental storytelling
- Multiple endings based on choices
- Particle effects (dust, flickering light)

### Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Text overflow on 160px screen | High | Careful word wrapping, scrollable text |
| Too many rooms = shallow content | Medium | Focus on 6 deep rooms over many shallow ones |
| Puzzle logic bugs | Medium | Simple key/lock chains, thorough state tracking |
| Performance with text rendering | Low | Minimal per-frame allocations, cached strings |

### Game Design Summary

**Premise**: You wake in a pitch-black room. A single match flickers. Fragments of memory surface as you explore — you are a researcher who discovered something terrible. The facility locked you in. Find the evidence, find the exit, expose the truth.

**Rooms**: Cell, Corridor, Lab, Office, Storage, Exit Hall
**Key Items**: Match, Keycard, Journal Pages, Fuse, Crowbar, Evidence File
**Core Puzzle Chain**: Match → see Cell → find Keycard → open Corridor → find Crowbar → pry Storage → get Fuse → power Lab terminal → get code → unlock Exit
