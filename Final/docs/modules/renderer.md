# renderer

Per-pixel layer compositor. Given a pixel coordinate request, outputs RGB888 color within 1 clock cycle.

## Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 100 MHz system clock |
| `pixel_req` | in | 1 | HDMI module requests pixel this cycle |
| `pixel_x` | in | 10 | Column of requested pixel (0–639) |
| `pixel_y` | in | 9 | Row of requested pixel (0–479) |
| `game_state` | in | enum | `game_state_t` from game_logic |
| `mole_state` | in | array(0–5) | Per-hole `mole_state_t` from game_logic |
| `hand` | in | record | `hand_t` — cursor position |
| `pixel_rgb` | out | 24 | RGB888 color for the requested pixel |
| `pixel_valid` | out | 1 | Registered: valid 1 cycle after `pixel_req` |

## Layer Order (back to front)

1. **Background** — solid green field.
2. **Holes** — dark circle at each `HOLE_CX/CY` with radius `HOLE_R`.
3. **Moles** — 32×32 sprite from `sprite_rom`, centered on hole, only when `mole_state = VISIBLE`.
4. **Cursor/hammer** — 32×32 sprite, centered on `HOLE_CX/CY(hand.hole_idx)`. Flashes 1 frame on `hand.strike`.
5. **Overlays** — `IDLE`: "Press KEY0 to start" text; `GAME_OVER`: "GAME OVER" + final score text. (Simple pixel-font or colored rectangle placeholder.)

## Behavior

- Fully combinational layer checks; output registered once → 1-cycle latency.
- Sprite transparency: if `sprite_rom` pixel = `0xFF00FF`, fall through to the layer below.
- `sprite_rom` read address is computed from `(pixel_x − sprite_origin_x, pixel_y − sprite_origin_y)`.
- When `pixel_req = '0'`, output is don't-care (HDMI blanking period).

## Notes

- No frame buffer — all layers computed fresh for every pixel, every frame.
- `pixel_valid` is simply `pixel_req` delayed 1 cycle (register the output, not a FIFO).
- The 1-cycle latency must be accounted for in the HDMI timing wrapper.
