# game_logic

Central FSM that runs the game: mole scheduling, hit detection, scoring, and countdown timer.

## Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 100 MHz system clock |
| `rst` | in | 1 | Synchronous reset |
| `hand` | in | record | `hand_t` — cursor position + strike pulse |
| `game_state` | out | enum | Current `game_state_t` (IDLE / PLAY / GAME_OVER) |
| `mole_state` | out | array(0–5) | Per-hole `mole_state_t` |
| `score` | out | record | `bcd_pair_t` — displayed score (00–99) |
| `time_left` | out | record | `bcd_pair_t` — displayed countdown (00–99 seconds) |

## FSM States

| State | Entry condition | Exit condition |
|-------|----------------|----------------|
| `IDLE` | Reset | `hand.strike` pulse |
| `PLAY` | From IDLE | `time_left = 00` |
| `GAME_OVER` | From PLAY | `hand.strike` pulse → back to IDLE |

## Behavior

**PLAY state:**
- **Mole scheduler:** 6-bit LFSR picks which hole to show next and how long it stays visible. At most 2 holes active simultaneously.
- **Mole lifecycle:** `HIDDEN → RISING → VISIBLE → FALLING → HIDDEN`. Rising/falling durations are fixed cycle counts; visible duration is LFSR-derived.
- **Hit detection:** on `hand.strike`, check whether `hand.x/y` maps to a `VISIBLE` or `RISING` hole. If yes, force that hole to `FALLING` and increment score.
- **Timer:** a 100 MHz prescaler counts down `time_left` by 1 BCD second each second. Saturates at 00; triggers `GAME_OVER`.
- **Score:** BCD increment on each hit; saturates at 99.

## Notes

- LFSR seed is set at IDLE→PLAY transition; fixed seed in simulation for reproducibility.
- `mole_state` array is read directly by renderer and game_logic — no extra handshake needed.
- BCD arithmetic: ones overflow carries to tens; cap both at 9 to prevent wrap-around above 99.
