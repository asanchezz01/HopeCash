#!/usr/bin/env python3
"""Gera os recursos gráficos do HopeCash para o Google Play Console."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "store-assets"
OUTPUT_DIR = SOURCE_DIR / "google-play"
ASSET_DIR = Path(__file__).resolve().parent / "assets"

PHONE_SIZE = (1080, 1920)
TABLET_SIZE = (1920, 1080)
FEATURE_SIZE = (1024, 500)

NAVY = "#07111f"
NAVY_RAISED = "#0d1b2a"
MINT = "#57d6a1"
MINT_DEEP = "#0d7f57"
WHITE = "#ffffff"
SLATE = "#b8c5d1"

SLIDES = [
    {
        "source": "0x0ss (8).png",
        "slug": "hope",
        "title": "Converse com a Hope",
        "subtitle": "Pergunte por texto ou voz e confirme antes de qualquer alteração.",
        "accent": "#57d6a1",
    },
    {
        "source": "0x0ss (5).png",
        "slug": "lancamentos",
        "title": "Acompanhe cada lançamento",
        "subtitle": "Receitas, despesas e previsões organizadas em uma visão clara.",
        "accent": "#8db2ff",
    },
    {
        "source": "0x0ss (7).png",
        "slug": "contas",
        "title": "Contas em um só lugar",
        "subtitle": "Veja saldos, cartões e movimentações sem perder o contexto.",
        "accent": "#57d6a1",
    },
    {
        "source": "0x0ss (4).png",
        "slug": "cartoes",
        "title": "Controle cartões e faturas",
        "subtitle": "Acompanhe limites, compras e vencimentos com clareza.",
        "accent": "#b8a7ff",
    },
    {
        "source": "0x0ss (6).png",
        "slug": "orcamento",
        "title": "Planeje seu orçamento",
        "subtitle": "Compare o previsto e o realizado em cada categoria.",
        "accent": "#57d6a1",
    },
    {
        "source": "0x0ss.png",
        "slug": "metas",
        "title": "Transforme planos em metas",
        "subtitle": "Defina objetivos e acompanhe cada avanço.",
        "accent": "#8db2ff",
    },
    {
        "source": "0x0ss (3).png",
        "slug": "dividas",
        "title": "Organize dívidas e parcelas",
        "subtitle": "Visualize saldo devedor, compromissos e próximos vencimentos.",
        "accent": "#f2bc62",
    },
    {
        "source": "0x0ss (1).png",
        "slug": "investimentos",
        "title": "Acompanhe seu patrimônio",
        "subtitle": "Monitore aportes, resgates e a evolução dos investimentos.",
        "accent": "#b8a7ff",
    },
]


def display_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        ROOT / "app/web/public/fonts/bricolage-grotesque-variable.ttf",
        Path("C:/Windows/Fonts/seguisb.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def body_font(size: int, semibold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/seguisb.ttf") if semibold else Path("C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf") if semibold else Path("C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def interpolate_color(start: tuple[int, int, int], end: tuple[int, int, int], ratio: float) -> tuple[int, int, int]:
    return tuple(round(a + (b - a) * ratio) for a, b in zip(start, end))


def gradient_canvas(size: tuple[int, int], accent: str) -> Image.Image:
    width, height = size
    start = (7, 17, 31)
    end = (15, 38, 54)
    image = Image.new("RGB", size, start)
    pixels = image.load()
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = interpolate_color(start, end, ratio)
        for x in range(width):
            pixels[x, y] = color

    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    accent_rgb = tuple(int(accent[i : i + 2], 16) for i in (1, 3, 5))
    radius = round(min(size) * 0.42)
    center = (round(width * 0.82), round(height * 0.22))
    glow_draw.ellipse(
        (center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius),
        fill=(*accent_rgb, 72),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius // 2))
    return Image.alpha_composite(image.convert("RGBA"), glow)


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=font)[2] <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def rounded_screenshot(source: Path, target_width: int, radius: int) -> Image.Image:
    screenshot = Image.open(source).convert("RGB")
    target_height = round(screenshot.height * target_width / screenshot.width)
    screenshot = screenshot.resize((target_width, target_height), Image.Resampling.LANCZOS)
    mask = Image.new("L", screenshot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screenshot.width - 1, screenshot.height - 1), radius=radius, fill=255)
    screenshot.putalpha(mask)
    return screenshot


def paste_with_shadow(canvas: Image.Image, item: Image.Image, xy: tuple[int, int], radius: int, border: str = "#405469") -> None:
    x, y = xy
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x - 14, y + 20, x + item.width + 14, y + item.height + 48),
        radius=radius + 12,
        fill=(0, 0, 0, 155),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.alpha_composite(shadow)
    border_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(border_layer).rounded_rectangle(
        (x - 5, y - 5, x + item.width + 4, y + item.height + 4),
        radius=radius + 5,
        fill=border,
    )
    canvas.alpha_composite(border_layer)
    canvas.alpha_composite(item, xy)


def draw_brand(draw: ImageDraw.ImageDraw, icon: Image.Image, xy: tuple[int, int], icon_size: int, text_size: int) -> None:
    x, y = xy
    resized_icon = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    draw._image.alpha_composite(resized_icon, (x, y))
    font = display_font(text_size)
    text_y = y + (icon_size - draw.textbbox((0, 0), "HopeCash", font=font)[3]) // 2 - 2
    draw.text((x + icon_size + 18, text_y), "Hope", font=font, fill=WHITE)
    hope_width = draw.textbbox((0, 0), "Hope", font=font)[2]
    draw.text((x + icon_size + 18 + hope_width, text_y), "Cash", font=font, fill=MINT)


def make_phone(slide: dict[str, str], index: int, icon: Image.Image) -> Image.Image:
    canvas = gradient_canvas(PHONE_SIZE, slide["accent"])
    draw = ImageDraw.Draw(canvas)
    draw_brand(draw, icon, (70, 56), 58, 38)

    title_font = display_font(76)
    title_lines = wrap_text(draw, slide["title"], title_font, 940)
    y = 146
    for line in title_lines:
        draw.text((70, y), line, font=title_font, fill=WHITE)
        y += 76

    subtitle_font = body_font(31)
    subtitle_lines = wrap_text(draw, slide["subtitle"], subtitle_font, 920)
    y += 12
    for line in subtitle_lines[:2]:
        draw.text((72, y), line, font=subtitle_font, fill=SLATE)
        y += 43

    accent_rgb = tuple(int(slide["accent"][i : i + 2], 16) for i in (1, 3, 5))
    draw.rounded_rectangle((70, 392, 300, 400), radius=4, fill=(*accent_rgb, 255))

    screenshot = rounded_screenshot(SOURCE_DIR / slide["source"], 660, 44)
    screen_x = (PHONE_SIZE[0] - screenshot.width) // 2
    screen_y = 438
    paste_with_shadow(canvas, screenshot, (screen_x, screen_y), 44)

    draw.rounded_rectangle((914, 74, 1005, 116), radius=21, fill=NAVY_RAISED, outline=slide["accent"], width=2)
    draw.text((944, 80), f"{index:02d}", font=body_font(22, semibold=True), fill=slide["accent"])
    return canvas.convert("RGB")


def make_tablet(slide: dict[str, str], companion: dict[str, str], index: int, icon: Image.Image, dual: bool) -> Image.Image:
    canvas = gradient_canvas(TABLET_SIZE, slide["accent"])
    draw = ImageDraw.Draw(canvas)
    draw_brand(draw, icon, (104, 76), 66, 44)

    title_font = display_font(88)
    title_lines = wrap_text(draw, slide["title"], title_font, 700)
    y = 270
    for line in title_lines:
        draw.text((108, y), line, font=title_font, fill=WHITE)
        y += 92

    subtitle_font = body_font(34)
    subtitle_lines = wrap_text(draw, slide["subtitle"], subtitle_font, 660)
    y += 26
    for line in subtitle_lines[:3]:
        draw.text((112, y), line, font=subtitle_font, fill=SLATE)
        y += 48

    accent_rgb = tuple(int(slide["accent"][i : i + 2], 16) for i in (1, 3, 5))
    draw.rounded_rectangle((110, 760, 430, 772), radius=6, fill=(*accent_rgb, 255))
    draw.text((112, 814), "Organize hoje. Conquiste amanhã.", font=body_font(28, semibold=True), fill=WHITE)

    primary_width = 402 if not dual else 360
    primary = rounded_screenshot(SOURCE_DIR / slide["source"], primary_width, 34)
    primary_y = (TABLET_SIZE[1] - primary.height) // 2 + (20 if dual else 0)
    primary_x = 1260 if not dual else 1400
    paste_with_shadow(canvas, primary, (primary_x, primary_y), 34)

    if dual:
        secondary = rounded_screenshot(SOURCE_DIR / companion["source"], 310, 30)
        secondary_x = 1040
        secondary_y = (TABLET_SIZE[1] - secondary.height) // 2 + 82
        paste_with_shadow(canvas, secondary, (secondary_x, secondary_y), 30, border="#26394b")

    draw.rounded_rectangle((1696, 76, 1815, 124), radius=24, fill=NAVY_RAISED, outline=slide["accent"], width=2)
    draw.text((1734, 84), f"{index:02d}", font=body_font(25, semibold=True), fill=slide["accent"])
    return canvas.convert("RGB")


def make_feature(icon: Image.Image) -> Image.Image:
    background = Image.open(ASSET_DIR / "feature-background.png").convert("RGB")
    source_ratio = background.width / background.height
    target_ratio = FEATURE_SIZE[0] / FEATURE_SIZE[1]
    if source_ratio > target_ratio:
        crop_width = round(background.height * target_ratio)
        left = (background.width - crop_width) // 2
        background = background.crop((left, 0, left + crop_width, background.height))
    else:
        crop_height = round(background.width / target_ratio)
        top = (background.height - crop_height) // 2
        background = background.crop((0, top, background.width, top + crop_height))
    canvas = background.resize(FEATURE_SIZE, Image.Resampling.LANCZOS).convert("RGBA")

    shade = Image.new("RGBA", FEATURE_SIZE, (0, 0, 0, 0))
    shade_pixels = shade.load()
    for x in range(FEATURE_SIZE[0]):
        alpha = max(0, round(190 * (1 - x / 720)))
        for y in range(FEATURE_SIZE[1]):
            shade_pixels[x, y] = (7, 17, 31, alpha)
    canvas = Image.alpha_composite(canvas, shade)

    draw = ImageDraw.Draw(canvas)
    feature_icon = icon.resize((118, 118), Image.Resampling.LANCZOS)
    canvas.alpha_composite(feature_icon, (82, 128))
    name_font = display_font(74)
    draw.text((230, 128), "Hope", font=name_font, fill=WHITE)
    hope_width = draw.textbbox((0, 0), "Hope", font=name_font)[2]
    draw.text((230 + hope_width, 128), "Cash", font=name_font, fill=MINT)
    draw.text((230, 220), "Organize hoje.", font=display_font(42), fill=WHITE)
    draw.text((230, 268), "Conquiste amanhã.", font=display_font(42), fill=MINT)
    draw.rounded_rectangle((230, 340, 492, 348), radius=4, fill=MINT)
    return canvas.convert("RGB")


def save_png(image: Image.Image, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, format="PNG", optimize=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    missing = [str(SOURCE_DIR / slide["source"]) for slide in SLIDES if not (SOURCE_DIR / slide["source"]).exists()]
    if missing:
        raise SystemExit("Capturas de origem ausentes:\n" + "\n".join(missing))

    icon_source = ROOT / "app/web/icons/Icon-maskable-512.png"
    if not icon_source.exists():
        raise SystemExit(f"Ícone de origem ausente: {icon_source}")
    if not (ASSET_DIR / "feature-background.png").exists():
        raise SystemExit("Fundo do recurso gráfico ausente")

    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    for directory in ("phone", "tablet-7", "tablet-10"):
        (OUTPUT_DIR / directory).mkdir(parents=True, exist_ok=True)

    icon = Image.open(icon_source).convert("RGBA")
    save_png(icon.convert("RGB"), OUTPUT_DIR / "icon-512.png")
    save_png(make_feature(icon), OUTPUT_DIR / "feature-graphic-1024x500.png")

    for index, slide in enumerate(SLIDES, start=1):
        filename = f"{index:02d}-{slide['slug']}.png"
        companion = SLIDES[index % len(SLIDES)]
        save_png(make_phone(slide, index, icon), OUTPUT_DIR / "phone" / filename)
        save_png(make_tablet(slide, companion, index, icon, dual=False), OUTPUT_DIR / "tablet-7" / filename)
        save_png(make_tablet(slide, companion, index, icon, dual=True), OUTPUT_DIR / "tablet-10" / filename)

    records = []
    for path in sorted(OUTPUT_DIR.rglob("*.png")):
        with Image.open(path) as image:
            records.append(
                {
                    "file": path.relative_to(OUTPUT_DIR).as_posix(),
                    "width": image.width,
                    "height": image.height,
                    "bytes": path.stat().st_size,
                    "sha256": sha256(path),
                }
            )
    (OUTPUT_DIR / "manifest.json").write_text(
        json.dumps({"generated": "2026-08-14", "files": records}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Gerados {len(records)} arquivos PNG em {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
