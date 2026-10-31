"""Листы превью волны 58 из рендеров render_previews.py (Pillow, без Blender).

  python tools/assets/preview_sheets.py build/w58/prev/raw design/wave58/png

Ждёт в raw: <breed>_{idle,sit,lie,sleep,paw}.png, <breed>_orig_idle.png, scene_shiba_idle.png, scene_husky_sit.png.
Пишет: shiba_poses.png, husky_poses.png, props_scene.png, style_compare.png, summary.png.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BG = "#F6F1EA"
INK = "#3B2F2A"
SOFT = "#8A7C72"
POSES = [("idle", "стоит"), ("sit", "сидит"), ("lie", "лежит"), ("sleep", "спит"), ("paw", "лапу")]
BREEDS = [("shiba", "Шиба"), ("husky", "Хаски")]


def font(size, bold=False):
    names = (["segoeuib.ttf", "DejaVuSans-Bold.ttf"] if bold else ["segoeui.ttf", "DejaVuSans.ttf"])
    for n in names:
        for d in ("C:/Windows/Fonts/", "/usr/share/fonts/truetype/dejavu/", ""):
            try:
                return ImageFont.truetype(d + n, size)
            except OSError:
                continue
    return ImageFont.load_default()


def tile(path, size):
    im = Image.open(path).convert("RGBA")
    box = im.getbbox() or (0, 0, im.width, im.height)
    return im, box


def crop_group(paths, pad=0.06):
    """Общая рамка для группы рендеров (одна камера) — размеры поз остаются сравнимыми."""
    ims = [Image.open(p).convert("RGBA") for p in paths]
    boxes = [im.getbbox() for im in ims if im.getbbox()]
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    p = int(max(x1 - x0, y1 - y0) * pad)
    x0, y0 = max(0, x0 - p), max(0, y0 - p)
    x1, y1 = min(ims[0].width, x1 + p), min(ims[0].height, y1 + p)
    return [im.crop((x0, y0, x1, y1)) for im in ims]


def fit(im, w, h):
    k = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)


def row_sheet(title, note, cells, cell=(300, 300)):
    """cells: [(image, подпись)] в один ряд."""
    cw, ch = cell
    W, H = 40 + len(cells) * (cw + 16) + 24, 110 + ch + 50
    out = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(out)
    d.text((40, 26), title, font=font(30, True), fill=INK)
    d.text((40, 66), note, font=font(17), fill=SOFT)
    for i, (im, cap) in enumerate(cells):
        x = 40 + i * (cw + 16)
        d.rounded_rectangle((x, 100, x + cw, 100 + ch), 18, fill="#FFFFFF")
        t = fit(im, cw - 24, ch - 24)
        out.alpha_composite(t, (x + (cw - t.width) // 2, 100 + (ch - t.height) // 2))
        tw = d.textlength(cap, font=font(18, True))
        d.text((x + (cw - tw) / 2, 110 + ch), cap, font=font(18, True), fill=INK)
    return out


def main():
    raw, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    sheets = {}
    for b, name in BREEDS:
        ims = crop_group([raw / f"{b}_{p}.png" for p, _ in POSES])
        s = row_sheet(f"{name} — позы", "Quaternius (CC0), стиль A; лапу — поверх «сидит»; во сне глаза закрыты, как в приложении",
                      [(im, cap) for im, (_, cap) in zip(ims, POSES)])
        s.convert("RGB").save(out / f"{b}_poses.png", optimize=True)
        sheets[b] = s

    scenes = crop_group([raw / "scene_shiba_idle.png"]) + crop_group([raw / "scene_husky_sit.png"])
    s = row_sheet("Миска и мячик в комнате",
                  "«Dog bowl» и «Tennis ball» — Poly by Google (CC-BY 3.0); масштаб и места как в комнате, миска чёрная (матовый графит)",
                  [(scenes[0], "Шиба у миски"), (scenes[1], "Хаски сидит")], cell=(460, 460))
    s.convert("RGB").save(out / "props_scene.png", optimize=True)
    sheets["props"] = s

    cells = []
    for b, name in BREEDS:
        a, o = crop_group([raw / f"{b}_idle.png", raw / f"{b}_orig_idle.png"])
        cells += [(a, f"{name}: стиль A"), (o, f"{name}: цвета Quaternius")]
    s = row_sheet("Стиль A против исходных цветов",
                  "Слева в паре — как в приложении сейчас; справа — модель Quaternius как скачана. Выбор за Вадимом.",
                  cells, cell=(330, 330))
    s.convert("RGB").save(out / "style_compare.png", optimize=True)

    parts = [sheets["shiba"], sheets["husky"], sheets["props"]]
    W = max(p.width for p in parts)
    H = 90 + sum(p.height for p in parts)
    summ = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(summ)
    d.text((40, 30), "Волна 58 · пёс и вещи комнаты", font=font(36, True), fill=INK)
    y = 90
    for p in parts:
        summ.alpha_composite(p, ((W - p.width) // 2, y))
        y += p.height
    summ.convert("RGB").save(out / "summary.png", optimize=True)
    for f in sorted(out.glob("*.png")):
        print(f.name, f.stat().st_size)


if __name__ == "__main__":
    main()
