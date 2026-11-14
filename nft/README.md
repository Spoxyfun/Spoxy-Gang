# SpoxyFun NFT files — 2,222 tokens

Generated from 39 characters in the original gang-banner style
(`base/`): the original 7 from the web artwork (Boo, Cool, Sleepy, Cap,
Shock, Starry, and the rare Mascot — 62 in this build, capped at 111)
plus 32 from four 3×3 character sheets — hats, moods, items, and
costumes — all drawn as TALL ghosts with lash eyes. An earlier round
of 36 round/chibi characters was rejected by the user and moved to
`base/_rejected/`. Every token is a distinct combination of
character × colorway (10) × mirror × frame (6) × zoom × finish —
2,222 unique images, verified by SHA-256 hash.

## Contents

- `images/1.webp` … `images/2222.webp` — 768×768 WebP artwork
- `metadata/1.json` … `metadata/2222.json` — ERC-721 metadata (name,
  description, image, 7 traits incl. Rarity)
- `manifest.csv` — id, sha256, and traits for every token
- `generate.py` — deterministic generator (seed 2222); re-running it
  rebuilds the exact same collection
- `base/` — the 7 base character portraits cut from the web artwork

## Going live (hosting)

1. Upload the `images/` and `metadata/` folders to any static hosting,
   keeping the folder names, e.g. under `https://HOST/spoxyfun/`.
2. In every metadata file, replace the placeholder with the real root:
   `sed -i 's|__SPOXYFUN_BASE_URL__|https://HOST/spoxyfun|g' metadata/*.json`
3. Set the contract base URI to the metadata folder, with a trailing
   slash: `https://HOST/spoxyfun/metadata/` — via the deploy page
   (`spoxyfun-deploy.html`, step 03, Set Base URI). tokenURI then
   returns `…/metadata/<id>.json` for each token.

Until the base URI is set, the contract's `tokenURI` returns an empty
string — set it before opening mint.

## Rarity (visible in the art)

- Legendary (80): Gold Frame + Golden/Midnight colorway
- Epic (371): Gold Frame, or Halo + Golden/Midnight
- Rare (775): Stars or Dots frame
- Common (996): everything else

Token #1 is the Mascot in its original web look with a Gold Frame.
