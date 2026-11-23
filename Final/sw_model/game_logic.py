from dataclasses import dataclass
from enum import Enum, auto
import random

# ---------------------------------------------------------------------------
# Timing constants (all in frames; one tick = one frame at 60 fps)
# ---------------------------------------------------------------------------
FPS             = 60
GAME_DURATION_S = 60
NUM_HOLES       = 6
MAX_ACTIVE      = 2       # max moles visible at once
VISIBLE_MIN     = 60      # 1 s minimum visible time
VISIBLE_MAX     = 180     # 3 s maximum visible time
SPAWN_INTERVAL  = 45      # frames between spawn attempts


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------
class GameState(Enum):
    IDLE      = auto()
    PLAY      = auto()
    GAME_OVER = auto()

class MoleState(Enum):
    HIDDEN  = auto()
    VISIBLE = auto()


# ---------------------------------------------------------------------------
# Internal per-hole state
# ---------------------------------------------------------------------------
@dataclass
class _Mole:
    state: MoleState = MoleState.HIDDEN
    timer: int = 0   # frames remaining visible


# ---------------------------------------------------------------------------
# Public snapshot — what renderer and testbench consume
# ---------------------------------------------------------------------------
@dataclass
class GameSnapshot:
    game_state:  GameState
    mole_states: list   # MoleState per hole, len 6
    cursor_hole: int    # which hole the cursor is on (0–5)
    score:       int    # 0–99
    time_left_s: int    # whole seconds remaining
    score_tens:  int    # BCD
    score_ones:  int
    time_tens:   int
    time_ones:   int


# ---------------------------------------------------------------------------
# GameLogic
# ---------------------------------------------------------------------------
class GameLogic:
    """
    Behavioral model of the game FSM. One tick = one frame (1/60 s).

    seed — matches the LFSR seed used in the VHDL testbench.
    """

    def __init__(self, seed: int = 42):
        self._seed = seed
        self.reset()

    def reset(self):
        self._rng         = random.Random(self._seed)
        self.game_state   = GameState.IDLE
        self._moles       = [_Mole() for _ in range(NUM_HOLES)]
        self._cursor      = 0
        self._score       = 0
        self._time_frames = GAME_DURATION_S * FPS
        self._spawn_cd    = 0 # spawn cooldown

    def tick(self, move: int = 0, strike: bool = False) -> GameSnapshot:
        """
        Advance one frame.
          move   : -1 = left, +1 = right, 0 = no movement
          strike : True for one frame when the player smashes
        Returns a GameSnapshot.
        """
        # Dispatch to state handlers
        if self.game_state == GameState.IDLE:
            self._tick_idle(strike)
        elif self.game_state == GameState.PLAY:
            self._tick_play(move, strike)
        elif self.game_state == GameState.GAME_OVER:
            self._tick_game_over(strike)

        return self._snapshot()

    # ------------------------------------------------------------------
    # State handlers
    # ------------------------------------------------------------------
    def _tick_idle(self, strike: bool):
        if strike:
            self.reset()
            self.game_state = GameState.PLAY

    def _tick_play(self, move: int, strike: bool):
        
        # move cursor
        self._cursor = (self._cursor + move) % NUM_HOLES

        # Hit detection
        if strike:
            if self._moles[self._cursor].state == MoleState.VISIBLE:
                self._score += 1
                self._moles[self._cursor].state = MoleState.HIDDEN

        # Decrement each visible mole's timer; hide on expiry
        for mole in self._moles:
            if mole.state == MoleState.VISIBLE:
                mole.timer -= 1
                if mole.timer <= 0:
                    mole.state = MoleState.HIDDEN

        # Spawn cooldown and game countdown
        self._spawn_cd -= 1
        if self._spawn_cd <= 0:
            self._try_spawn()
            self._spawn_cd = SPAWN_INTERVAL

        self._time_frames -= 1
        if self._time_frames <= 0:
            self.game_state = GameState.GAME_OVER


    def _tick_game_over(self, strike: bool):
        if strike:
            self.reset()
            self.game_state = GameState.IDLE
        

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _try_spawn(self):
        active = sum(1 for m in self._moles if m.state == MoleState.VISIBLE)
        if active >= MAX_ACTIVE:
            return
        hidden = [i for i, m in enumerate(self._moles) if m.state == MoleState.HIDDEN]
        if not hidden:
            return
        hole = self._rng.choice(hidden)
        self._moles[hole].state = MoleState.VISIBLE
        self._moles[hole].timer = self._rng.randint(VISIBLE_MIN, VISIBLE_MAX)

    def _snapshot(self) -> GameSnapshot:
        time_s = self._time_frames // FPS
        return GameSnapshot(
            game_state  = self.game_state,
            mole_states = [m.state for m in self._moles],
            cursor_hole = self._cursor,
            score       = self._score,
            time_left_s = time_s,
            score_tens  = self._score // 10,
            score_ones  = self._score % 10,
            time_tens   = time_s // 10,
            time_ones   = time_s % 10,
        )

