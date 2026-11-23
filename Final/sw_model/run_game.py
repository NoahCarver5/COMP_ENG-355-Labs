"""
Run a scripted game and dump BMP frames to out/.
Used to generate golden reference output for VHDL testbenches.
"""
import os
from game_logic import GameLogic
from renderer import render_frame

OUT_DIR = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Input script: list of (frame, move, strike)
# frame  — frame number to apply the input on
# move   — -1 / 0 / +1
# strike — True to smash
# ---------------------------------------------------------------------------
SCRIPT = [
    (0,   0,  True),   # start game
    (90,  1,  False),  # move right at frame 90
    (91,  0,  True),   # smash
    (180, -1, False),  # move left
    (181, 0,  True),   # smash
]

def run(num_frames: int = 300, save_every: int = 10):
    gl     = GameLogic(seed=42)
    script = {f: (m, s) for f, m, s in SCRIPT}

    for frame in range(num_frames):
        move, strike = script.get(frame, (0, False))
        snap = gl.tick(move=move, strike=strike)

        if frame % save_every == 0:
            img  = render_frame(snap)
            path = os.path.join(OUT_DIR, f"frame_{frame:04d}.bmp")
            img.save(path)
            print(f"frame {frame:4d} | state={snap.game_state.name:9s} "
                  f"score={snap.score} time={snap.time_left_s}s "
                  f"moles={[m.name for m in snap.mole_states]}")

    print(f"\nFrames saved to {OUT_DIR}/")

if __name__ == "__main__":
    run()
