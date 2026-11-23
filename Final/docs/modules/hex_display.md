# hex_display

Drives the six 7-segment displays: HEX1–HEX0 for score, HEX5–HEX4 for time remaining.

## Ports (per instance)

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `digit` | in | 4 | BCD digit (0–9) |
| `seg` | out | 7 | Active-low segment drive (a–g) |

Instantiated 6× in the top level; `digit` wired to tens/ones fields of `score` and `time_left` from game_logic.

## Behavior

- Pure combinational decode table: 10 entries (0–9) → 7-bit segment pattern.
- Input > 9 outputs all segments off (blank).
- Active-low: `seg = "0000001"` displays `0`.

## Notes

- HEX3–HEX2 are unused; tie their `seg` outputs to `"1111111"` (all off) in the top level.
- Segment ordering follows the DE-series board convention: `seg[6]` = segment g (center bar).
