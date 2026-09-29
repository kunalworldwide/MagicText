#!/usr/bin/env python3
"""Generate MagicText icons.

Outputs:
  assets/icon.png    — 1024px app icon: blue gradient squircle + white wand glyph
  assets/menubar.png — 512px menu bar template icon: white glyph on transparency

The glyph (wand + sparkles) is drawn once in a 1000x1000 design space,
measured, then auto-centered and scaled into each target. Assertions verify
geometry so a broken render can never silently ship.
"""
from PIL import Image, ImageDraw
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ICON = os.path.join(REPO, "assets", "icon.png")
OUT_MENUBAR = os.path.join(REPO, "assets", "menubar.png")

WHITE = (255, 255, 255, 255)


def star4(draw, cx, cy, R, fill, ratio=0.30):
    """Four-point sparkle."""
    d = R * ratio
    pts = [(cx, cy - R), (cx + d, cy - d), (cx + R, cy), (cx + d, cy + d),
           (cx, cy + R), (cx - d, cy + d), (cx - R, cy), (cx - d, cy - d)]
    draw.polygon(pts, fill=fill)


def wand_line(draw, p1, p2, width, fill):
    """Rounded-cap line."""
    draw.line([p1, p2], fill=fill, width=width)
    r = width / 2
    for (x, y) in (p1, p2):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def make_glyph_layer(design=1000):
    """Wand pointing up-right, big sparkle at its tip, two small sparkles."""
    layer = Image.new("RGBA", (design, design), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    wand_line(d, (250, 750), (560, 440), 76, WHITE)      # the wand
    star4(d, 695, 305, 160, WHITE)                        # big sparkle at tip
    star4(d, 365, 200, 80, WHITE, ratio=0.32)             # small sparkle, upper-left
    star4(d, 858, 515, 55, WHITE, ratio=0.32)             # small sparkle, right
    return layer


def fit_glyph(layer, size, fill_frac):
    """Crop glyph to its alpha bbox, scale so it fills `fill_frac` of `size`, center."""
    bbox = layer.split()[3].getbbox()
    assert bbox, "glyph layer is empty"
    cropped = layer.crop(bbox)
    w, h = cropped.size
    target = int(size * fill_frac)
    scale = min(target / w, target / h)
    resized = cropped.resize((max(1, int(w * scale)), max(1, int(h * scale))),
                             Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(resized, ((size - resized.width) // 2, (size - resized.height) // 2), resized)
    return out


def vgrad(size, top_rgb, bottom_rgb):
    """Vertical gradient via 1x2 stretch (row 0 = top)."""
    g = Image.new("RGB", (1, 2))
    g.putpixel((0, 0), top_rgb)
    g.putpixel((0, 1), bottom_rgb)
    return g.resize((size, size), Image.Resampling.BILINEAR)


def make_app_icon(glyph_layer):
    S = 4096  # supersample
    radius = int(S * 0.2245)  # macOS squircle
    # gradient body: lighter blue on top -> deeper blue at bottom
    body = vgrad(S, (1, 105, 252), (0, 77, 217)).convert("RGBA")
    # top sheen: white fading out over the top 16%
    sheen_h = int(S * 0.16)
    ramp = Image.new("L", (1, 2))
    ramp.putpixel((0, 0), 255)
    ramp.putpixel((0, 1), 0)
    alpha = ramp.resize((S, sheen_h), Image.Resampling.BILINEAR).point(lambda p: p * 34 // 255)
    body.paste(Image.new("RGBA", (S, sheen_h), (255, 255, 255, 255)), (0, 0), alpha)
    # white glyph, fills 56% of the icon
    glyph = fit_glyph(glyph_layer, S, 0.56)
    body.alpha_composite(glyph)
    # rounded-squircle mask
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(body, (0, 0), mask)
    # slim dark rim for definition on light backgrounds
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius,
                                          outline=(0, 20, 60, 70), width=int(S * 0.004))
    icon.alpha_composite(rim)
    return icon.resize((1024, 1024), Image.Resampling.LANCZOS)


def make_menubar_template(glyph_layer):
    """White glyph, transparent background -> NSImage template (isTemplate=true)."""
    return fit_glyph(glyph_layer, 512, 0.85)


def alpha_bbox_frac(im):
    b = im.split()[3].getbbox()
    if not b:
        return None
    W, H = im.size
    return (b[0] / W, b[1] / H, b[2] / W, b[3] / H)


def coverage(im, step=4):
    W, H = im.size
    px = im.load()
    n = tot = 0
    for y in range(0, H, step):
        for x in range(0, W, step):
            tot += 1
            if px[x, y][3] > 40:
                n += 1
    return n / tot


def ascii_preview(im, cells=48, thr=60):
    small = im.resize((cells, cells), Image.Resampling.LANCZOS)
    px = small.load()
    return "\n".join("".join("#" if px[x, y][3] > thr else "." for x in range(cells))
                     for y in range(cells))


def main():
    glyph = make_glyph_layer()
    gb = alpha_bbox_frac(glyph)
    print("glyph design bbox:", gb)
    assert gb and gb[1] > 0.05 and gb[3] < 0.95, "glyph should span most of design space vertically"

    app = make_app_icon(glyph)
    app.save(OUT_ICON)
    tpl = make_menubar_template(glyph)
    tpl.save(OUT_MENUBAR)

    # --- verify app icon ---
    px = app.load()
    corners = [px[2, 2][3], px[1021, 2][3], px[2, 1021][3], px[1021, 1021][3]]
    print("app: size", app.size, "mode", app.mode, "corner alphas", corners)
    assert all(c == 0 for c in corners), "app icon corners must be transparent"
    top = px[512, 60]
    bottom = px[512, 964]
    print("app: top px", top, "bottom px", bottom)
    assert top[2] > bottom[2] + 10, "gradient must be lighter on top"
    # sample body points that skip the glyph (checked against glyph coverage below)
    blue_pts = [(140, 850), (900, 850), (900, 140), (300, 140), (150, 500)]
    blues = [p for p in blue_pts if px[p[0], p[1]][2] > 180 and px[p[0], p[1]][0] < 80]
    print("app: blue body samples", len(blues), "/", len(blue_pts))
    assert len(blues) >= 4, "body should be predominantly blue"

    # --- verify template icon ---
    tp = tpl.load()
    print("tpl: size", tpl.size, "mode", tpl.mode)
    tb = alpha_bbox_frac(tpl)
    print("tpl: alpha bbox frac", tb)
    assert tb[0] > 0.03 and tb[1] > 0.03 and tb[2] < 0.97 and tb[3] < 0.97, "glyph must have margins"
    cov = coverage(tpl)
    print("tpl: coverage %.1f%%" % (100 * cov))
    assert 0.03 < cov < 0.30, "implausible glyph coverage"
    # glyph must be white where opaque
    W = tpl.size[0]
    samples = [(x, y) for y in range(0, W, 37) for x in range(0, W, 37)]
    opaque = [(x, y) for (x, y) in samples if tp[x, y][3] > 200]
    assert opaque, "no opaque samples"
    # Template rendering only uses the alpha channel, but keep the glyph white:
    # allow anti-aliased edges (RGB blends toward transparent black on resize).
    non_white = [(x, y) for (x, y) in opaque
                 if max(tp[x, y][:3]) - min(tp[x, y][:3]) > 3 or min(tp[x, y][:3]) < 225]
    print("tpl: opaque samples", len(opaque), "non-white", len(non_white))
    assert not non_white, f"template glyph must be pure white, bad: {non_white[:5]}"

    print("--- menubar template preview ---")
    print(ascii_preview(tpl))
    print("--- app icon glyph preview (glyph layer @56%) ---")
    print(ascii_preview(fit_glyph(glyph, 512, 0.56)))
    print("OK: wrote", OUT_ICON, "and", OUT_MENUBAR)


if __name__ == "__main__":
    main()
