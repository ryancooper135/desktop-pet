"""Превью поз без Blender и без GPU: скиннинг + растеризация на numpy → PNG-лист.

Нужен, чтобы проверить сгенерированные позы (сидеть/лежать/спать) на ПК или в CI,
где нет ни Mac, ни видеокарты.

    python tools/assets/preview.py build/shiba_clips.glb --clips build/clips.json --out build/preview.png
    python tools/assets/preview.py tools/assets/source/shiba.glb --anim Idle --anim Death --out x.png

Контактный лист: строки «клип × вид», 8 кадров от начала до конца, красная линия — пол
(низ меша в кадре 0 idle), рядом <out>.txt с подписями строк:
    python tools/assets/preview.py build/shiba_clips.glb --clips build/clips.json --only sit_in --only eat \
        --frames 8 --view side:90 --view 3q:35 --out build/contact.png

Крупный план (камера едет за костью в каждом кадре, радиус кадра в метрах модели):
    python tools/assets/preview.py build/shiba_clips.glb --clips build/clips.json --only yawn         --focus Jaw --radius 0.5 --out build/mouth.png
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import Glb, globals_from_local, sample_track, trs_mat  # noqa: E402


def write_png(path: str, rgb: np.ndarray) -> None:
    h, w, _ = rgb.shape
    raw = b"".join(b"\0" + rgb[y].astype(np.uint8).tobytes() for y in range(h))

    def chunk(t: bytes, d: bytes) -> bytes:
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def lin2srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


class Model:
    def __init__(self, g: Glb):
        self.g = g
        self.parents = g.parents()
        self.rest = g.rest_trs()
        skin = g.j["skins"][0]
        self.joints = skin["joints"]
        self.ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        self.prims = []
        for p in g.j["meshes"][0]["primitives"]:
            a = p["attributes"]
            pos = g.accessor(a["POSITION"])
            idx = g.accessor(p["indices"])[:, 0].reshape(-1, 3)
            jn = g.accessor(a["JOINTS_0"]).astype(int)
            wt = g.accessor(a["WEIGHTS_0"])
            wt = wt / np.maximum(wt.sum(1, keepdims=True), 1e-9)
            mat = g.j["materials"][p.get("material", 0)] if g.j.get("materials") else {}
            col = np.array(mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.8, 0.8, 0.8, 1])[:3])
            self.prims.append((pos, idx, jn, wt, col))

    def pose_locals(self, tracks: dict | None, t: float) -> list[np.ndarray]:
        loc = []
        for i, (tr, rot, sc) in enumerate(self.rest):
            if tracks:
                if (i, "translation") in tracks:
                    tt, vv, ip = tracks[(i, "translation")]
                    tr = sample_track(tt, vv, t, "translation", ip)
                if (i, "rotation") in tracks:
                    tt, vv, ip = tracks[(i, "rotation")]
                    rot = sample_track(tt, vv, t, "rotation", ip)
                if (i, "scale") in tracks:
                    tt, vv, ip = tracks[(i, "scale")]
                    sc = sample_track(tt, vv, t, "scale", ip)
            loc.append(trs_mat(tr, rot, sc))
        return loc

    def skinned(self, locals_: list[np.ndarray]):
        G = globals_from_local(locals_, self.parents)
        M = np.stack([G[j] for j in self.joints]) @ self.ibm  # (J,4,4)
        out = []
        for pos, idx, jn, wt, col in self.prims:
            ph = np.c_[pos, np.ones(len(pos))]
            v = np.zeros((len(pos), 3))
            for k in range(4):
                v += wt[:, k:k + 1] * np.einsum("nij,nj->ni", M[jn[:, k]], ph)[:, :3]
            out.append((v, idx, col))
        return out


def render(meshes, size: int, yaw_deg: float, pitch_deg: float, bounds, bg=(236, 230, 220),
           floor_y: float = 0.0, floor_line: bool = False) -> np.ndarray:
    W = H = size
    img = np.zeros((H, W, 3)) + np.array(bg)
    zbuf = np.full((H, W), -np.inf)
    cy, sy = np.cos(np.radians(yaw_deg)), np.sin(np.radians(yaw_deg))
    cp, sp = np.cos(np.radians(pitch_deg)), np.sin(np.radians(pitch_deg))
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    R = Rx @ Ry
    center, radius = bounds
    scale = (size * 0.46) / radius
    light = np.array([0.4, 0.8, 0.6])
    light /= np.linalg.norm(light)
    # пол: ниже — темнее; floor_line — красная линия поверх (видно, где лапы уходят в пол)
    floor = ((np.array([[0, floor_y, 0]]) - center) @ R.T)[0]
    fy = int(H / 2 - floor[1] * scale)
    if 0 <= fy < H:
        img[fy:, :] = img[fy:, :] * 0.93
    for v, idx, col in meshes:
        pv = (v - center) @ R.T
        sx = W / 2 + pv[:, 0] * scale
        sy_ = H / 2 - pv[:, 1] * scale
        sz = pv[:, 2]
        tri = v[idx]
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        shade = 0.5 + 0.5 * np.abs(n @ light)
        base = lin2srgb(col) * 255
        for f, (a, b, c) in enumerate(idx):
            x0, y0, x1, y1, x2, y2 = sx[a], sy_[a], sx[b], sy_[b], sx[c], sy_[c]
            area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if abs(area) < 1e-9:
                continue
            minx, maxx = int(max(min(x0, x1, x2), 0)), int(min(max(x0, x1, x2) + 1, W))
            miny, maxy = int(max(min(y0, y1, y2), 0)), int(min(max(y0, y1, y2) + 1, H))
            if minx >= maxx or miny >= maxy:
                continue
            gx, gy = np.meshgrid(np.arange(minx, maxx) + 0.5, np.arange(miny, maxy) + 0.5)
            w0 = ((x1 - gx) * (y2 - gy) - (x2 - gx) * (y1 - gy)) / area
            w1 = ((x2 - gx) * (y0 - gy) - (x0 - gx) * (y2 - gy)) / area
            w2 = 1 - w0 - w1
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not inside.any():
                continue
            z = w0 * sz[a] + w1 * sz[b] + w2 * sz[c]
            zb = zbuf[miny:maxy, minx:maxx]
            m = inside & (z > zb)
            zb[m] = z[m]
            img[miny:maxy, minx:maxx][m] = base * shade[f]
    if floor_line and 0 <= fy < H and pitch_deg == 0:
        img[fy, :] = (220, 40, 40)  # при pitch 0 пол — прямая; иначе линия по краю пола врёт
    elif floor_line and 0 <= fy < H:
        img[fy, ::3] = (220, 40, 40)
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("--clips", help="clips.json от build_clips.py (тогда в GLB одна анимация)")
    ap.add_argument("--anim", action="append", default=[], help="имя анимации исходного GLB (можно несколько)")
    ap.add_argument("--only", action="append", default=[], help="только эти клипы из clips.json")
    ap.add_argument("--cols", "--frames", type=int, default=5, help="кадров на строку (от начала до конца клипа)")
    ap.add_argument("--view", action="append", default=[], help="вид «имя:yaw», можно несколько: строки клип × вид")
    ap.add_argument("--size", type=int, default=180)
    ap.add_argument("--yaw", type=float, default=60, help="0 — спереди, 90 — сбоку")
    ap.add_argument("--pitch", type=float, default=12)
    ap.add_argument("--focus", help="крупный план: центр кадра — эта кость (в каждом кадре своя позиция)")
    ap.add_argument("--radius", type=float, default=0.5, help="с --focus: полуразмер кадра")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    g = Glb.load(args.glb)
    model = Model(g)
    rows = []  # (label, tracks, start, end)
    floor_y, floor_line = 0.0, False
    if args.clips:
        clips = json.loads(Path(args.clips).read_text(encoding="utf-8"))["clips"]
        tracks = g.animation_tracks(g.j["animations"][0])
        missing = [n for n in args.only if n not in clips]
        if missing:
            raise SystemExit(f"нет клипов в clips.json: {missing}")
        names = [n for n in args.only if n in clips] if args.only else list(clips)
        for name in names:  # порядок — как в --only
            c = clips[name]
            rows.append((name, tracks, c["start"], c["end"]))
        if "idle" in clips:  # пол = низ меша в кадре 0 idle (как в build_clips --check)
            idle0 = model.skinned(model.pose_locals(tracks, clips["idle"]["start"]))
            floor_y, floor_line = float(min(v[:, 1].min() for v, _, _ in idle0)), True
    else:
        names = args.anim or [a["name"] for a in g.j.get("animations", [])]
        for name in names:
            a = next(x for x in g.j["animations"] if x["name"] == name)
            tr = g.animation_tracks(a)
            end = max(float(t[-1]) for t, _, _ in tr.values())
            rows.append((name, tr, 0.0, end))
    if not rows:
        rows.append(("rest", None, 0.0, 0.0))

    # общий масштаб по позе покоя: радиус по вершинам
    rest_mesh = model.skinned(model.pose_locals(None, 0))
    allv = np.concatenate([m[0] for m in rest_mesh])
    lo, hi = allv.min(0), allv.max(0)
    center = (lo + hi) / 2
    center[1] = (hi[1] + 0) / 2
    radius = float(np.linalg.norm(hi - lo)) / 2 * 1.05
    views = []
    for v in args.view or [f"yaw{args.yaw:g}:{args.yaw}"]:
        nm, _, yaw = v.rpartition(":")
        views.append((nm or f"yaw{yaw}", float(yaw)))
    S = args.size
    nrows = len(rows) * len(views)
    focus = g.node_index(args.focus) if args.focus else None
    sheet = np.zeros((nrows * S, args.cols * S, 3)) + 255
    legend = []
    r = 0
    for label, tr, t0, t1 in rows:
        times = [t0 + (t1 - t0) * (c / max(args.cols - 1, 1)) for c in range(args.cols)]
        locs = [model.pose_locals(tr, t) for t in times]
        meshes = [model.skinned(lc) for lc in locs]
        cams = [(center, radius) if focus is None else
                (globals_from_local(lc, model.parents)[focus][:3, 3], args.radius) for lc in locs]
        for vname, yaw in views:
            for c, m in enumerate(meshes):
                sheet[r * S:(r + 1) * S, c * S:(c + 1) * S] = render(
                    m, S, yaw, args.pitch, cams[c], floor_y=floor_y, floor_line=floor_line and focus is None)
            sheet[r * S, :] = 120
            legend.append(f"строка {r + 1}: {label} · {vname} (yaw {yaw:g}°) · {t0:.3f}-{t1:.3f} с · "
                          f"кадры {', '.join(f'{t - t0:.2f}' for t in times)}")
            r += 1
        print(f"{label}: {t0:.3f}-{t1:.3f} s")
    for c in range(1, args.cols):
        sheet[:, c * S] = 200
    write_png(args.out, sheet)
    Path(args.out).with_suffix(".txt").write_text(
        f"{Path(args.out).name}: {args.cols} кадров на строку, красная линия — пол\n" + "\n".join(legend) + "\n",
        encoding="utf-8")
    print("->", args.out)


if __name__ == "__main__":
    main()
