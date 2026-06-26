#!/usr/bin/env python3
"""Generate Read the Docs favicons with a light cream background.

The packaged desktop app keeps the default logo icon; RTD uses these files
under ``docs/_static/`` only (see ``docs/conf.py`` ``html_favicon``).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "icons" / "logosimple" / "logosimple-256.png"
OUT_DIR = ROOT / "docs" / "_static"
# Warm off-white ("panna") — distinct from the app's dark-framed icon.
BACKGROUND = "#FAF6F0"
ICO_SIZES = (16, 32, 48)


def _render(size: int) -> Image.Image:
    logo = Image.open(SOURCE).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), BACKGROUND)
    pad = max(2, size // 14)
    inner = size - 2 * pad
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    return canvas.convert("RGB")


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Logo not found: {SOURCE}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    icons = [_render(size) for size in ICO_SIZES]
    icons[0].save(
        OUT_DIR / "favicon.ico",
        format="ICO",
        sizes=[(size, size) for size in ICO_SIZES],
        append_images=icons[1:],
    )
    _render(32).save(OUT_DIR / "favicon-32.png", format="PNG")
    print(f"Wrote {OUT_DIR / 'favicon.ico'} and {OUT_DIR / 'favicon-32.png'}")


if __name__ == "__main__":
    main()
