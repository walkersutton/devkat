#!/usr/bin/env python3
"""
Generate App Store preview cards for DEVKAT.

Usage:
    python3 scripts/generate-app-store-previews.py

Outputs to:  scripts/app-store-previews/
  cards/       — 1290×2796 iPhone 6.7" cards (App Store required size)
  ipad-cards/  — 2048×2732 iPad Pro 12.9" cards (App Store required size)
  renderings/  — phone-only PNGs with drop shadow (for website/marketing)
"""

from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ── Output sizes ──────────────────────────────────────────────────────────────
IPHONE_W, IPHONE_H = 1290, 2796   # iPhone 6.7" Pro Max
IPAD_W,   IPAD_H   = 2048, 2732   # iPad Pro 12.9"

# ── Phone frame appearance ────────────────────────────────────────────────────
PHONE_ASPECT    = 19.5 / 9
PHONE_BORDER    = 14
PHONE_RADIUS    = 120
PHONE_FRAME_COL = (20, 20, 20, 255)
PHONE_SCREEN_BG = (0, 0, 0, 255)

# ── Card background (matches Runnon) ─────────────────────────────────────────
CARD_BG = (250, 249, 246)

# ── Layout ratios (match Runnon exactly) ─────────────────────────────────────
CONTENT_OFFSET_RATIO = 0.025
TEXT_TOP_RATIO       = 0.055
PHONE_Y_RATIO        = 0.18
BOTTOM_PAD_RATIO     = 0.055
FONT_SIZE_RATIO      = 0.068
LINE_SPACING_RATIO   = 0.014
PHONE_WIDTH_RATIO    = 0.78

# ── Screenshots + captions ───────────────────────────────────────────────────
ASSETS = Path(__file__).parent.parent / ".." / ".cursor/projects/Users-xavierkahn-devkat/assets"
SCREENSHOTS = [
    {
        "path": ASSETS / "IMG_4469-bde85d89-d85a-4c31-975c-29c19222d9f2.png",
        "lines": ["For AI", "dirtbags."],
    },
    {
        "path": Path("/Users/xavierkahn/.cursor/projects/Users-xavierkahn-devkat/assets/Screenshot_2026-05-05_at_14.28.55-f2b15481-2c07-44c4-a13e-e3c9eeed2fee.png"),
        "lines": ["Download", "Devkat."],
    },
    {
        "path": ASSETS / "IMG_4462-26571da0-d562-4ec4-aaca-724472f353ca.png",
        "lines": ["Yell at", "Claude."],
    },
    {
        "path": Path("/Users/xavierkahn/.cursor/projects/Users-xavierkahn-devkat/assets/Screenshot_2026-05-05_at_14.44.29-c47f03de-0224-4530-91d3-059c751a17ac.png"),
        "lines": ["Yell at", "Codex."],
    },
    {
        "path": Path("/Users/xavierkahn/.cursor/projects/Users-xavierkahn-devkat/assets/3567B9F0-9AE3-473D-819E-EB7B57E23221-7e0fe078-8b6b-4c26-a4b5-47bd4d4b80f9.png"),
        "lines": ["Share it."],
    },
]

OUT_DIR = Path(__file__).parent / "app-store-previews"


# ── Helpers ───────────────────────────────────────────────────────────────────

def cover_resize(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    tw, th = size
    scale = max(tw / img.width, th / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    l = (img.width - tw) // 2
    t = (img.height - th) // 2
    return img.crop((l, t, l + tw, t + th))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    w, h = size
    ss = 4
    mask = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=radius * ss, fill=255)
    return mask.resize(size, Image.LANCZOS)


def render_phone(screenshot: Image.Image, phone_w: int) -> Image.Image:
    phone_h  = round(phone_w * PHONE_ASPECT)
    scr_size = (phone_w - 2 * PHONE_BORDER, phone_h - 2 * PHONE_BORDER)

    phone = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    phone.paste(Image.new("RGBA", (phone_w, phone_h), PHONE_FRAME_COL),
                mask=rounded_mask((phone_w, phone_h), PHONE_RADIUS))

    screen = Image.new("RGBA", scr_size, PHONE_SCREEN_BG)
    screen.alpha_composite(cover_resize(screenshot.convert("RGBA"), scr_size))
    phone.paste(screen, (PHONE_BORDER, PHONE_BORDER),
                mask=rounded_mask(scr_size, max(1, PHONE_RADIUS - PHONE_BORDER)))
    return phone


def add_shadow(img: Image.Image, blur: int = 40, offset: tuple[int, int] = (0, 30),
               opacity: float = 0.35, padding: int = 60) -> Image.Image:
    ox, oy = offset
    canvas = Image.new("RGBA",
        (img.width + padding * 2 + abs(ox), img.height + padding * 2 + abs(oy)), (0, 0, 0, 0))
    ix = padding + max(0, -ox)
    iy = padding + max(0, -oy)
    shadow_alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(blur))
    shadow_alpha = shadow_alpha.point(lambda p: round(p * opacity))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow, (ix + ox, iy + oy))
    canvas.alpha_composite(img, (ix, iy))
    return canvas


def load_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        ("/System/Library/Fonts/Avenir Next.ttc", 0),
        ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", None),
        ("/System/Library/Fonts/Supplemental/Helvetica Bold.ttf", None),
    ]
    for path, index in candidates:
        if Path(path).exists():
            kwargs = {"index": index} if index is not None else {}
            return ImageFont.truetype(path, size=size, **kwargs)
    return ImageFont.load_default()


def render_card(screenshot: Image.Image, lines: list[str],
                card_w: int, card_h: int,
                phone_y_ratio: float = PHONE_Y_RATIO,
                bottom_pad_ratio: float = BOTTOM_PAD_RATIO) -> Image.Image:
    """Render a card at any size — all layout values scale proportionally."""
    card = Image.new("RGB", (card_w, card_h), CARD_BG)
    draw = ImageDraw.Draw(card)

    font        = load_font(round(card_w * FONT_SIZE_RATIO))
    text        = "\n".join(l for l in lines if l)
    spacing     = round(card_w * LINE_SPACING_RATIO)
    content_off = round(card_h * CONTENT_OFFSET_RATIO)
    text_top    = round(card_h * TEXT_TOP_RATIO) + content_off
    bbox        = draw.multiline_textbbox((0, 0), text, font=font, spacing=spacing, align="center")
    text_w      = bbox[2] - bbox[0]
    draw.multiline_text(
        ((card_w - text_w) // 2, text_top),
        text, font=font, fill=(10, 10, 10), spacing=spacing, align="center"
    )

    phone_y         = round(card_h * phone_y_ratio) + content_off
    bottom_padding  = round(card_h * bottom_pad_ratio)
    max_w_by_height = round((card_h - phone_y - bottom_padding) / PHONE_ASPECT)
    desired_w       = round(card_w * PHONE_WIDTH_RATIO)
    phone_w         = min(desired_w, max_w_by_height)
    phone           = render_phone(screenshot, phone_w)
    phone_x         = (card_w - phone.width) // 2
    card_rgba       = card.convert("RGBA")
    card_rgba.alpha_composite(phone, (phone_x, phone_y))
    return card_rgba.convert("RGB")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    cards_dir      = OUT_DIR / "cards"
    ipad_cards_dir = OUT_DIR / "ipad-cards"
    renderings_dir = OUT_DIR / "renderings"
    for d in (cards_dir, ipad_cards_dir, renderings_dir):
        d.mkdir(parents=True, exist_ok=True)

    for i, item in enumerate(SCREENSHOTS, start=1):
        path = Path(item["path"]).resolve()
        if not path.exists():
            print(f"  ⚠️  Missing: {path}"); continue

        screenshot = Image.open(path)
        slug = f"{i:02d}"

        card = render_card(screenshot, item["lines"], IPHONE_W, IPHONE_H)
        card.save(cards_dir / f"{slug}-card.png")
        print(f"  ✓ cards/{slug}-card.png")

        ipad_card = render_card(screenshot, item["lines"], IPAD_W, IPAD_H,
                                phone_y_ratio=0.185, bottom_pad_ratio=0.025)
        ipad_card.save(ipad_cards_dir / f"{slug}-ipad-card.png")
        print(f"  ✓ ipad-cards/{slug}-ipad-card.png")

        phone  = render_phone(screenshot, 1125)
        shadow = add_shadow(phone, blur=50, offset=(0, 40), opacity=0.30, padding=80)
        shadow.save(renderings_dir / f"{slug}-rendering.png")
        print(f"  ✓ renderings/{slug}-rendering.png")


if __name__ == "__main__":
    main()
