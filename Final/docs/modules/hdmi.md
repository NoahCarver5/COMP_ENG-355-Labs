# hdmi *(reused from Lab 5)*

Generates 640×480 @ 60 Hz HDMI timing and serializes RGB888 pixels over TMDS.

## Ports (key signals)

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 100 MHz system clock |
| `pixel_req` | out | 1 | Active-area pixel needed this cycle |
| `pixel_x` | out | 10 | Column of requested pixel (0–639) |
| `pixel_y` | out | 9 | Row of requested pixel (0–479) |
| `pixel_rgb` | in | 24 | RGB888 from renderer (must be valid 1 cycle after req) |
| `hdmi_*` | out | — | Physical HDMI differential pairs |

## Notes

- Reused directly from Lab 5; do not modify.
- `pixel_req` is the signal renderer uses as `pixel_req` input; renderer's 1-cycle latency is already accounted for in the Lab 5 timing.
- Blanking intervals (hsync/vsync) are handled internally; renderer output is ignored during blanking.
