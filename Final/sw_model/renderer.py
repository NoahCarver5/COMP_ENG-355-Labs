from PIL import Image, ImageDraw, ImageFont
from game_logic import GameSnapshot, GameState, MoleState

# ---------------------------------------------------------------------------
# Layout constants — must match whac_pkg.vhd HOLE_CX / HOLE_CY / HOLE_R
# ---------------------------------------------------------------------------
WIDTH  = 640
HEIGHT = 480

HOLE_R  = 60
HOLE_CX = [160, 320, 480, 160, 320, 480]  # column centers for holes 0–5
HOLE_CY = [160, 160, 160, 320, 320, 320]  # row centers for holes 0–5

# Colors (R, G, B)
COLOR_BG      = (34, 139, 34)   # green field
COLOR_HOLE    = (30,  20,  10)   # dark hole
COLOR_MOLE    = (139,  90,  43)  # brown mole
COLOR_CURSOR  = (255, 255,   0)  # yellow cursor ring
COLOR_OVERLAY = (0,    0,    0)  # overlay background


def render_frame(snap: GameSnapshot) -> Image.Image:
    img  = Image.new("RGB", (WIDTH, HEIGHT), COLOR_BG)
    draw = ImageDraw.Draw(img)

    _draw_holes(draw)
    _draw_moles(draw, snap)
    _draw_cursor(draw, snap.cursor_hole)
    _draw_overlay(draw, snap)

    return img


# ---------------------------------------------------------------------------
# Layer helpers
# ---------------------------------------------------------------------------
def _draw_holes(draw: ImageDraw.ImageDraw):
    for cx, cy in zip(HOLE_CX, HOLE_CY):
        _circle(draw, cx, cy, HOLE_R, COLOR_HOLE)


def _draw_moles(draw: ImageDraw.ImageDraw, snap: GameSnapshot):
    for i, state in enumerate(snap.mole_states):
        if state == MoleState.VISIBLE:
            _circle(draw, HOLE_CX[i], HOLE_CY[i], HOLE_R - 10, COLOR_MOLE)


def _draw_cursor(draw: ImageDraw.ImageDraw, hole: int):
    cx, cy = HOLE_CX[hole], HOLE_CY[hole]
    r = HOLE_R + 10
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=COLOR_CURSOR, width=5)


def _draw_overlay(draw: ImageDraw.ImageDraw, snap: GameSnapshot):
    if snap.game_state == GameState.IDLE:
        _text_centered(draw, "Press KEY0 to start", WIDTH // 2, HEIGHT // 2)
    elif snap.game_state == GameState.GAME_OVER:
        _text_centered(draw, "GAME OVER", WIDTH // 2, HEIGHT // 2 - 20)
        _text_centered(draw, f"Score: {snap.score}", WIDTH // 2, HEIGHT // 2 + 20)


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
def _circle(draw, cx, cy, r, color):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def _text_centered(draw, text, x, y):
    # semi-transparent dark box + white text
    bbox = draw.textbbox((0, 0), text)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    pad = 8
    draw.rectangle([x - w//2 - pad, y - h//2 - pad,
                    x + w//2 + pad, y + h//2 + pad], fill=COLOR_OVERLAY)
    draw.text((x - w//2, y - h//2), text, fill=(255, 255, 255))
