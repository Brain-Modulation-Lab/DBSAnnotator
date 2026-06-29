#!/usr/bin/env python3
"""Generate Read the Docs branding assets with an opaque light background.

Outputs under ``docs/_static/``:

* ``favicon-16.png``, ``favicon-32.png``, ``favicon-48.png`` — RGB PNG tab icons
* ``favicon.ico`` — multi-size fallback (24-bit BMP entries, no alpha)
* ``logo_docs.png`` — landing-page logo (same background as favicons)

The packaged desktop app keeps the default transparent icon; these files are
docs-only (see ``docs/conf.py`` ``html_favicon`` and ``docs/index.rst``).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "icons" / "logosimple" / "logosimple-256.png"
OUT_DIR = ROOT / "docs" / "_static"
# Opaque white — visible on browser tabs and the RTD light content panel.
BACKGROUND = "#FFFFFF"
FAVICON_SIZES = (16, 32, 48)
LOGO_DOCS_SIZE = 256


def _render(size: int) -> Image.Image:
    logo = Image.open(SOURCE).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), BACKGROUND)
    pad = max(2, size // 14)
    inner = size - 2 * pad
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    # RGB only — no alpha channel in shipped assets.
    return canvas.convert("RGB")


def _write_png(path: Path, size: int) -> None:
    _render(size).save(path, format="PNG", optimize=True)


def _write_ico(path: Path) -> None:
    images = [_render(size) for size in FAVICON_SIZES]
    images[0].save(
        path,
        format="ICO",
        sizes=[(size, size) for size in FAVICON_SIZES],
        append_images=images[1:],
        bitmap_format="bmp",
    )


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Logo not found: {SOURCE}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for size in FAVICON_SIZES:
        _write_png(OUT_DIR / f"favicon-{size}.png", size)
    _write_ico(OUT_DIR / "favicon.ico")
    _write_png(OUT_DIR / "logo_docs.png", LOGO_DOCS_SIZE)

    print(
        "Wrote favicon PNGs, favicon.ico, and logo_docs.png under",
        OUT_DIR,
    )


if __name__ == "__main__":
    main()
