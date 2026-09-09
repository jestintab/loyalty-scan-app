#!/usr/bin/env python3
"""Cut the launcher icon out of the Qwallet logo, for both platforms.

The lockup in assets/qwallet-logo.png is a gold wallet mark beside a near-black
wordmark. A launcher icon is square and read at ~40px, so the wordmark can't
come along — only the mark does.

Ground colour is the wordmark's own near-black (#1A1815), not the cream the
logo is printed on. That is a contrast decision, not a taste one: the brand
gold on cream is 2.84:1, under the 3:1 floor for a graphic that has to carry
meaning, while the same gold on the ink is 6.14:1. Keeping the ink also means
the icon is made of the two brand colours exactly as drawn, with no third
colour invented and no gold re-mixed to make it legible.

Run from the repo root:  python3 tool/make_launcher_icons.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "qwallet-logo.png"

# Everything left of the wordmark, which starts at x=328. The mark's own tight
# bounds get measured inside mark(); this is only the region to look in.
MARK_REGION = (0, 0, 320, 400)

GOLD = (0xC0, 0x90, 0x2D)
INK = (0x1A, 0x18, 0x15)

# The launch image is the same mark on the same disc as the launcher icon, at
# 120pt. Android composes its splash from the adaptive icon automatically;
# iOS has to be handed a picture, and handing it a different one would mean the
# app looked like two apps between tapping it and it opening.
LAUNCH_PT = 120

# How much of each canvas the mark's height takes up. The adaptive figure is
# the small one because Android reserves the outer quarter of that canvas for
# parallax and mask: 46% of 108dp lands the mark at two thirds of the 72dp a
# launcher actually shows, which is where it sits comfortably rather than
# crowding the mask edge.
ADAPTIVE_SCALE = 0.46
LEGACY_SCALE = 0.58
IOS_SCALE = 0.58

# Adaptive foreground/monochrome layers are 108dp; these are the pixel sizes at
# each density bucket.
ADAPTIVE_PX = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def mark() -> Image.Image:
    """The mark redrawn as flat gold on transparency.

    The artwork was made for white paper, and it shows: the hairlines fanning
    the cards apart are painted white rather than left open, and every edge is
    antialiased towards white. Composited straight onto a dark ground both turn
    into pale fringing, and the fan ends up with cream gaps in one place and
    dark gaps in another.

    So rather than composite the pixels, measure them. Laying the artwork back
    on its white paper and reading the blue channel recovers how much gold ink
    each pixel carries — 255 on bare paper, 45 under full gold — and that
    coverage becomes the alpha of a flat gold fill. Painted whites drop out with
    the paper, edges keep their antialiasing, and every gap in the fan reads as
    the ground, whatever colour the ground happens to be.
    """
    src = Image.open(SOURCE).convert("RGBA").crop(MARK_REGION)
    paper = Image.new("RGBA", src.size, (255, 255, 255, 255))
    paper.alpha_composite(src)

    span = 255 - GOLD[2]
    coverage = paper.getchannel("B").point(
        lambda v: min(255, round((255 - v) * 255 / span))
    )

    art = Image.new("RGBA", src.size, GOLD + (255,))
    art.putalpha(coverage)
    return art.crop(coverage.getbbox())


def placed(canvas: int, scale: float, art: Image.Image) -> Image.Image:
    """The mark, scaled by height and centred on a transparent square."""
    height = round(canvas * scale)
    width = round(art.width * height / art.height)
    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    layer.paste(
        art.resize((width, height), Image.LANCZOS),
        ((canvas - width) // 2, (canvas - height) // 2),
    )
    return layer


def silhouette(art: Image.Image) -> Image.Image:
    """The mark's shape in flat black. Android 13 tints this itself for themed
    icons, so only the alpha channel survives — but a flat fill keeps the gold
    out of the picture if a launcher ever draws it untinted."""
    solid = Image.new("RGBA", art.size, (0, 0, 0, 255))
    solid.putalpha(art.getchannel("A"))
    return solid


def rounded(canvas: int, radius_ratio: float = 0.22) -> Image.Image:
    """An ink square with rounded corners, for the pre-Android-8 icon, which
    the launcher draws exactly as given — no mask, no shape of its own."""
    ground = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(ground).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1),
        radius=round(canvas * radius_ratio),
        fill=INK + (255,),
    )
    return ground


def launch_tile(px: int, art: Image.Image) -> Image.Image:
    """The icon's disc and mark, on transparency.

    Transparent rather than on the cream, because the storyboard paints the
    ground from a colour set that follows light and dark mode — baking a light
    background in here would put a cream card in the middle of a dark screen.
    """
    tile = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    ImageDraw.Draw(tile).ellipse((0, 0, px - 1, px - 1), fill=INK + (255,))
    tile.alpha_composite(placed(px, ADAPTIVE_SCALE / (72 / 108), art))
    return tile


def size_of(path: Path) -> int:
    with Image.open(path) as im:
        assert im.width == im.height, f"{path} is not square"
        return im.width


def main() -> None:
    art = mark()
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    written = []

    for bucket, canvas in ADAPTIVE_PX.items():
        folder = res / f"mipmap-{bucket}"
        folder.mkdir(parents=True, exist_ok=True)

        fg = placed(canvas, ADAPTIVE_SCALE, art)
        fg.save(folder / "ic_launcher_foreground.png")
        placed(canvas, ADAPTIVE_SCALE, silhouette(art)).save(
            folder / "ic_launcher_monochrome.png"
        )
        written += [folder / "ic_launcher_foreground.png",
                    folder / "ic_launcher_monochrome.png"]

        # Legacy: same mark, but this canvas is the whole icon, so it carries
        # its own ink ground and its own corners.
        legacy_path = folder / "ic_launcher.png"
        legacy_canvas = size_of(legacy_path)
        legacy = rounded(legacy_canvas)
        legacy.alpha_composite(placed(legacy_canvas, LEGACY_SCALE, art))
        legacy.save(legacy_path)
        written.append(legacy_path)

    # iOS: full bleed, opaque, no alpha and no corners of our own — the system
    # rounds it, and an icon with alpha is rejected at submission.
    appicon = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for path in sorted(appicon.glob("Icon-App-*.png")):
        canvas = size_of(path)
        tile = Image.new("RGBA", (canvas, canvas), INK + (255,))
        tile.alpha_composite(placed(canvas, IOS_SCALE, art))
        tile.convert("RGB").save(path)
        written.append(path)

    # iOS launch screen: one image per scale, named as the storyboard expects.
    launch = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    for scale in (1, 2, 3):
        name = "LaunchImage.png" if scale == 1 else f"LaunchImage@{scale}x.png"
        launch_tile(LAUNCH_PT * scale, art).save(launch / name)
        written.append(launch / name)

    for path in written:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
