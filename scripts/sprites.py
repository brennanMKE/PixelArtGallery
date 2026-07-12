#!/usr/bin/env python3
"""
Pixel Art Gallery sprite generator for FlaschenTaschen (45x35).
Each sprite is drawn on its own native grid, then integer-scaled up
(uniform, nearest-neighbor, largest multiple that fits) and centered onto a
45x35 canvas. Every color edge lands on a pixel boundary.
"""
from PIL import Image
import argparse
import os

W, H = 45, 35

# Palette (8-bit-ish)
_ = None            # transparent -> becomes background
K = (0, 0, 0)       # black outline
WH_ = (255, 255, 255)
R = (224, 32, 32)
G = (32, 200, 64)
B = (48, 96, 240)
Y = (248, 216, 40)
C = (64, 224, 224)
M = (240, 64, 200)
O = (248, 144, 32)
P = (168, 80, 224)
S = (200, 200, 200)   # silver/steel
D = (96, 96, 96)      # dark grey
F = (240, 176, 128)   # flesh

BG = (12, 12, 20)     # near-black background for the wall


def grid(rows):
    """rows: list of strings using single-char keys mapped below."""
    return rows


LEGEND = {
    '.': _, 'k': K, 'w': WH_, 'r': R, 'g': G, 'b': B,
    'y': Y, 'c': C, 'm': M, 'o': O, 'p': P, 's': S,
    'd': D, 'f': F,
}


def render(rows, bg=BG):
    h = len(rows)
    w = max(len(r) for r in rows)
    # Draw the sprite on its native grid (transparent cells -> bg).
    native = Image.new("RGB", (w, h), bg)
    px = native.load()
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            col = LEGEND.get(ch, _)
            if col is not None:
                px[i, j] = col
    # Largest uniform integer scale that fits the canvas; nearest keeps edges crisp.
    scale = max(1, min(W // w, H // h))
    scaled = native.resize((w * scale, h * scale), Image.NEAREST)
    img = Image.new("RGB", (W, H), bg)
    img.paste(scaled, ((W - scaled.width) // 2, (H - scaled.height) // 2))
    return img


sprites = {}

# --- Space Invader (classic crab) ---
sprites["invader"] = grid([
    "..g.....g..",
    "...g...g...",
    "..ggggggg..",
    ".gg.ggg.gg.",
    "ggggggggggg",
    "g.ggggggg.g",
    "g.g.....g.g",
    "...gg.gg...",
])

# --- Ghost (Pac-Man style) ---
sprites["ghost"] = grid([
    "...mmmmm...",
    "..mmmmmmm..",
    ".mmmmmmmmm.",
    ".mwwmmwwm m".replace(" ", ""),
    ".mwbmmwbm m".replace(" ", ""),
    ".mmmmmmmmm.",
    ".mmmmmmmmm.",
    ".mm.mm.mm..",
])

# --- Pac-Man ---
sprites["pacman"] = grid([
    "...yyyyy...",
    ".yyyyyyyyy.",
    "yyyyyyy....",
    "yyyyyy.....",
    "yyyyy......",
    "yyyyyy.....",
    "yyyyyyy....",
    ".yyyyyyyyy.",
    "...yyyyy...",
])

# --- Heart ---
sprites["heart"] = grid([
    ".rr...rr.",
    "rrrr.rrrr",
    "rrrrrrrrr",
    "rrrrrrrrr",
    ".rrrrrrr.",
    "..rrrrr..",
    "...rrr...",
    "....r....",
])

# --- Mushroom (1-up style) ---
sprites["mushroom"] = grid([
    "...kkkkk...",
    ".kkrrrrrkk.",
    ".krwwrrwwk.",
    "kkrwwrrwwrk",
    "krrrrrrrrrk",
    "kwwkffkkwwk".replace("f", "w"),
    ".kwffffwk..".replace("f", "w"),
    "..kkfkfkk..".replace("f", "w"),
    "...kkkk....",
])

# --- Robot / Bot ---
sprites["robot"] = grid([
    "..sssssss..",
    ".s.......s.",
    ".s.cc.cc.s.",
    ".s.......s.",
    ".sssssssss.",
    "d.sssssss.d",
    "d.s.....s.d",
    "..ss...ss..",
    "..dd...dd..",
])

# --- Spaceship ---
sprites["ship"] = grid([
    ".....w.....",
    "....www....",
    "...wwwww...",
    "..wwcccww..",
    ".wwwcccwww.",
    "wwwwwwwwwww",
    "ww.wwwww.ww",
    "o..o.o.o..o",
    "...o...o...",
])

# --- Star ---
sprites["star"] = grid([
    "....y....",
    "....y....",
    "...yyy...",
    "yyyyyyyyy",
    ".yyyyyyy.",
    "..yyyyy..",
    ".yyy.yyy.",
    ".yy...yy.",
    "y.......y",
])

# --- Skull ---
sprites["skull"] = grid([
    ".wwwwwww.",
    "wwwwwwwww",
    "wkkwwwkkw",
    "wkkwwwkkw",
    "wwwwwwwww",
    "wwwkwkwww",
    ".wwwwwww.",
    ".w.w.w.w.",
    ".w.w.w.w.",
])

# --- Coin ---
sprites["coin"] = grid([
    "..ooooo..",
    ".ooyyyoo.",
    "ooyyyyyoo",
    "ooyyoyyoo",
    "ooyyoyyoo",
    "ooyyoyyoo",
    "ooyyyyyoo",
    ".ooyyyoo.",
    "..ooooo..",
])

# --- Frog ---
sprites["frog"] = grid([
    ".gg...gg.",
    "gwgg.ggwg".replace("w", "k"),
    "ggkg.gkgg",
    ".ggggggg.",
    "ggggggggg",
    "gg.ggg.gg",
    "g.gg.gg.g",
    ".g.....g.",
])

def main():
    parser = argparse.ArgumentParser(
        description="Generate FlaschenTaschen (45x35) pixel-art sprite PNGs.")
    parser.add_argument(
        "output_dir",
        help="Directory to write the sprite PNGs into (created if missing).")
    args = parser.parse_args()

    out = args.output_dir
    os.makedirs(out, exist_ok=True)

    for name, rows in sprites.items():
        img = render(rows)
        img.save(os.path.join(out, f"{name}.png"))

    print(f"Generated {len(sprites)} sprites in {out}")
    print(", ".join(sprites.keys()))


if __name__ == "__main__":
    main()
