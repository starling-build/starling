#!/usr/bin/env python3
"""Make the sunset waterfront: a blocky city for the desktop to stand in.

    voxel-world.py [--out <dir>] [--size 96] [--seed 3]

The composition in city-night.py follows the city-night wallpaper with
terraced Victorian houses, a downhill trolley route, Ferry Building,
bay and bridge. One glTF with animated actors, emissive window textures
and six punctual street lights, plus an early-evening sky for cmgen.
world.json supplies fractional walking heights and the app anchors.
The earlier daylight layout helpers remain available for experiments.

Outputs: room.glb, room_ibl.ktx, room_skybox.ktx, world.json, atlas.png,
frame.png (the renderer's names for any world).
"""
import argparse
import importlib.util
import io
import json
import os
import struct
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# ------------------------------------------------------------ the atlas

TILE = 16
ATLAS = 8            # tiles per side
TILES = [
    "asphalt", "roadline", "sidewalk", "concrete", "window", "window_lit", "brick", "roof",
    "plaza", "grass", "log", "leaves", "lamp", "water", "dark", "stone",
    "crosswalk", "plaster_cream", "plaster_terra", "plaster_sage", "plaster_blue",
    "glass", "glass_lit", "steel", "door_top", "door_bottom", "shop",
    "awning_red", "awning_green", "awning_blue", "sign_red", "sign_blue", "sign_green",
    "sign_yellow", "sign_white", "sandstone", "sandstone_window", "flowers", "tank",
    "vent", "planks", "brick_window", "plaster_window", "cornice",
    "copper", "limestone", "paving_border", "bridge_red", "plaster_rose", "bronze",
    "cloud", "water_glint", "hill", "hill_far", "reflection_amber",
]
T = {name: i for i, name in enumerate(TILES)}
assert len(TILES) <= ATLAS * ATLAS


def noise_tile(rng, base, spread, dark=None, light=None):
    """A 16x16 tile of a base colour with per-pixel speckle."""
    t = np.zeros((TILE, TILE, 3), np.float32)
    t[:] = base
    t += rng.normal(0, spread, (TILE, TILE, 1))
    if dark is not None:
        m = rng.random((TILE, TILE)) < 0.12
        t[m] = dark
    if light is not None:
        m = rng.random((TILE, TILE)) < 0.08
        t[m] = light
    return np.clip(t, 0, 1)


def window_tile(rng, wall, glass, glass_hi, frame=(0.6, 0.6, 0.6), sill=None):
    win = noise_tile(rng, wall, 0.02)
    win[2:14, 2:14] = glass
    win[3:13, 3:8] = glass_hi
    win[2:14, 8] = frame
    if sill is not None:
        win[14, 1:15] = sill
    return win


def sign_tile(rng, bg, ink):
    s = noise_tile(rng, bg, 0.01)
    s[0, :] = s[15, :] = s[:, 0] = s[:, 15] = np.array(bg) * 0.6
    # Lettering: two rows of short dark runs, the way text reads from
    # across a street.
    for row in (4, 5, 9, 10):
        x = 2
        while x < 14:
            n = int(rng.integers(1, 3))
            if rng.random() < 0.75:
                s[row, x:min(x + n, 14)] = ink
            x += n + 1
    return s


def awning_tile(rng, colour):
    a = np.zeros((TILE, TILE, 3), np.float32)
    for x in range(TILE):
        a[:, x] = colour if (x // 2) % 2 == 0 else (0.95, 0.95, 0.92)
    a[15, :] = np.array(colour) * 0.7
    return a


def planks_tile(rng, base=(0.58, 0.42, 0.25), seam=(0.34, 0.24, 0.13)):
    p = noise_tile(rng, base, 0.02, None, (0.66, 0.5, 0.31))
    for y in range(0, TILE, 4):
        p[y, :] = seam
        off = 0 if (y // 4) % 2 == 0 else 8
        p[y:y + 4, (off + 3) % 16] = seam
    return p


def make_tiles(seed=1):
    rng = np.random.default_rng(seed)
    t = {}
    grey_dark = (0.5, 0.5, 0.48)
    t["asphalt"] = noise_tile(rng, (0.17, 0.17, 0.18), 0.02, (0.13, 0.13, 0.14), (0.22, 0.22, 0.23))
    line = noise_tile(rng, (0.17, 0.17, 0.18), 0.02)
    line[:, 7:9] = (0.85, 0.72, 0.2)
    t["roadline"] = line
    cross = noise_tile(rng, (0.17, 0.17, 0.18), 0.02)
    for x in range(1, 16, 4):
        cross[:, x:x + 2] = (0.9, 0.9, 0.88)
    t["crosswalk"] = cross
    walk = noise_tile(rng, (0.64, 0.63, 0.6), 0.02)
    walk[0, :] = grey_dark; walk[:, 0] = grey_dark
    t["sidewalk"] = walk
    t["concrete"] = noise_tile(rng, (0.74, 0.72, 0.68), 0.025, (0.66, 0.64, 0.6))
    t["window"] = window_tile(rng, (0.74, 0.72, 0.68), (0.22, 0.3, 0.42), (0.28, 0.38, 0.52))
    t["window_lit"] = window_tile(rng, (0.74, 0.72, 0.68), (0.98, 0.86, 0.5), (1.0, 0.92, 0.62))
    brick = noise_tile(rng, (0.6, 0.28, 0.2), 0.03, (0.5, 0.22, 0.16))
    mortar = (0.72, 0.68, 0.62)
    for y in range(TILE):
        if y % 4 == 0:
            brick[y] = mortar
        off = 0 if (y // 4) % 2 == 0 else 4
        for x in range(TILE):
            if (x + off) % 8 == 0:
                brick[y, x] = mortar
    t["brick"] = brick
    bw = brick.copy()
    bw[2:14, 2:14] = (0.2, 0.26, 0.36); bw[3:13, 3:8] = (0.26, 0.34, 0.46); bw[2:14, 8] = (0.85, 0.82, 0.78)
    bw[14, 1:15] = (0.8, 0.76, 0.7)
    t["brick_window"] = bw
    t["roof"] = noise_tile(rng, (0.24, 0.23, 0.22), 0.03, (0.18, 0.17, 0.16), (0.32, 0.31, 0.3))
    plaza = noise_tile(rng, (0.76, 0.71, 0.61), 0.008)
    plaza[0, :] = (0.64, 0.59, 0.50)
    plaza[:, 0] = (0.64, 0.59, 0.50)
    t["plaza"] = plaza
    t["grass"] = noise_tile(rng, (0.36, 0.62, 0.22), 0.04, (0.28, 0.5, 0.16), (0.46, 0.7, 0.3))
    flowers = t["grass"].copy()
    for _ in range(9):
        x, y = rng.integers(1, 15, 2)
        flowers[y, x] = [(0.9, 0.2, 0.2), (0.95, 0.85, 0.2), (0.95, 0.95, 0.95), (0.7, 0.3, 0.8)][int(rng.integers(0, 4))]
        flowers[y + 1, x] = (0.2, 0.42, 0.12)
    t["flowers"] = flowers
    log = noise_tile(rng, (0.4, 0.3, 0.18), 0.03)
    for x in range(0, TILE, 4):
        log[:, x] = (0.3, 0.22, 0.12)
    t["log"] = log
    t["leaves"] = noise_tile(rng, (0.2, 0.48, 0.14), 0.05, (0.12, 0.34, 0.08), (0.3, 0.6, 0.22))
    t["lamp"] = noise_tile(rng, (1.0, 0.92, 0.6), 0.02)
    t["water"] = noise_tile(rng, (0.14, 0.48, 0.53), 0.012)
    for row in (3, 11):
        t["water"][row, 3:10] = (0.25, 0.58, 0.61)
    t["dark"] = noise_tile(rng, (0.12, 0.12, 0.14), 0.02)
    t["stone"] = noise_tile(rng, (0.5, 0.5, 0.5), 0.035, (0.4, 0.4, 0.42), (0.58, 0.58, 0.58))
    # Painted plaster in a few colours, with a tall window that suits it.
    for name, col in (("plaster_cream", (0.9, 0.84, 0.68)), ("plaster_terra", (0.78, 0.46, 0.32)),
                      ("plaster_sage", (0.62, 0.7, 0.56)), ("plaster_blue", (0.5, 0.64, 0.78))):
        t[name] = noise_tile(rng, col, 0.015, None, tuple(min(1, c * 1.08) for c in col))
    pw = noise_tile(rng, (0.9, 0.84, 0.68), 0.015)
    pw[1:15, 4:12] = (0.2, 0.28, 0.4); pw[2:14, 5:8] = (0.28, 0.38, 0.52); pw[1:15, 8] = (0.92, 0.92, 0.9)
    pw[1:15, 3] = pw[1:15, 12] = (0.96, 0.95, 0.92); pw[15, 2:14] = (0.7, 0.66, 0.55)
    t["plaster_window"] = pw
    # A glass curtain wall: dark panes in a light mullion grid.
    glass = noise_tile(rng, (0.16, 0.24, 0.34), 0.02, None, (0.26, 0.36, 0.48))
    glass[0, :] = (0.55, 0.57, 0.6); glass[:, 0] = (0.55, 0.57, 0.6); glass[8, :] = (0.45, 0.47, 0.5)
    t["glass"] = glass
    gl = glass.copy(); gl[1:8, 1:16] = (0.9, 0.84, 0.6); gl[9:16, 1:16] = (0.95, 0.9, 0.7)
    gl[8, :] = (0.45, 0.47, 0.5); gl[:, 0] = (0.55, 0.57, 0.6)
    t["glass_lit"] = gl
    steel = noise_tile(rng, (0.55, 0.57, 0.6), 0.02, (0.48, 0.5, 0.53))
    steel[0, :] = (0.4, 0.42, 0.45); steel[:, 0] = (0.4, 0.42, 0.45)
    t["steel"] = steel
    t["cornice"] = noise_tile(rng, (0.82, 0.8, 0.76), 0.015, (0.7, 0.68, 0.64))
    t["cornice"][6:8, :] = (0.62, 0.6, 0.56); t["cornice"][12:14, :] = (0.62, 0.6, 0.56)
    # A door, two blocks tall: a pane in the top half, panels and a knob below.
    wood = (0.45, 0.3, 0.16); jamb = (0.3, 0.2, 0.1)
    top = noise_tile(rng, wood, 0.015); top[:, 0:2] = jamb; top[:, 14:16] = jamb; top[0:2, :] = jamb
    top[4:10, 4:12] = (0.55, 0.7, 0.85); top[5:9, 5:8] = (0.7, 0.82, 0.92); top[4:10, 8] = jamb
    t["door_top"] = top
    bot = noise_tile(rng, wood, 0.015); bot[:, 0:2] = jamb; bot[:, 14:16] = jamb; bot[14:16, :] = jamb
    bot[3:11, 4:12] = (0.4, 0.26, 0.13); bot[4:10, 5:11] = wood; bot[6:8, 12] = (0.9, 0.75, 0.3)
    t["door_bottom"] = bot
    # A shopfront: a big pane with something warm lit inside.
    shop = noise_tile(rng, (0.2, 0.3, 0.42), 0.02)
    shop[0, :] = shop[15, :] = shop[:, 0] = shop[:, 15] = (0.25, 0.25, 0.27)
    shop[8:13, 3:13] = (0.62, 0.5, 0.34); shop[9:12, 4:12] = (0.85, 0.72, 0.45)
    for k in range(1, 6):
        shop[k, 12 - k] = (0.45, 0.58, 0.72)
    t["shop"] = shop
    for name, col in (("awning_red", (0.8, 0.18, 0.16)), ("awning_green", (0.16, 0.5, 0.3)),
                      ("awning_blue", (0.18, 0.32, 0.68))):
        t[name] = awning_tile(rng, col)
    for name, bg, ink in (("sign_red", (0.78, 0.16, 0.14), (0.98, 0.94, 0.8)),
                          ("sign_blue", (0.16, 0.3, 0.62), (0.96, 0.96, 0.9)),
                          ("sign_green", (0.14, 0.46, 0.3), (0.96, 0.94, 0.8)),
                          ("sign_yellow", (0.94, 0.78, 0.2), (0.2, 0.16, 0.1)),
                          ("sign_white", (0.94, 0.93, 0.9), (0.16, 0.16, 0.2))):
        t[name] = sign_tile(rng, bg, ink)
    sand = noise_tile(rng, (0.8, 0.72, 0.55), 0.02, (0.7, 0.62, 0.46))
    sand[0, :] = (0.66, 0.58, 0.42); sand[8, :] = (0.66, 0.58, 0.42)
    sand[0:8, 5] = (0.66, 0.58, 0.42); sand[8:16, 12] = (0.66, 0.58, 0.42)
    t["sandstone"] = sand
    sw = sand.copy(); sw[1:14, 3:13] = (0.22, 0.28, 0.36); sw[2:13, 4:8] = (0.3, 0.38, 0.48)
    sw[1, 3] = sw[1, 12] = (0.8, 0.72, 0.55); sw[1:14, 8] = (0.78, 0.7, 0.55); sw[14, 2:14] = (0.62, 0.54, 0.4)
    t["sandstone_window"] = sw
    tank = noise_tile(rng, (0.5, 0.52, 0.55), 0.02, (0.55, 0.35, 0.25))
    tank[3, :] = tank[12, :] = (0.36, 0.38, 0.4)
    t["tank"] = tank
    vent = noise_tile(rng, (0.4, 0.42, 0.44), 0.02)
    for y in range(2, 14, 3):
        vent[y, 1:15] = (0.24, 0.25, 0.27)
    t["vent"] = vent
    t["planks"] = planks_tile(rng)
    t["copper"] = noise_tile(rng, (0.25, 0.43, 0.39), 0.012)
    t["copper"][:, 0] = (0.17, 0.31, 0.28)
    t["limestone"] = noise_tile(rng, (0.86, 0.80, 0.67), 0.008)
    t["paving_border"] = noise_tile(rng, (0.39, 0.43, 0.41), 0.009)
    t["bridge_red"] = noise_tile(rng, (0.72, 0.22, 0.12), 0.008)
    t["plaster_rose"] = noise_tile(rng, (0.78, 0.57, 0.55), 0.01)
    t["bronze"] = noise_tile(rng, (0.34, 0.25, 0.15), 0.006)
    t["cloud"] = noise_tile(rng, (0.78, 0.70, 0.68), 0.001)
    t["asphalt"] = noise_tile(rng, (0.14, 0.17, 0.22), 0.0)
    t["water"] = noise_tile(rng, (0.13, 0.23, 0.31), 0.002)
    t["water_glint"] = noise_tile(rng, (0.45, 0.55, 0.65), 0.001)
    t["hill"] = noise_tile(rng, (0.20, 0.28, 0.34), 0.001)
    t["hill_far"] = noise_tile(rng, (0.28, 0.36, 0.48), 0.001)
    t["reflection_amber"] = noise_tile(rng, (0.34, 0.19, 0.08), 0.002)
    t["leaves"] = noise_tile(rng, (0.20, 0.34, 0.28), 0.018)
    t["lamp"] = noise_tile(rng, (1.0, 0.65, 0.29), 0.005)
    return t


def make_atlas(path, frame_path, seed=1):
    tiles = make_tiles(seed)
    atlas = np.zeros((ATLAS * TILE, ATLAS * TILE, 3), np.float32)
    for name, i in T.items():
        r, c = divmod(i, ATLAS)
        atlas[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = tiles[name]
    Image.fromarray((atlas * 255).astype(np.uint8)).save(path)
    bronze = noise_tile(np.random.default_rng(seed), (0.34, 0.25, 0.15), 0.006)
    Image.fromarray((bronze * 255).astype(np.uint8)).save(frame_path)


def tile_uv(i):
    """The UV rectangle of a tile, inset half a texel so nothing bleeds."""
    r, c = divmod(i, ATLAS)
    e = 0.5 / (ATLAS * TILE)
    return (c / ATLAS + e, r / ATLAS + e, (c + 1) / ATLAS - e, (r + 1) / ATLAS - e)


# ------------------------------------------------------------ the land

# Block kinds: name -> (top tile, side tile, bottom tile).
BLOCKS = [
    ("air", None),
    ("asphalt", ("asphalt", "asphalt", "asphalt")),
    ("roadline", ("roadline", "asphalt", "asphalt")),
    ("crosswalk", ("crosswalk", "asphalt", "asphalt")),
    ("sidewalk", ("sidewalk", "sidewalk", "sidewalk")),
    ("concrete", ("concrete", "concrete", "concrete")),
    ("window", ("concrete", "window", "concrete")),
    ("window_lit", ("concrete", "window_lit", "concrete")),
    ("brick", ("brick", "brick", "brick")),
    ("brick_window", ("brick", "brick_window", "brick")),
    ("brick_window_lit", ("brick", "window_lit", "brick")),
    ("roof", ("roof", "concrete", "concrete")),
    ("plaza", ("plaza", "plaza", "plaza")),
    ("grass", ("grass", "grass", "grass")),
    ("flowers", ("flowers", "grass", "grass")),
    ("log", ("log", "log", "log")),
    ("leaves", ("leaves", "leaves", "leaves")),
    ("lamp", ("lamp", "lamp", "lamp")),
    ("water", ("water", "water", "water")),
    ("dark", ("dark", "dark", "dark")),
    ("stone", ("stone", "stone", "stone")),
    ("plaster_cream", ("plaster_cream",) * 3),
    ("plaster_terra", ("plaster_terra",) * 3),
    ("plaster_sage", ("plaster_sage",) * 3),
    ("plaster_blue", ("plaster_blue",) * 3),
    ("plaster_window", ("plaster_cream", "plaster_window", "plaster_cream")),
    ("glass", ("steel", "glass", "steel")),
    ("glass_lit", ("steel", "glass_lit", "steel")),
    ("steel", ("steel", "steel", "steel")),
    ("cornice", ("cornice", "cornice", "cornice")),
    ("door_top", ("concrete", "door_top", "concrete")),
    ("door_bottom", ("concrete", "door_bottom", "concrete")),
    ("shop", ("concrete", "shop", "concrete")),
    ("awning_red", ("awning_red",) * 3),
    ("awning_green", ("awning_green",) * 3),
    ("awning_blue", ("awning_blue",) * 3),
    ("sign_red", ("sign_red",) * 3),
    ("sign_blue", ("sign_blue",) * 3),
    ("sign_green", ("sign_green",) * 3),
    ("sign_yellow", ("sign_yellow",) * 3),
    ("sign_white", ("sign_white",) * 3),
    ("sandstone", ("sandstone",) * 3),
    ("sandstone_window", ("sandstone", "sandstone_window", "sandstone")),
    ("sandstone_window_lit", ("sandstone", "window_lit", "sandstone")),
    ("tank", ("tank", "tank", "tank")),
    ("vent", ("vent", "vent", "vent")),
    ("planks", ("planks",) * 3),
    ("limestone", ("limestone",) * 3),
    ("paving_border", ("paving_border",) * 3),
    ("plaster_rose", ("plaster_rose",) * 3),
]
B = {name: i for i, (name, _) in enumerate(BLOCKS)}
AIR, WATER = B["air"], B["water"]
# Face tiles as an array: [block][top, side, bottom] -> tile index.
FACE_TILES = np.zeros((len(BLOCKS), 3), np.int32)
for i, (name, faces) in enumerate(BLOCKS):
    if faces:
        FACE_TILES[i] = [T[f] for f in faces]
SOLID = np.array([i for i, (name, faces) in enumerate(BLOCKS) if faces and name != "water"])

CELL = 12        # a city block: 4 of street, then the lot
CLOCK_Z = 10     # the clock tower's centre column, this far from the square's middle, away from the door
G = 4            # ground level: the surface block's y
PAINTED_LADIES = ((-23, 8, "plaster_rose"), (-16, 11, "plaster_cream"),
                 (9, 11, "plaster_sage"), (16, 8, "plaster_blue"))


def workspace_rail():
    """Center and maximum card dimensions; shell distributes running apps."""
    return [dict(x=0, y=G + 3.45, z=-4, width=3.8, height=2.1)]

# Building styles: the wall block, its window, its lit window, how the
# windows are laid out, and the roof parapet.
STYLES = {
    "concrete": dict(wall="concrete", win="window", lit="window_lit", rows=2, gap=1, top="concrete"),
    "brick": dict(wall="brick", win="brick_window", lit="brick_window_lit", rows=2, gap=2, top="cornice"),
    "plaster_cream": dict(wall="plaster_cream", win="plaster_window", lit="window_lit", rows=2, gap=2, top="cornice"),
    "plaster_terra": dict(wall="plaster_terra", win="plaster_window", lit="window_lit", rows=2, gap=2, top="cornice"),
    "plaster_sage": dict(wall="plaster_sage", win="plaster_window", lit="window_lit", rows=2, gap=2, top="cornice"),
    "plaster_blue": dict(wall="plaster_blue", win="plaster_window", lit="window_lit", rows=2, gap=2, top="cornice"),
    "plaster_rose": dict(wall="plaster_rose", win="plaster_window", lit="window_lit", rows=3, gap=2, top="cornice"),
    "sandstone": dict(wall="sandstone", win="sandstone_window", lit="sandstone_window_lit", rows=3, gap=2, top="sandstone"),
    "glass": dict(wall="glass", win="glass", lit="glass_lit", rows=1, gap=0, top="steel"),
}
AWNINGS = ("awning_red", "awning_green", "awning_blue")
SIGNS = ("sign_red", "sign_blue", "sign_green", "sign_yellow", "sign_white")


def plant_tree(blocks, rng, x, base, z):
    trunk = int(rng.integers(4, 6))
    blocks[x, base:base + trunk, z] = B["log"]
    for dy, r in ((trunk - 3, 1), (trunk - 2, 2), (trunk - 1, 3),
                  (trunk, 3), (trunk + 1, 2), (trunk + 2, 1)):
        y = base + dy
        for dx in range(-r, r + 1):
            for dz in range(-r, r + 1):
                if dx * dx + dz * dz > r * r + 1:
                    continue
                xx, zz = x + dx, z + dz
                if 0 <= xx < blocks.shape[0] and 0 <= zz < blocks.shape[2] and blocks[xx, y, zz] == AIR:
                    blocks[xx, y, zz] = B["leaves"]


def build_tier(blocks, rng, x0, z0, x1, z1, y0, h, style, facing, door, shop):
    """One tier of a building: walls with windows from y0 up h blocks,
    a parapeted roof on top. `facing` is the wall the door is on
    (+x, -x, +z, -z as a unit pair), `door` whether this tier has one."""
    st = STYLES[style]
    wall, win, lit, top = B[st["wall"]], B[st["win"]], B[st["lit"]], B[st["top"]]
    rows, gap = st["rows"], st["gap"]
    lit_p = 0.22
    for x in range(x0, x1):
        for z in range(z0, z1):
            edge = x in (x0, x1 - 1) or z in (z0, z1 - 1)
            corner = x in (x0, x1 - 1) and z in (z0, z1 - 1)
            along = (x - x0) if z in (z0, z1 - 1) else (z - z0)
            for y in range(y0, y0 + h):
                if not edge:
                    blocks[x, y, z] = B["dark"]
                    continue
                floor = y - y0
                is_wall = corner or floor % rows != 1 or (gap and along % (gap + 1) == 0)
                if style == "glass":
                    is_wall = corner or floor % 4 == 3
                blocks[x, y, z] = wall if is_wall else (lit if rng.random() < lit_p else win)
            blocks[x, y0 + h, z] = top if edge else B["roof"]
    fx, fz = facing
    if fx:
        wx = x1 - 1 if fx > 0 else x0
        wz = (z0 + z1) // 2
        span = [(wx, wz + k) for k in (-1, 0, 1)]
        out = [(wx + fx, wz + k) for k in (-1, 0, 1)]
    else:
        wz = z1 - 1 if fz > 0 else z0
        wx = (x0 + x1) // 2
        span = [(wx + k, wz) for k in (-1, 0, 1)]
        out = [(wx + k, wz + fz) for k in (-1, 0, 1)]
    if shop:
        # The ground floor is glass along the door's wall, corners aside.
        for x in range(x0, x1):
            for z in range(z0, z1):
                on_wall = (x == wx) if fx else (z == wz)
                corner = x in (x0, x1 - 1) and z in (z0, z1 - 1)
                if on_wall and not corner:
                    blocks[x, y0, z] = B["shop"]
                    blocks[x, y0 + 1, z] = B["shop"]
    if door:
        blocks[wx, y0, wz] = B["door_bottom"]
        blocks[wx, y0 + 1, wz] = B["door_top"]
        awning = B[AWNINGS[int(rng.integers(0, len(AWNINGS)))]]
        for (ax, az) in out:
            if 0 <= ax < blocks.shape[0] and 0 <= az < blocks.shape[2] and blocks[ax, y0 + 2, az] == AIR:
                blocks[ax, y0 + 2, az] = awning
        if h > 4:
            sign = B[SIGNS[int(rng.integers(0, len(SIGNS)))]]
            for (sx, sz) in span:
                blocks[sx, y0 + 3, sz] = sign


def detail_box(props, tile, x0, y0, z0, x1, y1, z1):
    """Sub-block architectural detail, in the same coordinates as the land."""
    props.append(("box", tile, x0, y0, z0, x1, y1, z1))


def dress_building(props, x0, z0, x1, z1, h, style, facing, tower):
    """Deep cornices, window sills and roof profiles that catch real shadows."""
    base, roof = G + 1, G + 2 + h
    def box(tile, xa, ya, za, xb, yb, zb):
        detail_box(props, tile, xa, ya, za, xb, yb, zb)
    trim = "steel" if style == "glass" else "limestone"
    # A grounded base and horizontal courses wrap all four elevations.
    for y, thickness in ((base, 0.35), (base + 2.8, 0.18), (roof - 0.15, 0.3)):
        if tower and y > base + h * 0.55:
            continue
        box(trim, x0 - 0.12, y, z0 - 0.12, x1 + 0.12, y + thickness, z1 + 0.12)
    if style != "glass":
        for x in (x0, x1 - 0.22):
            for z in (z0, z1 - 0.22):
                box(trim, x - 0.06, base, z - 0.06, x + 0.28, roof, z + 0.28)
        for y in range(base + 3, roof - 1, STYLES[style]["rows"]):
            for x in range(x0 + 1, x1 - 1):
                if (x - x0) % (STYLES[style]["gap"] + 1):
                    for z in (z0 - 0.18, z1 - 0.03):
                        box(trim, x - 0.04, y, z, x + 1.04, y + 0.13, z + 0.21)
    # Low masonry buildings get stepped hipped roofs; taller ones keep
    # their usable terraces and roof equipment.
    if not tower and style != "glass" and h <= 13:
        for step in range(5):
            inset = step * 0.55
            box("copper", x0 - 0.28 + inset, roof + step * 0.38, z0 - 0.28 + inset,
                x1 + 0.28 - inset, roof + (step + 1) * 0.38, z1 + 0.28 - inset)
        box("brick", x0 + 0.7, roof + 0.7, z0 + 0.8, x0 + 1.35, roof + 2.5, z0 + 1.45)
    # Small iron balconies on the inward-facing upper floor.
    if not tower and style.startswith("plaster"):
        fx, fz = facing
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        # San Francisco's projecting bays: three glazed sides, deep sills,
        # painted spandrels and a small stepped cap. Facade-local u/v
        # keeps the same model on streets facing either axis.
        front_x = x1 if fx > 0 else x0 if fx < 0 else cx
        front_z = z1 if fz > 0 else z0 if fz < 0 else cz
        def facade(tile, u0, y0, v0, u1, y1, v1):
            points = [(front_x + fz * u + fx * v, front_z + fx * u + fz * v)
                      for u in (u0, u1) for v in (v0, v1)]
            box(tile, min(p[0] for p in points), y0, min(p[1] for p in points),
                max(p[0] for p in points), y1, max(p[1] for p in points))
        for by in range(base + 3, roof - 2, 3):
            facade(style, -1.15, by, 0, 1.15, by + 2.6, .68)
            facade("glass", -1, by + .35, .68, 1, by + 2.15, .72)
            for u in (-1.17, 1.13):
                facade("glass", u, by + .35, .12, u + .04, by + 2.15, .65)
            for u in (-1.14, -.38, .38, 1.1):
                facade("limestone", u, by + .2, .72, u + .08, by + 2.3, .8)
            for yy in (by + .15, by + 1.25, by + 2.25):
                facade("limestone", -1.24, yy, -.02, 1.24, yy + .12, .85)
        for step in range(3):
            facade("copper", -1.35 + step * .25, roof + step * .25, -.05,
                   1.35 - step * .25, roof + (step + 1) * .25, .95 - step * .2)
        if fx:
            xa, xb = (x1, x1 + 0.8) if fx > 0 else (x0 - 0.8, x0)
            za, zb = cz - 1.5, cz + 1.5
        else:
            xa, xb = cx - 1.5, cx + 1.5
            za, zb = (z1, z1 + 0.8) if fz > 0 else (z0 - 0.8, z0)
        y = base + 4
        box(trim, xa, y, za, xb, y + 0.16, zb)
        for x in np.linspace(xa, xb, 5):
            for z in (za, zb):
                box("dark", x, y + 0.16, z, x + 0.045, y + 0.95, z + 0.045)
        for z in np.linspace(za, zb, 7):
            for x in (xa, xb):
                box("dark", x, y + 0.16, z, x + 0.045, y + 0.95, z + 0.045)
        for z in (za, zb):
            box("dark", xa, y + 0.95, z, xb + 0.045, y + 1, z + 0.045)
        for x in (xa, xb):
            box("dark", x, y + 0.95, za, x + 0.045, y + 1, zb + 0.045)


def build_city(size, seed, plaza_r=13):
    """The blocks, and the props too thin to be blocks: lamp posts and
    masts, as (kind, x, y, z, height) with x/z the column they stand in."""
    rng = np.random.default_rng(seed)
    height = 48
    blocks = np.zeros((size, height, size), np.uint8)        # x, y, z
    props = []
    c = size // 2
    blocks[:, :G, :] = B["stone"]
    for x in range(size):
        for z in range(size):
            d = max(abs(x - c), abs(z - c))
            cx, cz = x % CELL, z % CELL
            if d < plaza_r:
                # A framed square and broad axial paths, not a carpet of
                # identical tiny tiles. All walking surfaces stay level.
                border = d in (5, 12) and min(abs(x - c), abs(z - c)) > 2
                blocks[x, G, z] = B["paving_border" if border else "plaza"]
            elif z < c - 28:
                blocks[x, G, z] = B["water"]
            elif cx < 4 and cz < 4:
                blocks[x, G, z] = B["asphalt"]
            elif cx < 4:
                if cz in (4, 11):
                    blocks[x, G, z] = B["crosswalk"]
                else:
                    blocks[x, G, z] = B["roadline"] if (cx == 2 and z % 2 == 0) else B["asphalt"]
            elif cz < 4:
                if cx in (4, 11):
                    blocks[x, G, z] = B["crosswalk"]
                else:
                    blocks[x, G, z] = B["roadline"] if (cz == 2 and x % 2 == 0) else B["asphalt"]
            else:
                blocks[x, G, z] = B["sidewalk"]
    # Buildings: one per lot, its footprint the lot less the pavement,
    # taller toward the middle, a few towers with setbacks.
    styles = list(STYLES)
    weights = np.array([.4, 1, 3, 2, 2, 2, 2, .8, .35]); weights /= weights.sum()
    lots = []
    for lx in range(0, size, CELL):
        for lz in range(0, size, CELL):
            x0, z0 = lx + 5, lz + 5
            x1, z1 = min(lx + 11, size), min(lz + 11, size)
            if x1 - x0 < 4 or z1 - z0 < 4:
                continue
            mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
            if mz < c - 25:
                continue  # the northern waterfront opens onto the bay
            if z0 < c - 16 and z1 > c - 24 and any(
                    x0 < c + dx + 7 and x1 > c + dx - 1 for dx, _, _ in PAINTED_LADIES):
                continue
            if max(abs(mx - c), abs(mz - c)) < plaza_r + 4:
                continue
            near = max(abs(mx - c), abs(mz - c)) / (size / 2)
            style = styles[int(rng.choice(len(styles), p=weights))]
            h = int(rng.integers(5, 10) + (1 - near) * rng.integers(4, 14))
            if style.startswith("plaster"):
                h = int(rng.choice((8, 11, 14)))
            tower = near < 0.55 and style == "glass" and rng.random() < 0.3
            if tower:
                style = "glass" if rng.random() < 0.5 else style
                h = int(rng.integers(16, 26))
            # The door faces the square: on the wall nearest the middle.
            dx, dz = c - mx, c - mz
            facing = (int(np.sign(dx)), 0) if abs(dx) > abs(dz) else (0, int(np.sign(dz)))
            lots.append((x0, z0, x1, z1, h, style, facing, tower))
    for x0, z0, x1, z1, h, style, facing, tower in lots:
        dress_building(props, x0, z0, x1, z1, h, style, facing, tower)
        shop = style != "glass" and rng.random() < 0.55
        if tower and h > 14:
            h1 = int(h * 0.55)
            build_tier(blocks, rng, x0, z0, x1, z1, G + 1, h1, style, facing, True, shop)
            build_tier(blocks, rng, x0 + 1, z0 + 1, x1 - 1, z1 - 1, G + 1 + h1 + 1, h - h1 - 1, style, facing, False, False)
            top = G + 1 + h
            # An aerial on the tallest.
            props.append(("mast", (x0 + x1) // 2, top + 1, (z0 + z1) // 2, int(rng.integers(3, 6))))
        else:
            build_tier(blocks, rng, x0, z0, x1, z1, G + 1, h, style, facing, True, shop)
            top = G + 1 + h
            r = rng.random()
            if style != "glass" and h <= 13:
                pass  # pitched roof and chimney supplied by dress_building
            elif r < 0.35:
                # A water tank on legs.
                tx, tz = x0 + 1, z0 + 1
                blocks[tx:tx + 2, top + 1, tz:tz + 2] = B["log"]
                blocks[tx:tx + 2, top + 2:top + 4, tz:tz + 2] = B["tank"]
            elif r < 0.65:
                # An air handler.
                blocks[x1 - 3:x1 - 1, top + 1, z1 - 3:z1 - 1] = B["vent"]
    # A waterfront row of Painted Ladies frames the clock from the entry.
    # These sit in the lots deliberately left open around the square.
    for dx, h, style in PAINTED_LADIES:
        xa, za = c + dx, c - 23
        blocks[xa:xa + 6, G + 1:, za:za + 6] = AIR
        build_tier(blocks, rng, xa, za, xa + 6, za + 6, G + 1, h, style, (0, 1), True, True)
        dress_building(props, xa, za, xa + 6, za + 6, h, style, (0, 1), False)
    # A lamp post at every corner, a street tree on a few lots.
    for lx in range(0, size, CELL):
        for lz in range(0, size, CELL):
            for (px, pz) in ((lx + 4, lz + 4), (lx + 11, lz + 11)):
                if px >= size or pz >= size or pz < c - 27 or max(abs(px - c), abs(pz - c)) < plaza_r + 2:
                    continue
                if blocks[px, G + 1, pz] != AIR:
                    continue
                props.append(("lamp", px, G + 1, pz, 3))
            tx, tz = (lx + 11, lz + 4) if rng.random() < 0.5 else (lx + 4, lz + 11)
            if tx < size and c - 27 <= tz < size and max(abs(tx - c), abs(tz - c)) >= plaza_r + 2 \
                    and rng.random() < 0.15 and blocks[tx, G + 1, tz] == AIR:
                blocks[tx, G, tz] = B["grass"]
                plant_tree(blocks, rng, tx, G + 1, tz)
    # The square: a fountain, a low workspace rail, lamps and trees.
    # A low reflecting basin leaves the working area and sightlines open.
    detail_box(props, "limestone", c - 1.4, G + 1, c - 1.4, c + 1.4, G + 1.22, c + 1.4)
    detail_box(props, "water", c - 1.18, G + 1.22, c - 1.18, c + 1.18, G + 1.25, c + 1.18)
    # A shallow curved rail, not a wall: open underneath and no empty bays.
    for x in np.arange(-8, 8, .25):
        props.append(("beam", "bronze", (c + x, G + 2.05, c - 4 + .04 * x * x),
                      (c + x + .25, G + 2.05, c - 4 + .04 * (x + .25) ** 2), .22))
    for x in (-8, -4, 0, 4, 8):
        z = c - 4 + .04 * x * x
        detail_box(props, "limestone", c + x - .22, G + 1, z - .22,
                   c + x + .22, G + 1.96, z + .22)
    # Small stepped water feature leaves the plaza's foreground clear.
    detail_box(props, "limestone", c - .32, G + 1.25, c - .32, c + .32, G + 1.65, c + .32)
    detail_box(props, "water", c - .18, G + 1.65, c - .18, c + .18, G + 1.9, c + .18)
    for sx, sz in ((-9, -9), (9, -9), (-9, 9), (9, 9)):
        props.append(("lamp", c + sx, G + 1, c + sz, 3))
    for sx, sz in ((-12, -12), (12, -12), (-12, 12), (12, 12)):
        for dx in range(-1, 2):
            for dz in range(-1, 2):
                blocks[c + sx + dx, G, c + sz + dz] = B["flowers"] if (dx or dz) else B["grass"]
        plant_tree(blocks, rng, c + sx, G + 1, c + sz)
    # Benches and low planted beds on the square's flanks, outside the
    # 7.5 m app-window ring and clear of the entrance and exit block.
    for sx in (-11, 11):
        for sz in (-5, 5):
            x, z, y = c + sx, c + sz, G + 1
            for dx in (-1, 1):
                detail_box(props, "dark", x + dx - .08, y, z - .25,
                           x + dx + .08, y + .48, z + .25)
            for dz in (-.24, -.06, .12):
                detail_box(props, "planks", x - 1.4, y + .45, z + dz,
                           x + 1.4, y + .55, z + dz + .14)
            detail_box(props, "planks", x - 1.4, y + .68, z - .32,
                       x + 1.4, y + 1.02, z - .20)
        for sz in (-9, 9):
            x, z = c + sx, c + sz
            detail_box(props, "limestone", x - 1.2, G + 1, z - 1.2,
                       x + 1.2, G + 1.45, z + 1.2)
            detail_box(props, "leaves", x - 1, G + 1.45, z - 1,
                       x + 1, G + 1.85, z + 1)
    # The clock tower: on the far side of the square from the door, in
    # the gap the windows keep clear, three blocks square and twelve
    # high — a stone footing with a door toward the square, sandstone
    # with a slit window or two, the clock's band near the top, a
    # cornice, a roof and a mast. The shell draws the faces (world.json
    # `clock`), one on each side of the band, a hair off the stone.
    tx0, tz0 = c - 1, c - CLOCK_Z - 1          # footprint x0..x0+2, z0..z0+2
    y0 = G + 1
    blocks[tx0:tx0 + 3, y0, tz0:tz0 + 3] = B["stone"]
    blocks[tx0:tx0 + 3, y0 + 1:y0 + 11, tz0:tz0 + 3] = B["sandstone"]
    blocks[c, y0, tz0 + 2] = B["door_bottom"]
    blocks[c, y0 + 1, tz0 + 2] = B["door_top"]
    for y in (y0 + 3, y0 + 5):
        blocks[c, y, tz0 + 2] = B["sandstone_window"]
        blocks[c, y, tz0] = B["sandstone_window"]
        blocks[tx0, y, tz0 + 1] = B["sandstone_window"]
        blocks[tx0 + 2, y, tz0 + 1] = B["sandstone_window"]
    blocks[tx0:tx0 + 3, y0 + 11, tz0:tz0 + 3] = B["cornice"]
    blocks[tx0:tx0 + 3, y0 + 12, tz0:tz0 + 3] = B["roof"]
    blocks[c, y0 + 13, tz0 + 1] = B["dark"]
    props.append(("mast", c, y0 + 14, tz0 + 1, 3))
    # Crown and corner pilasters frame the live clock faces without
    # changing their positions or covering the clock's band.
    for x in (tx0 - .12, tx0 + 2.9):
        for z in (tz0 - .12, tz0 + 2.9):
            detail_box(props, "limestone", x, y0, z, x + .22, y0 + 7, z + .22)
    for y in (y0 + 7, y0 + 10.9):
        detail_box(props, "limestone", tx0 - .22, y, tz0 - .22,
                   tx0 + 3.22, y + .2, tz0 + 3.22)
    for step in range(4):
        inset = step * .4
        detail_box(props, "copper", tx0 - .3 + inset, y0 + 13 + step * .4, tz0 - .3 + inset,
                   tx0 + 3.3 - inset, y0 + 13.4 + step * .4, tz0 + 3.3 - inset)
    # A Golden Gate-inspired silhouette across the bay. The roadway,
    # open portal towers, suspended main cables and vertical hangers are
    # real geometry, so it reads from any walking position.
    bz, deck = c - 66, G + 6
    detail_box(props, "water", c - 150, G - .2, c - 150, c + 150, G + .01, c - 28)
    def bridge(tile, xa, ya, za, xb, yb, zb):
        detail_box(props, tile, c + xa, ya, bz + za, c + xb, yb, bz + zb)
    bridge("asphalt", -46, deck, -1.7, 46, deck + .4, 1.7)
    for z in (-1.8, 1.65):
        bridge("bridge_red", -46, deck + .4, z, 46, deck + .8, z + .15)
    for x in (-20, 20):
        for z in (-2.2, 1.5):
            bridge("stone", x - 1.1, G, z - .35, x + 1.1, G + 2, z + 1.05)
            bridge("bridge_red", x - .6, G + 2, z, x + .6, deck + 20, z + .7)
        for y in (deck + 5, deck + 11, deck + 17, deck + 19):
            bridge("bridge_red", x - .6, y, -2.2, x + .6, y + .6, 2.2)
    def cable_y(x):
        return deck + 7 + 12 * (x / 20) ** 2 if abs(x) <= 20 else deck + 19 - (abs(x) - 20) * .57
    for x in np.arange(-45, 45, .5):
        for z in (-1.9, 1.9):
            props.append(("beam", "bridge_red",
                          (c + x, cable_y(x), bz + z),
                          (c + x + .5, cable_y(x + .5), bz + z), .16))
    for x in range(-44, 45, 2):
        for z in (-1.9, 1.9):
            bridge("bridge_red", x - .035, deck + .5, z - .035,
                   x + .035, cable_y(x), z + .035)
    # A short double-ended cable-car line behind the interaction rail.
    for z in (-7.48, -6.52):
        detail_box(props, "bronze", c - 14, G + 1.012, c + z,
                   c + 14, G + 1.035, c + z + .055)
    return blocks, props


# ------------------------------------------------------------ the mesh

FACES = [
    # (dx, dy, dz) neighbour, corners (4, CCW from outside), normal, which tile
    ((0, 1, 0), [(0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)], (0, 1, 0), 0),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], (0, -1, 0), 2),
    ((1, 0, 0), [(1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1)], (1, 0, 0), 1),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)], (-1, 0, 0), 1),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, 1), 1),
    ((0, 0, -1), [(1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)], (0, 0, -1), 1),
]


def shifted(a, d, fill):
    """`a` moved by -d, so out[x] = a[x + d]; `fill` past the edge."""
    out = np.full_like(a, fill)
    dx, dy, dz = d
    sx, sy, sz = a.shape
    src = (slice(max(dx, 0), sx + min(dx, 0)), slice(max(dy, 0), sy + min(dy, 0)), slice(max(dz, 0), sz + min(dz, 0)))
    dst = (slice(max(-dx, 0), sx + min(-dx, 0)), slice(max(-dy, 0), sy + min(-dy, 0)), slice(max(-dz, 0), sz + min(-dz, 0)))
    out[dst] = a[src]
    return out


def box_quads(x0, y0, z0, x1, y1, z1, tile, out):
    """An axis-aligned box's six faces, the tile stretched over each."""
    u0, v0, u1, v1 = tile_uv(tile)
    lo, hi = np.array([x0, y0, z0], np.float32), np.array([x1, y1, z1], np.float32)
    for _, corners, n, _ in FACES:
        quad = np.array([lo + (hi - lo) * np.array(cn, np.float32) for cn in corners], np.float32)
        out["pos"].append(quad)
        out["nrm"].append(np.tile(np.array(n, np.float32), (4, 1)))
        out["uv"].append(np.array([(u0, v1), (u1, v1), (u1, v0), (u0, v0)], np.float32))
        out["count"] += 1


def mesh_props(props, origin, out):
    """Lamp posts (a thin log with a glowing block on top) and masts."""
    ox, oz = origin
    for prop in props:
        if prop[0] == "beam":
            _, tile, start, end, width = prop
            start, end = np.array(start, dtype=float), np.array(end, dtype=float)
            axis = end - start
            axis /= np.linalg.norm(axis)
            side = np.cross(axis, (0, 1, 0) if abs(axis[2]) > .95 else (0, 0, 1))
            side /= np.linalg.norm(side)
            up = np.cross(axis, side)
            local = {"pos": [], "nrm": [], "uv": [], "count": 0}
            box_quads(0, -width / 2, -width / 2, np.linalg.norm(end - start),
                      width / 2, width / 2, T[tile], local)
            basis = np.column_stack((axis, side, up))
            shift = start + np.array([ox, 0, oz])
            out["pos"].extend([(p @ basis.T + shift).astype(np.float32) for p in local["pos"]])
            out["nrm"].extend([(n @ basis.T).astype(np.float32) for n in local["nrm"]])
            out["uv"].extend(local["uv"])
            out["count"] += local["count"]
            continue
        if prop[0] == "box":
            _, tile, x0, y0, z0, x1, y1, z1 = prop
            box_quads(x0 + ox, y0, z0 + oz, x1 + ox, y1, z1 + oz, T[tile], out)
            continue
        kind, x, y, z, h = prop
        cx, cz = x + ox + 0.5, z + oz + 0.5
        if kind == "lamp":
            box_quads(cx - 0.16, y, cz - 0.16, cx + 0.16, y + .3, cz + 0.16, T["dark"], out)
            box_quads(cx - 0.06, y, cz - 0.06, cx + 0.06, y + h, cz + 0.06, T["dark"], out)
            box_quads(cx - 0.25, y + h, cz - 0.25, cx + 0.25, y + h + 0.5, cz + 0.25, T["lamp"], out)
            box_quads(cx - .32, y + h + .5, cz - .32, cx + .32, y + h + .62, cz + .32, T["copper"], out)
        elif kind == "mast":
            box_quads(cx - 0.08, y, cz - 0.08, cx + 0.08, y + h, cz + 0.08, T["dark"], out)
            box_quads(cx - 0.3, y + h - 0.6, cz - 0.05, cx + 0.3, y + h - 0.5, cz + 0.05, T["dark"], out)


def mesh_blocks(blocks, origin, props=()):
    """Every block face with air (or, for the water's bed, water) beyond
    it, as quads — one pass of array arithmetic per face direction."""
    ox, oz = origin
    solid = np.isin(blocks, SOLID)
    pos, nrm, uv = [], [], []
    count = 0
    uvs = np.array([tile_uv(i) for i in range(ATLAS * ATLAS)], np.float32)   # u0 v0 u1 v1
    for d, corners, n, which in FACES:
        nb = shifted(blocks, d, AIR)
        nsolid = shifted(solid, d, False)
        visible = np.where(blocks == WATER, nb == AIR, (blocks != AIR) & ~nsolid)
        cells = np.argwhere(visible)
        if not len(cells):
            continue
        tiles = FACE_TILES[blocks[visible], which]
        u0, v0, u1, v1 = uvs[tiles].T
        base = cells.astype(np.float32) + np.array([ox, 0, oz], np.float32)
        quad = np.stack([base + np.array(cn, np.float32) for cn in corners], axis=1)   # (n, 4, 3)
        pos.append(quad.reshape(-1, 3))
        nrm.append(np.tile(np.array(n, np.float32), (len(cells) * 4, 1)))
        # v runs down the image in glTF (top-left origin).
        uv.append(np.stack([np.stack([u0, v1], 1), np.stack([u1, v1], 1),
                            np.stack([u1, v0], 1), np.stack([u0, v0], 1)], axis=1).reshape(-1, 2))
        count += len(cells)
    extra = {"pos": [], "nrm": [], "uv": [], "count": 0}
    mesh_props(props, origin, extra)
    if extra["count"]:
        pos.append(np.concatenate(extra["pos"])); nrm.append(np.concatenate(extra["nrm"]))
        uv.append(np.concatenate(extra["uv"])); count += extra["count"]
    pos = np.concatenate(pos); nrm = np.concatenate(nrm); uv = np.concatenate(uv).astype(np.float32)
    b = np.arange(count, dtype=np.uint32)[:, None] * 4
    idx = (b + np.array([0, 1, 2, 0, 2, 3], np.uint32)).reshape(-1)
    return pos, nrm, uv, idx


def ambient_actors():
    """Local-space meshes and closed glTF translation tracks (seconds).

    No actor crosses the app plane: clouds stay over the bay, the ferry
    below the bridge, and the double-ended trolley on its plaza track.
    """
    actors = []
    def actor(name, boxes, times, positions):
        out = {"pos": [], "nrm": [], "uv": [], "count": 0}
        for tile, bounds in boxes:
            box_quads(*bounds, T[tile], out)
        p = np.concatenate(out["pos"]).astype(np.float32)
        n = np.concatenate(out["nrm"]).astype(np.float32)
        u = np.concatenate(out["uv"]).astype(np.float32)
        b = np.arange(out["count"], dtype=np.uint32)[:, None] * 4
        indices = (b + np.array([0, 1, 2, 0, 2, 3], np.uint32)).reshape(-1)
        actors.append((name, (p, n, u, indices), times, positions))

    for i in range(5):
        times = np.linspace(0, 240, 121)
        a = times / 240 * 2 * np.pi + i * 2 * np.pi / 5
        positions = np.column_stack((65 * np.sin(a),
            np.full_like(a, 24 + (i % 3) * 4), -83 + 12 * np.cos(a)))
        # Layered cream voxel clouds, no transparency sorting or billboards.
        cloud_boxes = []
        for k in range(9):
            x = -6+k*1.4
            crown = 1.0+1.3*np.sin((k+.5)/9*np.pi)
            cloud_boxes.append(("cloud",(x,.18*np.sin(k*2+i),-1.3,
                                          x+2.1,crown,1.2)))
        actor(f"cloud-{i}", cloud_boxes, times, positions)

    times = np.linspace(0, 150, 301)
    a = times / 150 * 2 * np.pi
    positions = np.column_stack((32 * np.sin(a),
        -2.25 + .10 * np.sin(a * 24), -79 + 5 * np.cos(a)))
    actor("bay-ferry", [
        ("bridge_red", (-4.2, 0, -1.3, 4.2, .65, 1.3)),
        ("limestone", (-3.7, .65, -1.25, 3.7, .95, 1.25)),
        ("plaster_cream", (-2.6, .95, -.95, 2.6, 2.3, .95)),
        ("glass_lit", (-2.4, 1.35, .96, 2.4, 2.05, .99)),
        ("glass_lit", (-2.4, 1.35, -.99, 2.4, 2.05, -.96)),
        ("limestone", (-2.9, 2.3, -1.1, 2.9, 2.5, 1.1)),
        ("bridge_red", (-.4, 2.5, -.4, .4, 3.2, .4)),
    ], times, positions)

    boxes = [
        ("dark", (-1.8, .15, -.7, 1.8, .45, .7)),
        ("bridge_red", (-1.9, .45, -.75, 1.9, 1.1, .75)),
        ("plaster_cream", (-1.8, 1.1, -.72, 1.8, 2.35, .72)),
        ("copper", (-2.05, 2.35, -.9, 2.05, 2.55, .9)),
        ("bronze", (-.04, 2.55, -.04, .04, 3.3, .04)),
    ]
    for x in (-1.3, -.45, .4, 1.25):
        for z in (-.735, .72):
            boxes.append(("glass_lit", (x - .31, 1.3, z, x + .31, 2.15, z + .015)))
    for x in (-1.25, 1.25):
        for z in (-.78, .55):
            boxes.append(("dark", (x - .26, 0, z, x + .26, .52, z + .23)))
    # Rotate the double-ended car to run down the sloping street (-Z).
    boxes = [(tile, (-b[5], b[1], b[0], -b[2], b[4], b[3])) for tile,b in boxes]
    boxes.append(("lamp", (-.22,.85,1.91,.22,1.25,1.94)))
    for z in (-1.82,1.80):
        for x in (-.61,.08):
            boxes.append(("glass_lit", (x,1.30,z,x+.53,2.12,z+.02)))
    def car(z):
        return [-4, 5+(z+8)*.19+.06, z]
    actor("plaza-cable-car", boxes, [0, 6, 36, 44, 74, 80],
          [car(-12),car(-12),car(-37),car(-37),car(-12),car(-12)])
    return actors


def write_glb(path, pos, nrm, uv, idx, atlas_path):
    with open(atlas_path, "rb") as f:
        png = f.read()
    bin_ = bytearray()
    views = []

    def view(data, target=None):
        while len(bin_) % 4:
            bin_.append(0)
        off = len(bin_)
        bin_.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    accessors = [
        {"bufferView": view(pos.tobytes(), 34962), "componentType": 5126, "count": len(pos), "type": "VEC3",
         "min": [float(v) for v in pos.min(axis=0)], "max": [float(v) for v in pos.max(axis=0)]},
        {"bufferView": view(nrm.tobytes(), 34962), "componentType": 5126, "count": len(nrm), "type": "VEC3"},
        {"bufferView": view(uv.tobytes(), 34962), "componentType": 5126, "count": len(uv), "type": "VEC2"},
        {"bufferView": view(idx.tobytes(), 34963), "componentType": 5125, "count": len(idx), "type": "SCALAR"},
    ]
    img_view = view(png)
    # Only glass and lantern texels emit; the masonry remains physically lit.
    emissive = np.zeros((ATLAS*TILE, ATLAS*TILE,3),np.uint8)
    tiles = make_tiles()
    for name in ("lamp", "window_lit", "glass_lit"):
        row,col = divmod(T[name],ATLAS)
        tile = tiles[name]
        mask = np.ones((TILE,TILE),bool) if name == "lamp" else (
            (tile[:,:,0]>.85) & (tile[:,:,1]>.7) & (tile[:,:,2]<.8))
        emissive[row*TILE:(row+1)*TILE,col*TILE:(col+1)*TILE][mask] = (255,166,74)
    # Restrained distance haze and water glints: these surfaces must not
    # disappear into black just because the moon is behind them.
    for name,color in (("hill",(9,15,24)),("hill_far",(16,24,36)),
                       ("water_glint",(19,30,43)),("reflection_amber",(69,39,17))):
        row,col = divmod(T[name],ATLAS)
        emissive[row*TILE:(row+1)*TILE,col*TILE:(col+1)*TILE] = color
    encoded = io.BytesIO()
    Image.fromarray(emissive).save(encoded,format="PNG")
    emission_view = view(encoded.getvalue())
    j = {
        "asset": {"version": "2.0", "generator": "starling voxel-world.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "land"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                                    "indices": 3, "material": 0, "mode": 4}]}],
        # NEAREST both ways: the pixels are the point.
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"bufferView": img_view, "mimeType": "image/png"},
                   {"bufferView": emission_view, "mimeType": "image/png"}],
        "textures": [{"sampler": 0, "source": 0}, {"sampler": 0, "source": 1}],
        "extensionsUsed": ["KHR_materials_emissive_strength", "KHR_lights_punctual"],
        "materials": [{"name": "blocks", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": .85},
            "emissiveTexture": {"index": 1}, "emissiveFactor": [1,1,1],
            "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": .55}}}],
        "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}],
    }
    def accessor(data, kind, component=5126, target=None):
        data = np.asarray(data, dtype=np.uint32 if component == 5125 else np.float32)
        item = {"bufferView": view(data.tobytes(), target), "componentType": component,
                "count": len(data), "type": kind}
        if kind in ("SCALAR", "VEC3"):
            item["min"] = np.atleast_1d(data.min(axis=0)).tolist()
            item["max"] = np.atleast_1d(data.max(axis=0)).tolist()
        accessors.append(item)
        return len(accessors) - 1

    # Actual pools of lamplight, limited to six lights near the viewing terrace.
    lights = []
    for row,z in enumerate((2, -10, -22)):
        east_lamp = max(14+row*1.4,(13-z)*1.32+8)-5
        for x in (-7.8, east_lamp):
            lights.append({"type": "point", "color": [1.0,.57,.25],
                           "intensity": 550, "range": 11})
            node = len(j["nodes"])
            j["nodes"].append({"name": "street-lantern", "translation":
                [x,max(-2.2,5+min(0,z+8)*.19)+3.2,z+.5],
                "extensions": {"KHR_lights_punctual": {"light": len(lights)-1}}})
            j["scenes"][0]["nodes"].append(node)
    j["extensions"] = {"KHR_lights_punctual": {"lights": lights}}
    j["animations"] = []
    for name, (p, n, u, indices), times, positions in ambient_actors():
        mesh = len(j["meshes"])
        j["meshes"].append({"primitives": [{"attributes": {
            "POSITION": accessor(p, "VEC3", target=34962),
            "NORMAL": accessor(n, "VEC3", target=34962),
            "TEXCOORD_0": accessor(u, "VEC2", target=34962)},
            "indices": accessor(indices, "SCALAR", 5125, 34963), "material": 0}]})
        node = len(j["nodes"])
        j["nodes"].append({"name": name, "mesh": mesh,
                           "translation": np.asarray(positions[0]).tolist()})
        if name == "plaza-cable-car":
            angle = -np.arctan(.19)/2
            j["nodes"][-1]["rotation"] = [float(np.sin(angle)),0,0,float(np.cos(angle))]
        j["scenes"][0]["nodes"].append(node)
        j["animations"].append({"name": name, "samplers": [{
            "input": accessor(times, "SCALAR"), "output": accessor(positions, "VEC3"),
            "interpolation": "LINEAR"}],
            "channels": [{"sampler": 0, "target": {"node": node, "path": "translation"}}]})
    j["buffers"][0]["byteLength"] = len(bin_)
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(bin_) % 4:
        bin_.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(bin_), 0x004E4942)); f.write(bin_)


# ------------------------------------------------------------- the sky

def write_hdr(path, img):
    h, w, _ = img.shape
    m = img.max(axis=2)
    f, e = np.frexp(m)
    live = m > 1e-32
    scale = np.where(live, f * 256.0 / np.maximum(m, 1e-32), 0.0)
    rgbe = np.zeros((h, w, 4), np.uint8)
    rgbe[..., :3] = np.clip(img * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(live, e + 128, 0).astype(np.uint8)
    first = rgbe[:, 0, :]
    both = (first[:, 0] == 2) & (first[:, 1] == 2)
    rgbe[both, 0, 0] = 3
    with open(path, "wb") as fo:
        fo.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        fo.write(f"-Y {h} +X {w}\n".encode())
        fo.write(rgbe.tobytes())


def sky(w=1024, h=512, sun_dir=(0.55, 0.75, 0.45), with_sun=True):
    """Early-evening sky: blue overhead, peach at the horizon and warm
    ground bounce below. Directions in
    cmgen's convention: u = (atan2(x, z) / pi + 1) / 2, v down from +y."""
    v = (np.arange(h) + 0.5) / h
    u = (np.arange(w) + 0.5) / w
    lat = (0.5 - v) * np.pi
    phi = (u * 2 - 1) * np.pi
    img = np.zeros((h, w, 3), np.float32)
    up = np.clip(np.sin(lat), 0, 1)[:, None]
    zenith = np.array([0.07, 0.18, 0.36]); horizon = np.array([0.48, 0.22, 0.12])
    skyc = horizon[None, None, :] * (1 - up[..., None] ** 0.35) + zenith[None, None, :] * up[..., None] ** 0.35
    ground = np.array([0.095, 0.075, 0.065])
    below = (lat < 0)[:, None, None]
    img = np.where(below, ground[None, None, :] * 0.9, skyc * 1.2)
    img = np.broadcast_to(img, (h, w, 3)).copy()
    if with_sun:
        # A low warm sun; no stars in the early-evening sky.
        sd = np.array(sun_dir) / np.linalg.norm(sun_dir)
        dx = np.cos(lat)[:, None] * np.sin(phi)[None, :]
        dy = np.sin(lat)[:, None] * np.ones_like(phi)[None, :]
        dz = np.cos(lat)[:, None] * np.cos(phi)[None, :]
        dirs = np.stack([dx, dy, dz], -1)
        # A square: the max of the two tangent-plane offsets.
        t1 = np.cross(sd, [0, 1, 0]); t1 /= np.linalg.norm(t1)
        t2 = np.cross(sd, t1)
        a = np.abs(dirs @ t1); b = np.abs(dirs @ t2)
        front = dirs @ sd > 0
        sun = front & (a*a+b*b < 0.019**2)
        img[sun] = (2.5, 1.5, .65)
    return img.astype(np.float32)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "shell", "Resources", "Worlds", "city"),
                    help="the world directory (default: the shipped city in shell/Resources/Worlds)")
    ap.add_argument("--size", type=int, default=96)
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--cmgen", default=os.path.expanduser("~/dev/filament/gles/bin/cmgen"))
    ap.add_argument("--no-sky", action="store_true", help="keep the sky already there (faster)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    atlas = os.path.join(a.out, "atlas.png")
    make_atlas(atlas, os.path.join(a.out, "frame.png"), a.seed)
    spec = importlib.util.spec_from_file_location("city_night", os.path.join(HERE,"city-night.py"))
    city_night = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(city_night)
    blocks, props = city_night.build(sys.modules[__name__], a.size, a.seed)
    origin = (-a.size // 2, -a.size // 2)          # the square at x = z = 0
    pos, nrm, uv, idx = mesh_blocks(blocks, origin, props)
    write_glb(os.path.join(a.out, "room.glb"), pos, nrm, uv, idx, atlas)
    plaza_h = G
    print(f"  {a.size}x{a.size} columns, ground at y={G}, {len(idx)//3} triangles")

    sun_dir = (-0.6, 0.28, 0.75)
    if not a.no_sky:
        # Separate sky brightness from the ambient-light bake: readable
        # readable architecture and a restrained sunset background.
        write_hdr(os.path.join(a.out, "sky-full.hdr"), sky(sun_dir=sun_dir, with_sun=True)*.22)
        write_hdr(os.path.join(a.out, "sky-nosun.hdr"), sky(sun_dir=sun_dir, with_sun=False))
        for sub, src, size in (("ibl", "sky-nosun.hdr", 64), ("sky", "sky-full.hdr", 512)):
            subprocess.run([a.cmgen, "--quiet", "--format=ktx", f"--size={size}",
                            f"--deploy={os.path.join(a.out, sub)}", os.path.join(a.out, src)], check=True)
        os.replace(os.path.join(a.out, "ibl", "ibl_ibl.ktx"), os.path.join(a.out, "room_ibl.ktx"))
        os.replace(os.path.join(a.out, "sky", "sky_skybox.ktx"), os.path.join(a.out, "room_skybox.ktx"))

    # Where feet go: the ground is level, and buildings are not climbed.
    surface = np.array([[city_night.ground(z-a.size//2) for z in range(a.size)]
                        for x in range(a.size)],float)
    world = {
        "kind": "voxel",
        "ambient_animation": True,
        "exposure": [8.0, 1.0 / 60.0, 100.0],
        "ibl_intensity": 24000.0,
        "sun": {"dir": list(sun_dir), "colour": [1.0, 0.72, 0.46], "lux": 6500.0},
        "hub": [0.0, float(plaza_h + 1), 0.0],
        "eye_height": 1.62,
        "ring_radius": 7.5,
        "heightmap": {"origin": [origin[0], origin[1]], "size": [a.size, a.size],
                      "heights": surface.reshape(-1).tolist()},   # [x][z] order
        "camera_home": {"radius": 13.0, "height": 3.5, "dolly": 6.0},
        # The windows' frames use a fine bronze tile,
        # one per `block` metres, a `margin` wide and `depth` deep.
        "pane_frame": {"texture": "frame.png", "block": 0.18, "margin": 0.012, "depth": 0.025},
        # Running-app previews share the low rail's center and curvature.
        "workspaceRail": workspace_rail(),
        # The clock tower's band: the shell hangs a face on each side,
        # `half` from the centre, `size` metres square.
        "clock": {"x": 10.0, "y": 11.5, "z": -49.0,
                  "half": 1.5, "size": 2.6},
    }
    with open(os.path.join(a.out, "world.json"), "w") as f:
        json.dump(world, f)
    for n in ("room.glb", "room_ibl.ktx", "room_skybox.ktx", "world.json", "atlas.png", "frame.png"):
        print(f"  {n:18s} {os.path.getsize(os.path.join(a.out, n))/1e6:6.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
