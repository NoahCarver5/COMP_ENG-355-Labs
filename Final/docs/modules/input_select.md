# input_select

Mux that picks between the button path and the camera path based on SW0.

## Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 100 MHz system clock |
| `sw0` | in | 1 | Switch 0: `'0'` = buttons, `'1'` = camera |
| `btn_hand` | in | record | `hand_t` from button_input |
| `cam_hand` | in | record | `hand_t` from color_tracker |
| `hand` | out | record | `hand_t` forwarded to game_logic and renderer |

## Behavior

- Pure registered mux: on each rising edge, copy `btn_hand` or `cam_hand` to `hand` based on `sw0`.
- Switching modes mid-game is safe — game_logic only acts on `hand.strike` pulses, so a mid-frame switch at most skips one input cycle.

## Notes

- Registering the output prevents glitches on the `hand.strike` line when SW0 toggles.
- color_tracker is a stretch goal; this module still synthesizes correctly when cam_hand is tied to zeros.
