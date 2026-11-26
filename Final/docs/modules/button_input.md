# button_input

Translates raw KEY presses into the shared `hand_t` cursor interface.

## Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 100 MHz system clock |
| `rst` | in | 1 | Synchronous reset |
| `key` | in | 4 | Raw KEY[3:0] from board (active-low) |
| `hand` | out | record | `hand_t` — cursor position + strike pulse |

## Behavior

- Double-flop `key` for metastability; detect falling edge for each button.
- **KEY3** → move cursor left; **KEY2** → move cursor right. Cursor wraps around (0↔5) through the 3×2 hole grid.
- **KEY0** → assert `hand.strike` for exactly 1 clock cycle; also acts as start signal in IDLE.
- `hand.hole_idx` outputs the index (0–5) of the currently selected hole; wraps on left/right.

## Notes

- KEY1 is unused (reserved for reset or future use).
- No debounce needed beyond the double-flop — FPGA buttons have minimal bounce at 100 MHz.
