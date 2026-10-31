"""Пастельный паркет «ёлочкой» для пола комнаты (волна 53) из WoodFloor036 (ambientCG, CC0).

Берём только карту цвета 1K, по яркости перекрашиваем в персиково-розовую пастель стиля B и
подчёркиваем стыки досок (локальный контраст), чтобы ёлочка читалась на маленьком экране.
Тайл бесшовный — приложение повторяет его по полу (PetRoom.floorImage).

    python -I tools/assets/floor_pastel.py <WoodFloor036_1K-JPG_Color.jpg> app/Resources/Room/floor_herringbone.jpg
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

DARK = np.array([0xF2, 0xB8, 0xA0], float)   # стыки и тёмные доски
MID = np.array([0xFF, 0xD9, 0xC7], float)
LIGHT = np.array([0xFF, 0xEE, 0xE4], float)


def main(src: str, out: str, size: int = 512) -> None:
    im = Image.open(src).convert("L").resize((size, size), Image.LANCZOS)
    lum = np.asarray(im, float) / 255
    blur = np.asarray(im.filter(ImageFilter.GaussianBlur(size / 24)), float) / 255
    detail = lum - blur                       # стыки и волокна
    tone = (blur - blur.mean()) / (blur.std() + 1e-6)
    t = np.clip(0.55 + 0.24 * tone + 7.0 * detail, 0, 1)[..., None]
    rgb = np.where(t < 0.5, DARK + (MID - DARK) * (t / 0.5), MID + (LIGHT - MID) * ((t - 0.5) / 0.5))
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(out, quality=86, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
