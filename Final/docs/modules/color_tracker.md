# color_tracker *(stretch goal)*

Detects the centroid of a colored glove in the D8M video stream and outputs a `hand_t` cursor position.

## Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 100 MHz system clock |
| `wr_en` | in | 1 | Tapped from video_store write bus |
| `wr_data` | in | 24 | RGB888 pixel being written to frame buffer |
| `wr_addr` | in | 19 | Write address (row-major, 640×480 → 0–307199) |
| `hand` | out | record | `hand_t` — centroid position + strike pulse |

## Behavior

1. **Frame start detection:** `wr_addr = 0` signals the start of a new frame; reset accumulators.
2. **Color classification:** convert RGB888 → YCbCr per pixel. A pixel is "glove" if Cb and Cr fall within a calibrated green (or colored) range.
3. **Centroid accumulation:** running sums `sum_x`, `sum_y`, `count` over glove pixels in the current frame.
4. **End-of-frame output:** when `wr_addr` wraps back to 0 (or hits last pixel), compute `centroid_x = sum_x / count`, `centroid_y = sum_y / count`. Snap to nearest hole by comparing against `HOLE_CX/CY`; output as `hand.hole_idx`.
5. **Strike detection:** a glove pixel count spike (fist → open hand area change) generates `hand.strike` for 1 cycle. TBD: threshold values.
6. **No-glove guard:** if `count < MIN_PIXELS`, do not update `hand` (hold previous position).

## Notes

- Taps the video_store write bus — no extra memory port needed; processes pixels as they arrive.
- Division for centroid: use a right-shift approximation or a small iterative divider; exact division not required (±2 px tolerance per spec).
- YCbCr thresholds are calibration constants in `whac_pkg` or a separate `tracker_pkg`.
- Strike detection approach (area threshold vs. velocity threshold) is TBD — confirm before implementing.
