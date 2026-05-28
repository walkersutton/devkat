#!/usr/bin/env python3
"""
Rebuild App Store cards (iPhone + iPad) from the committed phone renderings.

Use this when the renderings in `scripts/app-store-previews/renderings/` are
authoritative (e.g. hand-tuned) and the cards need to catch up *without*
regenerating renderings from raw source screenshots.

Outputs:
  scripts/app-store-previews/cards/NN-card.png       (1284x2778)
  scripts/app-store-previews/ipad-cards/NN-ipad-card.png  (2048x2732)
"""

from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

IPHONE_W, IPHONE_H = 1284, 2778
IPAD_W, IPAD_H = 2048, 2732

PHONE_ASPECT = 19.5 / 9
CARD_BG = (250, 249, 246)

CONTENT_OFFSET_RATIO = 0.025
TEXT_TOP_RATIO = 0.055
PHONE_Y_RATIO_IPHONE = 0.18
PHONE_Y_RATIO_IPAD = 0.22
BOTTOM_PAD_RATIO_IPHONE = 0.055
BOTTOM_PAD_RATIO_IPAD = 0.025
FONT_SIZE_RATIO = 0.068
LINE_SPACING_RATIO = 0.014
PHONE_WIDTH_RATIO = 0.78

CAPTIONS: list[list[str]] = [
    ["For AI", "dirtbags."],
    ["Download", "Devkat."],
    ["Yell at", "Claude."],
    ["Yell at", "Codex."],
    ["Share it."],
]

OUT_DIR = Path(__file__).parent / "app-store-previews"
RENDERINGS_DIR = OUT_DIR / "renderings"


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


def extract_phone_from_rendering(rendering: Image.Image) -> Image.Image:
    """Strip drop-shadow + transparent padding, returning just the phone frame.

    The phone body is fully opaque (alpha==255). The shadow is partially
    transparent. Threshold the alpha channel to isolate the phone-only bbox.
    """
    rgba = rendering.convert("RGBA")
    alpha = rgba.getchannel("A")
    phone_only_mask = alpha.point(lambda p: 255 if p >= 250 else 0)
    bbox = phone_only_mask.getbbox()
    if bbox is None:
        raise RuntimeError("No opaque phone region found in rendering")
    return rgba.crop(bbox)


def render_card(
    phone: Image.Image,
    lines: list[str],
    card_w: int,
    card_h: int,
    phone_y_ratio: float,
    bottom_pad_ratio: float,
) -> Image.Image:
    card = Image.new("RGB", (card_w, card_h), CARD_BG)
    draw = ImageDraw.Draw(card)

    font = load_font(round(card_w * FONT_SIZE_RATIO))
    text = "\n".join(l for l in lines if l)
    spacing = round(card_w * LINE_SPACING_RATIO)
    content_off = round(card_h * CONTENT_OFFSET_RATIO)
    text_top = round(card_h * TEXT_TOP_RATIO) + content_off
    bbox = draw.multiline_textbbox((0, 0), text, font=font, spacing=spacing, align="center")
    text_w = bbox[2] - bbox[0]
    draw.multiline_text(
        ((card_w - text_w) // 2, text_top),
        text, font=font, fill=(10, 10, 10), spacing=spacing, align="center",
    )

    phone_y = round(card_h * phone_y_ratio) + content_off
    bottom_padding = round(card_h * bottom_pad_ratio)
    max_w_by_height = round((card_h - phone_y - bottom_padding) / PHONE_ASPECT)
    desired_w = round(card_w * PHONE_WIDTH_RATIO)
    phone_w = min(desired_w, max_w_by_height)
    phone_h = round(phone_w * PHONE_ASPECT)
    phone_resized = phone.resize((phone_w, phone_h), Image.LANCZOS)

    phone_x = (card_w - phone_w) // 2
    card_rgba = card.convert("RGBA")
    card_rgba.alpha_composite(phone_resized, (phone_x, phone_y))
    return card_rgba.convert("RGB")


def main() -> None:
    cards_dir = OUT_DIR / "cards"
    ipad_cards_dir = OUT_DIR / "ipad-cards"
    cards_dir.mkdir(parents=True, exist_ok=True)
    ipad_cards_dir.mkdir(parents=True, exist_ok=True)

    for i, lines in enumerate(CAPTIONS, start=1):
        slug = f"{i:02d}"
        rendering_path = RENDERINGS_DIR / f"{slug}-rendering.png"
        if not rendering_path.exists():
            print(f"  ⚠️  Missing rendering: {rendering_path}"); continue

        phone = extract_phone_from_rendering(Image.open(rendering_path))

        iphone_card = render_card(
            phone, lines, IPHONE_W, IPHONE_H,
            PHONE_Y_RATIO_IPHONE, BOTTOM_PAD_RATIO_IPHONE,
        )
        iphone_card.save(cards_dir / f"{slug}-card.png")
        print(f"  ✓ cards/{slug}-card.png")

        ipad_card = render_card(
            phone, lines, IPAD_W, IPAD_H,
            PHONE_Y_RATIO_IPAD, BOTTOM_PAD_RATIO_IPAD,
        )
        ipad_card.save(ipad_cards_dir / f"{slug}-ipad-card.png")
        print(f"  ✓ ipad-cards/{slug}-ipad-card.png")


if __name__ == "__main__":
    main()
