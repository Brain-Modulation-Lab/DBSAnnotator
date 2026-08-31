#!/usr/bin/env python3
"""Build desktop icon assets (Briefcase + Qt) from a single **square-ish** source PNG.

**Output directory** defaults to ``icons/logosimple/`` so all app-icon files for one
mark live together.

**Linux (``linux system`` / .deb):** BeeWare’s template lists exactly six PNGs:
``icon.16`` … ``icon.512`` in ``briefcase.toml``; Briefcase copies them from
``{icon}-{size}.png`` into ``usr/share/icons/hicolor/<size>/apps/<bundle id>.png``.
All six sizes are required (missing files keep the template placeholder).

**Windows:** one multi-size ``.ico`` (16, 32, 48, 64, 256).

**macOS .icns:** Apple’s ``iconutil`` reads a ``.iconset`` folder (fixed PNG names and
pixel sizes) and writes a **single** ``.icns`` binary. That is the only portable way
to produce a valid ``.icns``; run ``iconutil`` on macOS (or copy the ``.iconset`` to
a Mac). The ``.iconset`` is build input only — you can delete it after ``.icns`` exists.

**Source:** prefer ≥512 px for clean downscales.

Requires Pillow (pulled in via project deps e.g. matplotlib).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

# Windows stub / MSI (BeeWare Windows icon format)
WIN_ICO_SIZES = (16, 32, 48, 64, 256)
# Linux system: briefcase-linux-system-template briefcase.toml path_index
LINUX_PNG_SIZES = (16, 32, 64, 128, 256, 512)
# macOS .icns: logical pixel size -> PNG file (same as `iconutil` / .iconset)
# Each tuple: (filename, width_px, height_px)
MACOS_ICONSET = (
    ("icon_16x16.png", 16, 16),
    ("icon_16x16@2x.png", 32, 32),
    ("icon_32x32.png", 32, 32),
    ("icon_32x32@2x.png", 64, 64),
    ("icon_128x128.png", 128, 128),
    ("icon_128x128@2x.png", 256, 256),
    ("icon_256x256.png", 256, 256),
    ("icon_256x256@2x.png", 512, 512),
    ("icon_512x512.png", 512, 512),
    ("icon_512x512@2x.png", 1024, 1024),
)


def _load_rgba(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    return img


def _letterbox_rgba(src: Image.Image) -> Image.Image:
    """Square canvas: transparent padding (canvas side = max of width, height)."""
    w, h = src.size
    m = max(w, h)
    canvas = Image.new("RGBA", (m, m), (0, 0, 0, 0))
    canvas.paste(src, ((m - w) // 2, (m - h) // 2), src)
    return canvas


def _ico_frame_sizes(path: Path) -> list[int]:
    """Widths actually present in an .ico, read from its ICONDIR.

    Verifying the file rather than trusting the writer: the previous bug
    reported five sizes while writing one.
    """
    data = path.read_bytes()
    count = int.from_bytes(data[4:6], "little")
    sizes = []
    for i in range(count):
        width = data[6 + i * 16]
        sizes.append(256 if width == 0 else width)
    return sorted(sizes)


def build_icons(
    source: Path,
    out_dir: Path,
    name: str,
    master_px: int,
    *,
    write_master: bool,
) -> None:
    out_dir = out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    src = _load_rgba(source)
    src_sq = _letterbox_rgba(src)

    master = src_sq.copy()
    if max(master.size) != master_px:
        master = master.resize((master_px, master_px), Image.Resampling.LANCZOS)

    master_path = out_dir / f"{name}.png"
    if source.resolve() == master_path.resolve() and not write_master:
        print(
            f"Skip {master_path} (same as --source; "
            f"use --write-master to re-encode to {master_px}px)",
            file=sys.stderr,
        )
    else:
        master.save(master_path, format="PNG", optimize=True)
        print(f"Wrote {master_path}", file=sys.stderr)

    # Windows .ico (one file, multiple embedded sizes).
    #
    # Pillow's ICO writer generates every entry in ``sizes`` by downscaling the
    # image it is called on, and it SILENTLY DROPS any requested size larger
    # than that image. So the base must be the largest size -- an earlier
    # version saved from ``ico_images[0]``, i.e. the 16 px frame, which produced
    # a single-frame 16x16 .ico while still printing "sizes=[16, 32, 48, 64,
    # 256]". Windows then upscaled 16 px for the taskbar, the desktop shortcut
    # and the MSI. (``append_images`` is not used by the ICO plugin at all.)
    ico_path = out_dir / f"{name}.ico"
    largest = max(WIN_ICO_SIZES)
    ico_base = src_sq.resize((largest, largest), Image.Resampling.LANCZOS)
    ico_base.save(
        ico_path,
        format="ICO",
        sizes=[(px, px) for px in WIN_ICO_SIZES],
    )
    written = _ico_frame_sizes(ico_path)
    if written != sorted(WIN_ICO_SIZES):
        raise SystemExit(
            f"{ico_path}: expected frames {sorted(WIN_ICO_SIZES)}, wrote {written}"
        )
    print(f"Wrote {ico_path} sizes={written}", file=sys.stderr)

    # Linux AppImage PNGs
    for px in LINUX_PNG_SIZES:
        li = src_sq.copy()
        li = li.resize((px, px), Image.Resampling.LANCZOS)
        p = out_dir / f"{name}-{px}.png"
        li.save(p, format="PNG", optimize=True)
    print(
        f"Wrote {len(LINUX_PNG_SIZES)} Linux PNGs: {name}-<size>.png",
        file=sys.stderr,
    )

    # macOS .iconset
    iconset_dir = out_dir / f"{name}.iconset"
    if iconset_dir.is_dir():
        shutil.rmtree(iconset_dir)
    iconset_dir.mkdir(parents=True)
    for fname, w, h in MACOS_ICONSET:
        im = src_sq.copy()
        im = im.resize((w, h), Image.Resampling.LANCZOS)
        im.save(iconset_dir / fname, format="PNG", optimize=True)
    print(f"Wrote {iconset_dir}/ ({len(MACOS_ICONSET)} files)", file=sys.stderr)

    icns_path = out_dir / f"{name}.icns"
    if sys.platform == "darwin":
        try:
            # Writes ``{name}.icns`` next to ``{name}.iconset`` (overwrites if present).
            subprocess.run(
                ["iconutil", "-c", "icns", f"{name}.iconset", "-o", f"{name}.icns"],
                check=True,
                capture_output=True,
                text=True,
                cwd=out_dir,
            )
            print(f"Wrote {icns_path} (iconutil)", file=sys.stderr)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(
                f"iconutil failed: {e}; on a Mac, run (cwd = output dir above):\n"
                f"  iconutil -c icns {name}.iconset -o {name}.icns",
                file=sys.stderr,
            )
    else:
        print(
            f"Skip {icns_path} (not macOS). On macOS (cwd = {out_dir}):\n"
            f"  iconutil -c icns {name}.iconset -o {name}.icns",
            file=sys.stderr,
        )


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--source",
        type=Path,
        default=root / "icons" / "logosimple" / "logosimple.png",
        help="Source PNG (master artwork)",
    )
    p.add_argument(
        "--out-dir",
        type=Path,
        default=root / "icons" / "logosimple",
        help="Output directory (default: ./icons/logosimple)",
    )
    p.add_argument(
        "--name",
        default="logosimple",
        help="Base filename without extension (default: logosimple)",
    )
    p.add_argument(
        "--master-px",
        type=int,
        default=512,
        help="Pixel size of {name}.png (default: 512)",
    )
    p.add_argument(
        "--write-master",
        action=argparse.BooleanOptionalAction,
        default=None,
        help=(
            "Write {name}.png from source. If --source is that file, default is skip "
            "re-encoding; use --write-master to replace."
        ),
    )
    args = p.parse_args()
    if not args.source.is_file():
        sys.exit(f"Not found: {args.source.resolve()}")
    master_path = (args.out_dir / f"{args.name}.png").resolve()
    if args.write_master is None:
        write_master = args.source.resolve() != master_path
    else:
        write_master = args.write_master
    build_icons(
        source=args.source,
        out_dir=args.out_dir,
        name=args.name,
        master_px=args.master_px,
        write_master=write_master,
    )


if __name__ == "__main__":
    main()
