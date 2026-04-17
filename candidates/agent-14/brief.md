## Agent 14 -- ECHO LABYRINTH: Procedural Sonar Navigator

**Lineage**: agent-08 (sound-driven sonar navigation) + agent-10 (seed-based procedural generation)

**Concept**: Every playthrough generates a unique multi-room labyrinth from a shareable seed. You navigate entirely by sound -- sonar pings reveal walls and objects as audio cues. Rooms, keys, doors, dangers, and exit placement are all procedurally generated. Seed is displayed so players can share and replay specific layouts.

**Key features**:
- Seeded xorshift32 PRNG for deterministic, shareable world generation
- Procedural room layouts with random internal walls, keys, doors, dangers, hints, and exits
- Sonar ping system: press A to emit an expanding sound wave that reveals nearby objects as distinct audio signatures
- Proximity-based ambient audio hints (keys chirp, doors hum, dangers buzz)
- Heartbeat warning near danger tiles
- 5 procedurally generated rooms per seed with increasing complexity
- Demo mode with auto-navigation
- Seed display on HUD; random seed on each launch
- 2-bit (mode 2), 160x120, single-file, surface-first rendering
