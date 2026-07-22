"""Regenerate Hafiz launcher icons: ivory bg, centered logo, no star."""
from __future__ import annotations

from PIL import Image

SRC = r"d:\Desktop\aiiii\hafiz\assets\brand\hafiz_logo_source.png"
OUT_FG = r"d:\Desktop\aiiii\hafiz\assets\brand\ic_launcher_foreground.png"
OUT_FULL = r"d:\Desktop\aiiii\hafiz\assets\brand\ic_launcher.png"

# App brand ivory (AppColors.ivory) — contrasts with olive logo
BG = (247, 241, 230, 255)  # #F7F1E6
TARGET_GREEN = (31, 77, 58)  # #1F4D3A AppColors.olive

SIZE = 1024
# ~62% of foreground canvas; with 16% inset ≈ 60–70% of adaptive safe zone
LOGO_FRAC = 0.62


def extract_logo(path: str) -> Image.Image:
    src = Image.open(path).convert("RGBA")
    pixels = src.load()
    w, h = src.size
    data = []
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r > 235 and g > 235 and b > 235:
                data.append((r, g, b, 0))
            else:
                data.append((r, g, b, 255))
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    logo = Image.new("RGBA", (w, h))
    logo.putdata(data)
    logo = logo.crop((minx, miny, maxx + 1, maxy + 1))

    # Drop light fringe
    lp = logo.load()
    lw, lh = logo.size
    for y in range(lh):
        for x in range(lw):
            r, g, b, a = lp[x, y]
            if a == 0:
                continue
            if r > 220 and g > 220 and b > 210 and (r + g + b) > 660:
                lp[x, y] = (r, g, b, 0)
    return logo


def recolor_to_brand(logo: Image.Image) -> Image.Image:
    """Map dark/teal body to olive; preserve gold accents."""
    lp = logo.load()
    lw, lh = logo.size
    for y in range(lh):
        for x in range(lw):
            r, g, b, a = lp[x, y]
            if a < 8:
                continue
            is_gold = (r > 100 and r > b + 40 and g > 60 and b < 80) or (
                r > 120 and g > 80 and b < 50
            )
            if is_gold:
                continue
            lum = (r + g + b) / 3.0
            factor = max(0.55, min(1.15, lum / 70.0))
            nr = int(min(255, TARGET_GREEN[0] * factor))
            ng = int(min(255, TARGET_GREEN[1] * factor))
            nb = int(min(255, TARGET_GREEN[2] * factor))
            lp[x, y] = (nr, ng, nb, a)
    return logo


def main() -> None:
    logo = recolor_to_brand(extract_logo(SRC))
    target = int(SIZE * LOGO_FRAC)
    lw, lh = logo.size
    scale = min(target / lw, target / lh)
    nw, nh = max(1, int(lw * scale)), max(1, int(lh * scale))
    logo_scaled = logo.resize((nw, nh), Image.Resampling.LANCZOS)

    ox = (SIZE - nw) // 2
    oy = (SIZE - nh) // 2

    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fg.paste(logo_scaled, (ox, oy), logo_scaled)
    fg.save(OUT_FG, "PNG")
    print(f"foreground: logo {nw}x{nh} at ({ox},{oy}) frac={nw / SIZE:.2f}")

    full = Image.new("RGBA", (SIZE, SIZE), BG)
    full.paste(logo_scaled, (ox, oy), logo_scaled)
    full.save(OUT_FULL, "PNG")
    print("full icon: bg=#F7F1E6")

    br = fg.crop((SIZE * 3 // 4, SIZE * 3 // 4, SIZE, SIZE))
    opaque = sum(1 for p in br.getdata() if p[3] > 20)
    print(f"bottom-right opaque pixels: {opaque} (expect 0 — star removed)")


if __name__ == "__main__":
    main()
