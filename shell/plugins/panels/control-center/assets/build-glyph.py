#!/usr/bin/env python3
"""Build control-center.otf: the bar's two-switch icon as a font glyph.

Drawn as a glyph (not a QML Shape) so the text renderer snaps it to the pixel
grid like the Nerd Font icons around it; vector shapes at fractional scales
land between pixels and look soft. Geometry uses the Material Design 24-unit
grid and BlexMono Nerd Font metrics (1000 upm, box centered at y=375), so it
sizes and aligns like the md-* glyphs. Requires fonttools + skia-pathops.

The glyph sits at U+E000.
"""
import os

import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen

HERE = os.path.dirname(os.path.abspath(__file__))
CODEPOINT = 0xE000
ADVANCE = 1000
SCALE = 1000 / 24
CENTER_Y = 375


def capsule(x0, y0, x1, y1):
    """Closed capsule path on the 24-grid (y down)."""
    p = pathops.Path()
    r = (y1 - y0) / 2
    k = 0.5523 * r  # cubic circle approximation
    cy = y0 + r
    p.moveTo(x0 + r, y0)
    p.lineTo(x1 - r, y0)
    p.cubicTo(x1 - r + k, y0, x1, cy - k, x1, cy)
    p.cubicTo(x1, cy + k, x1 - r + k, y1, x1 - r, y1)
    p.lineTo(x0 + r, y1)
    p.cubicTo(x0 + r - k, y1, x0, cy + k, x0, cy)
    p.cubicTo(x0, cy - k, x0 + r - k, y0, x0 + r, y0)
    p.close()
    return p


def circle(cx, cy, r):
    return capsule(cx - r, cy - r, cx + r, cy + r)


def op(a, b, kind):
    return pathops.op(a, b, kind)


# Top switch "on": solid track, knob punched out on the right.
top = op(capsule(2, 3, 22, 11), circle(18, 7, 2.25), pathops.PathOp.DIFFERENCE)
# Bottom switch "off": outlined track (stroke 2) with a full-height knob left.
ring = op(capsule(2, 13, 22, 21), capsule(4, 15, 20, 19), pathops.PathOp.DIFFERENCE)
bottom = op(ring, circle(6, 17, 4), pathops.PathOp.UNION)
glyph = op(top, bottom, pathops.PathOp.UNION)

pen = T2CharStringPen(ADVANCE, None)
transform = (SCALE, 0, 0, -SCALE, (ADVANCE - 24 * SCALE) / 2, CENTER_Y + 12 * SCALE)
glyph.draw(TransformPen(pen, transform))

fb = FontBuilder(1000, isTTF=False)
fb.setupGlyphOrder([".notdef", "switches"])
fb.setupCharacterMap({CODEPOINT: "switches"})
fb.setupCFF("RoseshellControlCenter", {"FullName": "Roseshell Control Center"},
            {".notdef": T2CharStringPen(ADVANCE, None).getCharString(), "switches": pen.getCharString()}, {})
fb.setupHorizontalMetrics({".notdef": (ADVANCE, 0), "switches": (ADVANCE, 0)})
fb.setupHorizontalHeader(ascent=1025, descent=-275)
fb.setupNameTable({"familyName": "Roseshell Control Center", "styleName": "Regular"})
fb.setupOS2(sTypoAscender=1025, sTypoDescender=-275, sTypoLineGap=0, usWinAscent=1025, usWinDescent=275)
fb.setupPost()
out = os.path.join(HERE, "control-center.otf")
fb.save(out)
print(out)
