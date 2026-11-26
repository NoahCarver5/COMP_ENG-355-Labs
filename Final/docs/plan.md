# CE355 Final Project — Augmented Reality Whac-a-Mole

**Team 10:** You-wei (Terry) Lu, Noah Carver  
**Platform:** DE25 Agilex 5 FPGA · 640×480 HDMI @ 60 Hz

---

## Overview

Moles pop up randomly in a 3×2 grid. The player smashes them before they hide.  
Score and countdown timer display on the board's 7-segment displays.

**Minimum deliverable:** full game driven by buttons (KEY3/KEY2 to move, KEY0 to smash/start).  
**Stretch goal:** SW0 switches to D8M camera — a colored glove moves the cursor and smashes.

---

## Workflow

```
Week 1  Interfaces & specs for every module; Python model + BMP frame generator
Week 1  button_input, game_logic, renderer pass unit tests
Week 2  color_tracker passes synthetic-frame tests
Week 2  Full-system sim; base game running on board
Week 3  Tracker on recorded video → live camera
Week 3  Demo prep + report
```

---

## Module List

| Module | Source | Description |
|--------|--------|-------------|
| `button_input` | write | Sync + edge-detect KEY[3:0]; output hand interface (hole_idx, strike) |
| `game_logic` | write | FSM (IDLE→PLAY→GAME_OVER), LFSR mole scheduler, BCD score/timer |
| `renderer` | write | Per-pixel layer compositor → RGB888 output; uses sprite_rom |
| `sprite_rom` | write | M20K BRAM, 32×32 RGB888 sprites, transparent = 0xFF00FF, .mif init |
| `hex_display` | write | BCD → 7-seg for HEX5–HEX0 (score + time) |
| `input_select` | write | SW0 mux between button_cursor and color_tracker hand interfaces |
| `color_tracker` | write *(stretch)* | YCbCr centroid on D8M feed; taps video_store bus |
| `video_store` | reuse Lab 5 | Frame buffer BRAM (~300 M20K), clock-domain crossing |
| `d8m` | reuse Lab 5 | Bayer→RGB888 at 25 MHz camera clock |
| `hdmi` | reuse Lab 5 | 640×480 timing + HDMI serializer |
| `pixel_pkg` / `bram` | reuse Lab 5 | Shared pixel types and BRAM primitive |
| `whac_pkg` | write | Shared types: `game_state_t`, hole layout (HOLE_CX/CY/R), constants |
| PLL IP | Quartus IP | 50 MHz → 100 MHz system clock, 20 MHz camera clock |

---

## Hand Interface (shared between both input paths)

```
-- hand_t record (whac_pkg)
hole_idx : unsigned(2 downto 0)  -- selected hole 0–5
strike   : std_logic             -- smash pulse, 1 cycle
```

---

## Verification Plan

Each module has a VHDL testbench cross-checked against a Python reference model.

| Testbench | Checks |
|-----------|--------|
| `button_input_tb` | Left/right wrap, single smash pulse per press |
| `game_logic_tb` | Hits/misses, mole timeout, timer BCD, FSM transitions |
| `renderer_tb` | BMP output pixel-exact vs Python render |
| `color_tracker_tb` | Centroid within ±2 px of Python; no-glove false negatives |
| `whac_system_tb` | Full game, fixed LFSR seed, frame-by-frame vs Python model |

---

## Demo Success Criteria

- KEY3/KEY2 moves cursor exactly one hole per press; wrap-around correct.
- Score increments only on a hit (mole visible + correct hole smashed).
- Timer counts down once per second; game-over screen appears at 00.
- *(Stretch)* SW0 live-switches to glove control mid-game.

---

*Module-level docs: `docs/modules/<module>.md` (add per module as implemented)*
