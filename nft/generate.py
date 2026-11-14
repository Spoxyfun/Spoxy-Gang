#!/usr/bin/env python3
"""SpoxyFun NFT collection generator.

Builds 2,222 unique NFT images + metadata from 39 characters in the
original banner style (base/*.webp): the original 7 from the web
artwork plus 32 from four 3x3 character sheets (hats, moods, items,
costumes) drawn as TALL ghosts with lash eyes, matching the gang
banner. An earlier round of 36 round/chibi characters was REJECTED by
the user ("masih jelek") and moved to base/_rejected/ - never use them.
Every token is a distinct combination of
character x colorway x flip x frame x zoom x finish, so the minted NFT
looks like the art on the web - same characters, many styles.

Deterministic: same seed -> same collection. Re-run to rebuild.

Output:
  images/1.webp .. images/2222.webp   (768x768 WebP)
  metadata/1.json .. metadata/2222.json
  manifest.csv                        (id, sha256, traits)

Before hosting, replace __SPOXYFUN_BASE_URL__ in metadata/*.json with
the real hosting root (one sed command, see README.md).
"""
import csv
import hashlib
import itertools
import json
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageEnhance

ROOT = pathlib.Path(__file__).resolve().parent
BASE = ROOT / "base"
IMG_DIR = ROOT / "images"
META_DIR = ROOT / "metadata"
SIZE = 768
SUPPLY = 2222
SEED = 2222
BASE_URL = "__SPOXYFUN_BASE_URL__"

CHARACTERS = {
    # Original 7 from the web artwork
    "boo":    {"name": "Boo",     "mood": "Mischievous"},
    "cool":   {"name": "Cool",    "mood": "Cool"},
    "sleepy": {"name": "Sleepy",  "mood": "Sleepy"},
    "cap":    {"name": "Cap",     "mood": "Chill"},
    "shock":  {"name": "Shock",   "mood": "Shocked"},
    "starry": {"name": "Starry",  "mood": "Starstruck"},
    "mascot": {"name": "Mascot",  "mood": "Waving"},
    # Sheet H: hats (tall banner style)
    "h1": {"name": "Wizard", "mood": "Magical"},
    "h2": {"name": "Crown",  "mood": "Royal"},
    "h3": {"name": "Bloom",  "mood": "Sweet"},
    "h4": {"name": "DJ",     "mood": "Groovy"},
    "h5": {"name": "Halo",   "mood": "Angelic"},
    "h6": {"name": "Pirate", "mood": "Bold"},
    "h7": {"name": "Tophat", "mood": "Dapper"},
    "h8": {"name": "Sunny",  "mood": "Cheerful"},
    "h9": {"name": "Viking", "mood": "Brave"},
    # Sheet M: moods (tall banner style)
    "m1": {"name": "Joy",     "mood": "Joyful"},
    "m2": {"name": "Wink",    "mood": "Playful"},
    "m3": {"name": "Grumpy",  "mood": "Grumpy"},
    "m4": {"name": "Lovely",  "mood": "In Love"},
    "m5": {"name": "Yawn",    "mood": "Sleepy"},
    "m6": {"name": "Nervous", "mood": "Nervous"},
    "m7": {"name": "Smirk",   "mood": "Cool"},
    "m8": {"name": "Curious", "mood": "Curious"},
    "m9": {"name": "Tears",   "mood": "Overjoyed"},
    # Sheet I: items (tall banner style)
    "i1": {"name": "Lolly",   "mood": "Sweet"},
    "i2": {"name": "Wand",    "mood": "Magical"},
    "i3": {"name": "Balloon", "mood": "Floaty"},
    "i4": {"name": "Booky",   "mood": "Bookish"},
    "i5": {"name": "Strum",   "mood": "Musical"},
    "i6": {"name": "Scoop",   "mood": "Sweet"},
    "i7": {"name": "Shroom",  "mood": "Curious"},
    "i8": {"name": "Lantern", "mood": "Spooky"},
    "i9": {"name": "Boba",    "mood": "Sweet"},
    # Sheet K: costumes (only the 5 tall on-style cuts kept)
    "k1": {"name": "Hero",   "mood": "Brave"},
    "k3": {"name": "Merlin", "mood": "Wise"},
    "k5": {"name": "Berry",  "mood": "Sweet"},
    "k7": {"name": "Sailor", "mood": "Breezy"},
    "k8": {"name": "Chef",   "mood": "Tasty"},
}
# hue shift in degrees -> colorway name
COLORWAYS = [
    (0, "Original"), (25, "Sunset"), (-25, "Ocean"), (50, "Citrus"),
    (-50, "Berry"), (80, "Mint"), (120, "Rose"), (180, "Midnight"),
    (200, "Ember"), (300, "Golden"),
]
FRAMES = ["None", "Stars", "Dots", "Gold Frame", "Lime Frame", "Halo"]
ZOOMS = [1.0, 1.08, 1.16]
FINISHES = ["Matte", "Gloss"]
MASCOT_CAP = 111  # mascot stays the rare logo character


def hue_shift(im: Image.Image, degrees: int) -> Image.Image:
    if degrees == 0:
        return im
    shift = round(degrees / 360 * 255) % 256
    hsv = im.convert("HSV")
    h, s, v = hsv.split()
    lut = [(i + shift) % 256 for i in range(256)]
    h = h.point(lut)
    return Image.merge("HSV", (h, s, v)).convert("RGB")


def _star(draw, cx, cy, r, fill):
    pts = []
    for i in range(8):
        ang = math.pi / 2 + i * math.pi / 4
        rad = r if i % 2 == 0 else r * 0.38
        pts.append((cx + rad * math.cos(ang), cy - rad * math.sin(ang)))
    draw.polygon(pts, fill=fill)


def apply_frame(im: Image.Image, frame: str, rng: random.Random) -> Image.Image:
    if frame == "None":
        return im
    im = im.convert("RGBA")
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    if frame == "Stars":
        for _ in range(14):
            x = rng.randint(30, SIZE - 30)
            y = rng.randint(30, SIZE - 30)
            _star(d, x, y, rng.randint(8, 20),
                  (255, 255, 255, 235) if rng.random() < 0.5 else (255, 215, 0, 235))
    elif frame == "Dots":
        palette = [(255, 107, 157, 230), (163, 230, 53, 230),
                   (255, 255, 255, 230), (255, 167, 38, 230)]
        for _ in range(22):
            x = rng.randint(20, SIZE - 20)
            y = rng.randint(20, SIZE - 20)
            r = rng.randint(5, 13)
            d.ellipse([x - r, y - r, x + r, y + r], fill=rng.choice(palette))
    elif frame == "Gold Frame":
        d.rectangle([10, 10, SIZE - 10, SIZE - 10], outline=(212, 175, 55, 255), width=14)
        d.rectangle([30, 30, SIZE - 30, SIZE - 30], outline=(255, 215, 0, 255), width=5)
    elif frame == "Lime Frame":
        d.rectangle([10, 10, SIZE - 10, SIZE - 10], outline=(163, 230, 53, 255), width=14)
        for cx, cy in [(52, 52), (SIZE - 52, 52), (52, SIZE - 52), (SIZE - 52, SIZE - 52)]:
            _star(d, cx, cy, 22, (163, 230, 53, 255))
    elif frame == "Halo":
        cx = cy = SIZE // 2
        for r, a in [(330, 26), (300, 34), (270, 42)]:
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 240, 180, a))
    im = Image.alpha_composite(im, overlay).convert("RGB")
    return im


def rarity_of(frame: str, colorway: str) -> str:
    rare_hues = {"Golden", "Midnight"}
    if frame == "Gold Frame" and colorway in rare_hues:
        return "Legendary"
    if frame == "Gold Frame" or (frame == "Halo" and colorway in rare_hues):
        return "Epic"
    if frame in ("Stars", "Dots"):
        return "Rare"
    return "Common"


def build_combos():
    combos = list(itertools.product(
        CHARACTERS.keys(), COLORWAYS, [False, True], FRAMES, ZOOMS, FINISHES))
    rng = random.Random(SEED)
    rng.shuffle(combos)
    picked = []
    mascot_seen = 0
    # ID 1 is fixed: the Mascot in its original web look, gold framed.
    first = ("mascot", (0, "Original"), False, "Gold Frame", 1.0, "Matte")
    picked.append(first)
    mascot_seen = 1
    for c in combos:
        if len(picked) >= SUPPLY:
            break
        if c == first:
            continue
        if c[0] == "mascot":
            if mascot_seen >= MASCOT_CAP:
                continue
            mascot_seen += 1
        picked.append(c)
    assert len(picked) == SUPPLY, len(picked)
    assert len(set(picked)) == SUPPLY, "duplicate combos"
    return picked


def render(combo, token_id):
    char, (deg, colorway), flip, frame, zoom, finish = combo
    im = Image.open(BASE / f"{char}.webp").convert("RGB")
    if zoom != 1.0:
        side = int(SIZE / zoom)
        off = (SIZE - side) // 2
        im = im.crop((off, off, off + side, off + side)).resize((SIZE, SIZE), Image.LANCZOS)
    im = hue_shift(im, deg)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    rng = random.Random(f"spoxyfun-{token_id}")
    im = apply_frame(im, frame, rng)
    if finish == "Gloss":
        im = ImageEnhance.Color(im).enhance(1.15)
        im = ImageEnhance.Sharpness(im).enhance(1.2)
    return im


def main():
    IMG_DIR.mkdir(exist_ok=True)
    META_DIR.mkdir(exist_ok=True)
    combos = build_combos()
    rows = []
    for token_id, combo in enumerate(combos, start=1):
        char, (_, colorway), flip, frame, zoom, finish = combo
        im = render(combo, token_id)
        img_path = IMG_DIR / f"{token_id}.webp"
        im.save(img_path, "WEBP", quality=80)
        sha = hashlib.sha256(img_path.read_bytes()).hexdigest()
        meta = {
            "name": f"SpoxyFun #{token_id}",
            "description": "A cute little ghost from the SpoxyFun gang - spooky fun, never scary. One of 2,222 unique ghosts on BNB Chain.",
            "image": f"{BASE_URL}/images/{token_id}.webp",
            "attributes": [
                {"trait_type": "Character", "value": CHARACTERS[char]["name"]},
                {"trait_type": "Mood", "value": CHARACTERS[char]["mood"]},
                {"trait_type": "Colorway", "value": colorway},
                {"trait_type": "Frame", "value": frame},
                {"trait_type": "Mirrored", "value": "Yes" if flip else "No"},
                {"trait_type": "Finish", "value": finish},
                {"trait_type": "Rarity", "value": rarity_of(frame, colorway)},
            ],
        }
        (META_DIR / f"{token_id}.json").write_text(json.dumps(meta, indent=2))
        rows.append([token_id, sha, CHARACTERS[char]["name"], colorway,
                     frame, "Yes" if flip else "No", zoom, finish,
                     rarity_of(frame, colorway)])
        if token_id % 500 == 0:
            print(f"{token_id} done")
    with open(ROOT / "manifest.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "sha256", "character", "colorway", "frame",
                    "mirrored", "zoom", "finish", "rarity"])
        w.writerows(rows)
    print(f"built {len(rows)} tokens")


if __name__ == "__main__":
    main()
