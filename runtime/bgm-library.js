/**
 * Mono BGM Library — Pre-made background music presets
 *
 * Usage:
 *   <script src="runtime/engine.js"></script>
 *   <script src="runtime/bgm-library.js"></script>
 *   ...
 *   bgm(Mono.BGM.IRON_EAGLE);          // play at preset BPM
 *   bgm(Mono.BGM.IRON_EAGLE, 200);     // override BPM
 *
 * Each preset: { tracks, bpm, style, tags }
 */
(function() {
  'use strict';

  var BGM = {};

  // ================================================================
  //  TRACKER / CHIPTUNE
  // ================================================================

  BGM.ARPEGGIO_BLITZ = {
    tracks: [
      "C4 E4 G4 C5 E5 G4 C4 E4 | G4 B4 D5 G5 D5 B4 G4 D4 | A3 C4 E4 A4 C5 E4 A3 C4 | F3 A3 C4 F4 A4 C4 F3 A3",
      "C2 - - - G2 - - - | G2 - - - D2 - - - | A2 - - - E2 - - - | F2 - - - C2 - - -",
    ],
    bpm: 220, style: "tracker",
    tags: ["fast", "intense", "chiptune", "gameplay", "boss"],
  };

  BGM.SID_GROOVE = {
    tracks: [
      "A4 . C5 . A4 E4 . G4 | A4 . C5 E5 D5 . C5 . | F4 . A4 . F4 C4 . E4 | F4 . A4 C5 B4 . A4 .",
      "A2 A3 A2 A3 E2 E3 E2 E3 | A2 A3 A2 A3 G2 G3 G2 G3 | F2 F3 F2 F3 C2 C3 C2 C3 | F2 F3 F2 F3 E2 E3 E2 E3",
    ],
    bpm: 200, style: "tracker",
    tags: ["fast", "groovy", "chiptune", "retro", "gameplay"],
  };

  BGM.PULSE_DRIVER = {
    tracks: [
      "E4 E5 E4 E5 D4 D5 D4 D5 | C4 C5 C4 C5 B3 B4 B3 B4 | A3 A4 A3 A4 G3 G4 G3 G4 | A3 C4 E4 A4 E4 C4 A3 .",
      "A2 . . A2 . . A2 . | F2 . . F2 . . F2 . | D2 . . D2 . . D2 . | A2 . E2 . A2 . . .",
    ],
    bpm: 240, style: "tracker",
    tags: ["fast", "intense", "chiptune", "driving", "boss"],
  };

  // ================================================================
  //  AMBIENT / SUSTAINED
  // ================================================================

  BGM.CLOUD_DRIFT = {
    tracks: [
      "E4 - - - - - G4 - | - - - - A4 - - - | - - - - G4 - - - | - - E4 - - - - -",
      "C3 - - - - - - - | A2 - - - - - - - | F2 - - - - - - - | G2 - - - - - - -",
    ],
    bpm: 80, style: "ambient",
    tags: ["slow", "calm", "dreamy", "title", "menu"],
  };

  BGM.NIGHT_CARRIER = {
    tracks: [
      "D4 - - - F4 - - - | A4 - - - - - G4 - | - - F4 - - - D4 - | - - - - - - - -",
      "D2 - - - - - - - | D2 - - - - - - - | A#2 - - - - - - - | A2 - - - - - - -",
    ],
    bpm: 90, style: "ambient",
    tags: ["slow", "dark", "moody", "suspense", "cutscene"],
  };

  BGM.DEEP_BLUE = {
    tracks: [
      "G3 - - - - - - - | B3 - - - - - - - | D4 - - - - - - - | C4 - - - - - - -",
      "G2 - - - - - - - | G2 - - - - - - - | G2 - - - - - - - | C2 - - - - - - -",
    ],
    bpm: 70, style: "ambient",
    tags: ["slow", "calm", "minimal", "underwater", "menu"],
  };

  // ================================================================
  //  ACTION / DRIVING
  // ================================================================

  BGM.IRON_EAGLE = {
    tracks: [
      "E4 - G4 A4 B4 - A4 G4 | E4 - G4 A4 B4 - D5 - | C5 - B4 A4 G4 - E4 - | D4 - E4 - - - . .",
      "E2 - - E3 E2 - - E3 | E2 - - E3 G2 - - G3 | A2 - - A3 A2 - - A3 | B2 - - B3 E2 - . .",
    ],
    bpm: 175, style: "action",
    tags: ["fast", "heroic", "intense", "gameplay", "shooter"],
  };

  BGM.ZERO_HOUR = {
    tracks: [
      "A4 A4 . C5 C5 . A4 . | G4 G4 . A4 . E4 . . | F4 F4 . A4 A4 . F4 . | E4 . D4 . E4 - - -",
      "A2 - E3 - A2 - E3 - | G2 - D3 - G2 - D3 - | F2 - C3 - F2 - C3 - | E2 - B2 - E2 - - -",
    ],
    bpm: 185, style: "action",
    tags: ["fast", "tense", "urgent", "gameplay", "shooter"],
  };

  BGM.FLAK_ALLEY = {
    tracks: [
      "D4 . F4 . A4 . D5 . | C5 . A4 . F4 . A4 . | B4 . G4 . D4 . G4 . | A4 . F4 . D4 - - .",
      "D2 D3 D2 D3 D2 D3 D2 D3 | F2 F3 F2 F3 F2 F3 F2 F3 | G2 G3 G2 G3 G2 G3 G2 G3 | D2 D3 D2 D3 D2 - - .",
    ],
    bpm: 195, style: "action",
    tags: ["fast", "driving", "intense", "gameplay", "retro"],
  };

  // ================================================================
  //  MARCH / MILITARY
  // ================================================================

  BGM.VALOR_MARCH = {
    tracks: [
      "C4 - E4 - G4 - - C5 | - - G4 - E4 - C4 - | D4 - F4 - A4 - - D5 | - - A4 - F4 - D4 -",
      "C3 - - G2 - - C3 - | E2 - - G2 - - C3 - | D3 - - A2 - - D3 - | F2 - - A2 - - D3 -",
    ],
    bpm: 140, style: "march",
    tags: ["medium", "heroic", "military", "title", "march"],
  };

  BGM.RISING_SUN = {
    tracks: [
      "A3 - C4 - E4 - A4 - | - - - - G4 - E4 - | F3 - A3 - C4 - F4 - | - - - - E4 - C4 -",
      "A2 - - - - - E2 - | A2 - - - G2 - - - | F2 - - - - - C2 - | F2 - - - E2 - - -",
    ],
    bpm: 130, style: "march",
    tags: ["medium", "solemn", "military", "cutscene", "march"],
  };

  // ================================================================
  //  BALLAD / MELANCHOLIC
  // ================================================================

  BGM.LAST_WINGMAN = {
    tracks: [
      "E4 - - D4 - - C4 - | - - B3 - - - A3 - | - - - - G3 - - - | A3 - - - - - - -",
      "A2 - - - - - - - | E2 - - - - - - - | C2 - - - - - - - | A2 - - - - - - -",
    ],
    bpm: 100, style: "ballad",
    tags: ["slow", "sad", "emotional", "gameover", "ending"],
  };

  BGM.EMPTY_RUNWAY = {
    tracks: [
      "D4 - - - - F4 - - | - - - E4 - - D4 - | - - - - A3 - - - | - - - - - - - -",
      "D2 - - - - - - - | A2 - - - - - - - | F2 - - - - - - - | D2 - - - - - - -",
    ],
    bpm: 85, style: "ballad",
    tags: ["slow", "sad", "lonely", "gameover", "ending"],
  };

  // ================================================================
  //  EXPERIMENTAL
  // ================================================================

  BGM.RADAR_PING = {
    tracks: [
      "C5 . . . . . . . | . . . . C5 . . . | . . . . . . . . | E5 . . . . . . .",
      "C3 - - - - - - - | C3 - - - - - - - | G2 - - - - - - - | C3 - - - - - - -",
    ],
    bpm: 110, style: "experimental",
    tags: ["medium", "minimal", "suspense", "mysterious", "menu"],
  };

  BGM.STATIC_FIELD = {
    tracks: [
      "C4 D#4 F#4 A4 C5 A4 F#4 D#4 | D4 F4 G#4 B4 D5 B4 G#4 F4 | C4 D#4 F#4 A4 C5 A4 F#4 D#4 | B3 D4 F4 G#4 B4 - - -",
      "C2 - - - C2 - - - | D2 - - - D2 - - - | C2 - - - C2 - - - | B1 - - - B1 - - -",
    ],
    bpm: 160, style: "experimental",
    tags: ["fast", "dark", "tense", "boss", "mysterious"],
  };

  // ================================================================
  //  PLATFORMER
  // ================================================================

  BGM.BOUNCY_TOWN = {
    tracks: [
      "C4 E4 G4 E4 C4 G3 C4 . | D4 F4 A4 F4 D4 A3 D4 . | E4 G4 B4 G4 E4 B3 E4 . | C4 E4 G4 C5 G4 E4 C4 .",
      "C3 . G2 . C3 . G2 . | D3 . A2 . D3 . A2 . | E3 . B2 . E3 . B2 . | C3 . G2 . C3 . . .",
    ],
    bpm: 160, style: "platformer",
    tags: ["fast", "cheerful", "bouncy", "gameplay", "platformer"],
  };

  BGM.MUSHROOM_WALK = {
    tracks: [
      "G4 . G4 . A4 . B4 - | C5 . B4 . A4 . G4 . | F4 . F4 . G4 . A4 - | G4 . F4 . E4 . D4 .",
      "C3 G3 C3 G3 C3 G3 C3 G3 | F2 C3 F2 C3 F2 C3 F2 C3 | D3 A3 D3 A3 D3 A3 D3 A3 | G2 D3 G2 D3 G2 D3 G2 D3",
    ],
    bpm: 150, style: "platformer",
    tags: ["medium", "cheerful", "playful", "gameplay", "platformer"],
  };

  BGM.TREETOP_DASH = {
    tracks: [
      "E5 D5 C5 B4 A4 G4 A4 B4 | C5 D5 E5 . E5 . D5 . | C5 B4 A4 G4 F4 E4 F4 G4 | A4 B4 C5 - - - . .",
      "A2 - E3 - A2 - E3 - | A2 - E3 - G2 - D3 - | F2 - C3 - F2 - C3 - | A2 - E3 - A2 - . .",
    ],
    bpm: 190, style: "platformer",
    tags: ["fast", "exciting", "cheerful", "gameplay", "platformer"],
  };

  // ================================================================
  //  PUZZLE
  // ================================================================

  BGM.THINK_TANK = {
    tracks: [
      "C4 - - E4 - - G4 - | - - - - F4 - - - | D4 - - F4 - - A4 - | - - - - G4 - - -",
      "C3 - - - - - - - | F2 - - - - - - - | D3 - - - - - - - | G2 - - - - - - -",
    ],
    bpm: 95, style: "puzzle",
    tags: ["slow", "calm", "thoughtful", "gameplay", "puzzle"],
  };

  BGM.CRYSTAL_LOGIC = {
    tracks: [
      "E4 . G4 . B4 . E5 . | D5 . B4 . G4 . D4 . | C4 . E4 . A4 . C5 . | B4 . A4 . G4 . E4 .",
      "E2 - - - - - - - | G2 - - - - - - - | A2 - - - - - - - | E2 - - - - - - -",
    ],
    bpm: 120, style: "puzzle",
    tags: ["medium", "calm", "clean", "gameplay", "puzzle"],
  };

  BGM.BLOCK_CASCADE = {
    tracks: [
      "A4 . A4 . C5 . B4 . | A4 . G4 . E4 . G4 . | A4 . A4 . C5 . D5 . | C5 . B4 . A4 - - -",
      "A2 E3 A2 E3 A2 E3 A2 E3 | C3 G3 C3 G3 C3 G3 C3 G3 | F2 C3 F2 C3 F2 C3 F2 C3 | A2 E3 A2 E3 A2 - - -",
    ],
    bpm: 140, style: "puzzle",
    tags: ["medium", "catchy", "playful", "gameplay", "puzzle"],
  };

  // ================================================================
  //  RACING
  // ================================================================

  BGM.NITRO_RUSH = {
    tracks: [
      "E4 E4 G4 E4 A4 A4 G4 E4 | D4 D4 F4 D4 G4 G4 F4 D4 | E4 E4 G4 E4 B4 B4 A4 G4 | E4 - G4 - A4 - B4 -",
      "E2 - B2 - E2 - B2 - | D2 - A2 - D2 - A2 - | E2 - B2 - E2 - B2 - | E2 - - - E2 - - -",
    ],
    bpm: 210, style: "racing",
    tags: ["fast", "exciting", "driving", "gameplay", "racing"],
  };

  BGM.TURBO_LANE = {
    tracks: [
      "A4 C5 A4 C5 D5 C5 A4 . | G4 B4 G4 B4 D5 B4 G4 . | F4 A4 F4 A4 C5 A4 F4 . | E4 G4 A4 B4 C5 D5 E5 -",
      "A2 . A2 . A2 . A2 . | G2 . G2 . G2 . G2 . | F2 . F2 . F2 . F2 . | E2 . E2 . E2 . E2 .",
    ],
    bpm: 200, style: "racing",
    tags: ["fast", "intense", "driving", "gameplay", "racing"],
  };

  // ================================================================
  //  RPG / ADVENTURE
  // ================================================================

  BGM.QUEST_BEGIN = {
    tracks: [
      "C4 - E4 - G4 - C5 - | - - B4 - A4 - G4 - | F4 - A4 - C5 - - - | B4 - G4 - E4 - C4 -",
      "C2 - - - G2 - - - | A2 - - - E2 - - - | F2 - - - C2 - - - | G2 - - - C2 - - -",
    ],
    bpm: 120, style: "rpg",
    tags: ["medium", "heroic", "adventure", "title", "rpg"],
  };

  BGM.DUNGEON_CRAWL = {
    tracks: [
      "E3 - - G3 - - A3 - | - - B3 - - - A3 - | E3 - - G3 - - B3 - | - - A3 - - - G3 -",
      "E2 - - - - - - - | A2 - - - - - - - | E2 - - - - - - - | C2 - - - - - - -",
    ],
    bpm: 90, style: "rpg",
    tags: ["slow", "dark", "mysterious", "gameplay", "rpg"],
  };

  BGM.VILLAGE_MORNING = {
    tracks: [
      "G4 - A4 - B4 - - - | D5 - C5 - B4 - A4 - | G4 - A4 - B4 - D5 - | C5 - - - - - - -",
      "G2 - D3 - G2 - D3 - | G2 - D3 - G2 - D3 - | C3 - G3 - C3 - G3 - | C3 - - - - - - -",
    ],
    bpm: 110, style: "rpg",
    tags: ["medium", "calm", "peaceful", "menu", "rpg"],
  };

  BGM.FINAL_TOWER = {
    tracks: [
      "A4 - C5 - E5 - C5 A4 | G#4 - B4 - E5 - B4 G#4 | A4 - C5 - E5 - F5 E5 | D5 - C5 - A4 - - -",
      "A2 - E3 - A2 - E3 - | E2 - B2 - E2 - B2 - | A2 - E3 - A2 - E3 - | D2 - A2 - D2 - - -",
    ],
    bpm: 155, style: "rpg",
    tags: ["fast", "heroic", "intense", "boss", "rpg"],
  };

  // ================================================================
  //  HORROR / SUSPENSE
  // ================================================================

  BGM.CREEPING_DARK = {
    tracks: [
      "D#3 - - - - - E3 - | - - - - - - D#3 - | - - - - F3 - - - | - - - - - - - -",
      "B1 - - - - - - - | C2 - - - - - - - | A1 - - - - - - - | B1 - - - - - - -",
    ],
    bpm: 60, style: "horror",
    tags: ["slow", "dark", "creepy", "suspense", "horror"],
  };

  BGM.DREAD_SIGNAL = {
    tracks: [
      "C4 . . . D#4 . . . | . . F4 . . . . . | D#4 . . . C4 . . . | . . . . . . . .",
      "C2 - - - - - - - | D#2 - - - - - - - | F2 - - - - - - - | C2 - - - - - - -",
    ],
    bpm: 75, style: "horror",
    tags: ["slow", "dark", "tense", "suspense", "horror"],
  };

  // ================================================================
  //  SPORTS / VERSUS
  // ================================================================

  BGM.KICKOFF = {
    tracks: [
      "C4 C4 E4 E4 G4 G4 C5 C5 | B4 B4 G4 G4 E4 E4 C4 C4 | D4 D4 F4 F4 A4 A4 D5 D5 | C5 - - - G4 - - -",
      "C2 - G2 - C2 - G2 - | E2 - G2 - E2 - G2 - | D2 - A2 - D2 - A2 - | C2 - G2 - C2 - - -",
    ],
    bpm: 170, style: "sports",
    tags: ["fast", "exciting", "energetic", "gameplay", "sports"],
  };

  BGM.VICTORY_LAP = {
    tracks: [
      "C5 - E5 - G5 - - - | E5 - C5 - G4 - - - | A4 - C5 - E5 - - - | G5 - - - - - - -",
      "C3 - G3 - C3 - G3 - | C3 - G3 - C3 - G3 - | A2 - E3 - A2 - E3 - | C3 - - - - - - -",
    ],
    bpm: 135, style: "sports",
    tags: ["medium", "cheerful", "triumphant", "ending", "sports"],
  };

  // ================================================================
  //  SPACE / SCI-FI
  // ================================================================

  BGM.STAR_DRIFT = {
    tracks: [
      "E4 - - - - - G4 - | - - - - - - A4 - | - - - - B4 - - - | - - - - A4 - G4 -",
      "E2 - - - - - - - | C2 - - - - - - - | G2 - - - - - - - | A2 - - - - - - -",
    ],
    bpm: 85, style: "space",
    tags: ["slow", "calm", "spacey", "title", "scifi"],
  };

  BGM.WARP_DRIVE = {
    tracks: [
      "E4 G4 B4 E5 B4 G4 E4 G4 | D4 F#4 A4 D5 A4 F#4 D4 F#4 | C4 E4 G4 C5 G4 E4 C4 E4 | B3 D#4 F#4 B4 F#4 D#4 B3 .",
      "E2 - - E2 - - E2 - | D2 - - D2 - - D2 - | C2 - - C2 - - C2 - | B1 - - B1 - - B1 .",
    ],
    bpm: 180, style: "space",
    tags: ["fast", "intense", "spacey", "gameplay", "scifi"],
  };

  BGM.NEBULA_WALTZ = {
    tracks: [
      "G4 - - B4 - - D5 - | - - C5 - - A4 - - | F4 - - A4 - - C5 - | - - B4 - - G4 - -",
      "G2 - - - - - - - | A2 - - - - - - - | F2 - - - - - - - | G2 - - - - - - -",
    ],
    bpm: 100, style: "space",
    tags: ["slow", "dreamy", "spacey", "menu", "scifi"],
  };

  // --- Shorthand: bgm(preset) plays with preset's BPM ---
  var origBgm = Mono.bgm;
  Mono.bgm = function(tracksOrPreset, bpm, loop) {
    if (tracksOrPreset && tracksOrPreset.tracks) {
      origBgm(tracksOrPreset.tracks, bpm || tracksOrPreset.bpm, loop);
    } else {
      origBgm(tracksOrPreset, bpm, loop);
    }
  };

  Mono.BGM = BGM;
})();
