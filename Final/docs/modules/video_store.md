# video_store *(reused from Lab 5)*

Frame buffer BRAM storing one full 640×480 RGB888 frame (~300 M20K blocks).  
Provides the only clock-domain crossing: camera side writes at 25 MHz, system side reads at 100 MHz.

## Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `wr_clk` | in | 1 | 25 MHz camera clock (write side) |
| `wr_en` | in | 1 | Write enable |
| `wr_addr` | in | 19 | Write address (0–307199) |
| `wr_data` | in | 24 | RGB888 pixel |
| `rd_clk` | in | 1 | 100 MHz system clock (read side) |
| `rd_en` | in | 1 | Read enable |
| `rd_addr` | in | 19 | Read address |
| `rd_data` | out | 24 | RGB888 pixel (1-cycle latency) |

## Notes

- Reused directly from Lab 5; do not modify.
- `color_tracker` taps `wr_en`, `wr_data`, and `wr_addr` on the write side.
- The true-dual-port M20K BRAM handles the clock crossing; no explicit CDC logic needed.
