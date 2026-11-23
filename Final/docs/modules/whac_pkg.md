# whac_pkg

Shared package imported by every module. No entity — package only.

## Contents

| Name | Type | Value / Description |
|------|------|---------------------|
| `NUM_HOLES` | constant integer | 6 (3 columns × 2 rows) |
| `HOLE_CX` | integer array (0–5) | Pixel column of each hole center |
| `HOLE_CY` | integer array (0–5) | Pixel row of each hole center |
| `HOLE_R` | constant integer | Hole radius in pixels |
| `game_state_t` | enum | `IDLE`, `PLAY`, `GAME_OVER` |
| `mole_state_t` | enum | `HIDDEN`, `RISING`, `VISIBLE`, `FALLING` |
| `hand_t` | record | `x` (10-bit), `y` (9-bit), `valid`, `strike`, `update` |
| `bcd_pair_t` | record | `tens` (3-bit), `ones` (4-bit) |

## Notes

- Hole layout is fixed for 640×480: two rows, three columns, evenly spaced.
- All modules use `hand_t` record for the cursor/glove interface.
- `bcd_pair_t` values are capped at 99 by game_logic.
