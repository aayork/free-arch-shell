#!/usr/bin/env python3
"""Build roseshell-icons.otf: Lucide artwork placed at Nerd Font codepoints.

The shell's QML hardcodes Nerd Font glyphs. Rather than rewrite every string,
this font covers those same codepoints with Lucide icons, and icon text renders
with font.families [Roseshell Icons, <bar font>], so anything not in map.json
(brand logos, etc.) falls through to the Nerd Font.

Metrics match BlexMono Nerd Font (1000 upm, 1025/-275 line box) and each icon
sits in a 1000-unit square centered where Material Design Nerd glyphs sit, so
swapping fonts doesn't move baselines or change icon size.

Requires: fonttools, picosvg (pip). Usage:
  build.py [--stroke 2] [--lucide-version 1.48.0]
"""
import argparse
import io
import json
import os
import re
import tarfile
import urllib.request

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import SVGPath
from picosvg.svg import SVG

HERE = os.path.dirname(os.path.abspath(__file__))
UPM = 1000
ASCENT, DESCENT = 1025, -275
BOX = 1000          # the 24-unit Lucide viewBox maps onto this many font units
CENTER_Y = 375      # vertical center of Material Design glyphs in the Nerd Font
ADVANCE = 1000
FAMILY = "Roseshell Icons"


def lucide_icons(version):
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                         "roseshell", f"lucide-static-{version}")
    icons = os.path.join(cache, "package", "icons")
    if not os.path.isdir(icons):
        url = f"https://registry.npmjs.org/lucide-static/-/lucide-static-{version}.tgz"
        data = urllib.request.urlopen(url).read()
        os.makedirs(cache, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(data)) as tar:
            tar.extractall(cache, filter="data")
    return icons


def draw_icon(svg_path, stroke, pen):
    text = open(svg_path, encoding="utf-8").read()
    text = re.sub(r'stroke-width="[^"]*"', f'stroke-width="{stroke}"', text, count=1)
    pico = SVG.fromstring(text).topicosvg()
    scale = BOX / 24
    # SVG is y-down in a 24x24 box; font space is y-up.
    transform = (scale, 0, 0, -scale, (ADVANCE - BOX) / 2, CENTER_Y + 12 * scale)
    SVGPath.fromstring(pico.tostring()).draw(TransformPen(pen, transform))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stroke", type=float, default=2.0, help="Lucide stroke width (24-unit grid)")
    ap.add_argument("--lucide-version", default="1.48.0")
    ap.add_argument("--out", default=os.path.join(HERE, "roseshell-icons.otf"))
    args = ap.parse_args()

    mapping = {int(k, 16): v for k, v in json.load(open(os.path.join(HERE, "map.json"))).items()
               if not k.startswith("_")}
    icons = lucide_icons(args.lucide_version)

    names = sorted(set(mapping.values()))
    glyph_order = [".notdef"] + names
    charstrings = {}
    for name in glyph_order:
        pen = T2CharStringPen(ADVANCE, None)
        if name != ".notdef":
            draw_icon(os.path.join(icons, name + ".svg"), args.stroke, pen)
        charstrings[name] = pen.getCharString()

    fb = FontBuilder(UPM, isTTF=False)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(mapping)
    fb.setupCFF(FAMILY.replace(" ", ""), {"FullName": FAMILY}, charstrings, {})
    fb.setupHorizontalMetrics({n: (ADVANCE, 0) for n in glyph_order})
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": "Regular",
        "version": f"Lucide {args.lucide_version}, stroke {args.stroke}",
        "licenseDescription": "Icons from Lucide (ISC); see LICENSE-lucide.",
    })
    fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, sTypoLineGap=0,
                usWinAscent=ASCENT, usWinDescent=-DESCENT)
    fb.setupPost()
    fb.save(args.out)
    print(f"{args.out}: {len(names)} icons, {len(mapping)} codepoints, stroke {args.stroke}")


if __name__ == "__main__":
    main()
