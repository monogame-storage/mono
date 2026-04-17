# Agent 30 — THE DARK ROOM: Sonic Abyss
## Wave 3 | Focus: SOUND DESIGN

### Vision
The best-sounding Dark Room. Audio alone tells the story.

### Sound Design Philosophy
- **Every object has a unique audio signature**: walls (noise burst), keys (bright sine arpeggio), doors (low square pulse), exit (harmonic sweep), entity (detuned sawtooth growl)
- **Entity dread profile**: heavy footsteps getting louder/closer, breathing rumble, pursuit escalation
- **Dynamic ambient soundscape**: water drips (random high sine plinks), creaks (low sawtooth wobble), distant thuds (muffled triangle pulses), wind (filtered noise)
- **Musical heartbeat**: dual-thump pattern with pitch/tempo tied to danger proximity, creates rhythmic tension
- **Sonar as music**: ping emits a descending chord (root + fifth), objects respond with their own pitch creating momentary harmony
- **Silence as weapon**: ambient sounds fade to nothing before entity encounters, amplifying the scare
- **2-channel orchestration**: CH0 = ambience/heartbeat/drone, CH1 = events/sonar/footsteps — constant interplay
- **Audio storytelling**: calm drone -> drips -> heartbeat rises -> silence -> jumpscare blast

### Technical
- `mode(2)`, 160x120, 2-bit (4 grayscale: 0-3)
- Single `main.lua`, surface-first rendering
- Demo mode: auto-plays after 5 seconds idle on title
- 3 rooms with escalating entity speed and sound intensity
- 2 audio channels used with careful scheduling to avoid clipping
- Sonar reveals walls/objects/entity with distance-mapped pitch and duration
