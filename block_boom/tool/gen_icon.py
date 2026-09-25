"""Рисует иконку приложения (обычную и адаптивную) для всех плотностей экрана.

Запуск из корня проекта:  python3 tool/gen_icon.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), '..')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
SS = 4  # суперсэмплинг для сглаживания

BG_TOP = (84, 104, 255)
BG_BOTTOM = (38, 22, 120)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def lighten(c, t):
    return lerp(c, (255, 255, 255), t)


def darken(c, t):
    return lerp(c, (0, 0, 0), t)


def gradient_bg(size):
    img = Image.new('RGBA', (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / size) + (255,))
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = size * 0.42
    cx, cy = size * 0.5, size * 0.45
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(160, 120, 255, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    return Image.alpha_composite(img, glow)


def block(d, x, y, s, col):
    """Блок с фаской, как в игре (стиль «Классика»)."""
    b = s * 0.16
    r = s * 0.14
    mask = Image.new('L', (int(s), int(s)), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=255)
    tile = Image.new('RGBA', (int(s), int(s)), col + (255,))
    td = ImageDraw.Draw(tile)
    L, T, R, B = 0, 0, s, s
    td.polygon([(L, T), (R, T), (R - b, T + b), (L + b, T + b)], fill=lighten(col, 0.4))
    td.polygon([(L, T), (L + b, T + b), (L + b, B - b), (L, B)], fill=lighten(col, 0.16))
    td.polygon([(R, T), (R, B), (R - b, B - b), (R - b, T + b)], fill=darken(col, 0.15))
    td.polygon([(L, B), (L + b, B - b), (R - b, B - b), (R, B)], fill=darken(col, 0.32))
    td.rectangle([L + b, T + b, R - b, B - b], fill=lighten(col, 0.06))
    td.rounded_rectangle([L + b * 1.3, T + b * 1.3, L + b * 1.3 + s * 0.22, T + b * 1.3 + s * 0.09],
                         radius=s * 0.045, fill=lighten(col, 0.75))
    d.paste(tile, (int(x), int(y)), mask)


def star(cx, cy, r_out, r_in, n, rot=0.0):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + math.pi * i / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def foreground(size, scale=1.0):
    """Фигура-«взрыв» из блоков. scale<1 — для адаптивной иконки (safe zone)."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c = size / 2
    # вспышка за блоками
    burst = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(burst)
    bd.polygon(star(c, c, size * 0.47 * scale, size * 0.27 * scale, 9, -math.pi / 2),
               fill=(255, 214, 64, 255))
    bd.polygon(star(c, c, size * 0.36 * scale, size * 0.22 * scale, 9, -math.pi / 2 + 0.35),
               fill=(255, 150, 40, 255))
    glow = burst.filter(ImageFilter.GaussianBlur(size * 0.03))
    img = Image.alpha_composite(img, glow)
    img = Image.alpha_composite(img, burst)

    # тень под блоками
    s = size * 0.2 * scale
    cells = [(-1, -1, (255, 77, 94)), (0, -1, (255, 154, 46)), (1, -1, (255, 210, 63)),
             (0, 0, (61, 220, 132)), (0, 1, (74, 123, 255))]
    ox, oy = c - s / 2, c - s / 2
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for dx, dy, _ in cells:
        x, y = ox + dx * s, oy + dy * s + s * 0.12
        sd.rounded_rectangle([x, y, x + s, y + s], radius=s * 0.14, fill=(20, 8, 60, 150))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(s * 0.12)))
    d = img
    for dx, dy, col in cells:
        block(d, ox + dx * s, oy + dy * s, s, col)
    # искры
    sp = ImageDraw.Draw(img)
    for (fx, fy, fr) in [(0.2, 0.22, 0.05), (0.8, 0.74, 0.04), (0.78, 0.2, 0.03)]:
        sx = c + (fx - 0.5) * size * scale * 1.3
        sy = c + (fy - 0.5) * size * scale * 1.3
        sp.polygon(star(sx, sy, size * fr * scale, size * fr * scale * 0.3, 4), fill=(255, 255, 255, 255))
    return img


def rounded(img, radius_frac):
    size = img.size[0]
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=size * radius_frac, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def save(img, path, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(path)


if __name__ == '__main__':
    big = 512 * SS
    legacy = rounded(Image.alpha_composite(gradient_bg(big), foreground(big, 0.92)), 0.22)
    adaptive_bg = gradient_bg(big)
    adaptive_fg = foreground(big, 0.62)

    dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, k in dens.items():
        folder = os.path.join(RES, f'mipmap-{name}')
        save(legacy, os.path.join(folder, 'ic_launcher.png'), int(48 * k))
        save(adaptive_fg, os.path.join(folder, 'ic_launcher_foreground.png'), int(108 * k))
        save(adaptive_bg, os.path.join(folder, 'ic_launcher_background.png'), int(108 * k))
    save(legacy, os.path.join(ROOT, 'assets', 'icon', 'icon.png'), 512)

    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    print('ok')
