"""Порода Quaternius → исходник в раскладке Шибы (волна 58): тот же порядок материалов, что ждёт приложение.

Приложение узнаёт части пса по номеру материала (PetRoom.shibaMaterials, PetRig: 0–1 шерсть, 3…5 глаза):
Main, Main_Light, Black, Eyes_White, Eyes_Pupil, Eyes_Black (+ Tongue из mouth.py). У Хаски из Quaternius
материалы безымянные («Material.00x») и нет радужки — здесь переименовываем, ставим в нужный порядок и
делаем радужку из диска зрачка: тот же диск шире, чуть впереди белка, а зрачок — ещё чуть впереди радужки.

    python -I tools/assets/normalize_breed.py <husky.glb из Quaternius> tools/assets/source/husky.glb --breed husky

Скелет, анимации и сетка шерсти не меняются; дальше — обычный build_clips.py.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import COMP, NCOMP, Glb  # noqa: E402

ORDER = ["Main", "Main_Light", "Black", "Eyes_White", "Eyes_Pupil", "Eyes_Black"]

# Имя материала в исходнике → имя Шибы. None для Eyes_Pupil — сделать из Eyes_Black.
BREEDS = {
    "husky": {
        "mesh": "Husky",
        "materials": {"Material": "Main", "Material.001": "Main_Light", "Material.006": "Black",
                      "Material.003": "Eyes_White", "Material.002": "Eyes_Black"},
    },
}

IRIS_SCALE = 1.35     # радиус радужки — в радиусах зрачка (у Хаски глазница меньше, шире — радужка вылезает)
IRIS_LIFT = 0.06      # радужка впереди белка (у Хаски белок — кольцо в той же поверхности), в радиусах зрачка
PUPIL_LIFT = 0.12     # зрачок впереди радужки
IRIS_COLOR = [0.0248497445136309, 0.0146784102544188, 0.00593237252905965, 1.0]  # как у Шибы; в приложении — EyeStyle


def _append(g: Glb, arr: np.ndarray, comp: int, typ: str, minmax: bool = False) -> int:
    dt = np.dtype(COMP[comp])
    data = np.ascontiguousarray(arr.astype(dt)).tobytes()
    pad = (-len(g.bin)) % 4
    off = len(g.bin) + pad
    g.bin = bytes(g.bin) + b"\0" * pad + data
    g.j["buffers"][0]["byteLength"] = len(g.bin)
    g.j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
    acc = {"bufferView": len(g.j["bufferViews"]) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
    if minmax:
        a2 = arr.reshape(arr.shape[0], -1)
        acc["min"] = [float(x) for x in a2.min(0)]
        acc["max"] = [float(x) for x in a2.max(0)]
    g.j["accessors"].append(acc)
    assert NCOMP[typ] == (arr.shape[1] if arr.ndim > 1 else 1)
    return len(g.j["accessors"]) - 1


def lift_disk(pos: np.ndarray, nrm: np.ndarray, scale: float, lift: float) -> np.ndarray:
    """Диск зрачка каждого глаза (по знаку X): шире в scale раз в плоскости глаза и на lift его радиусов
    вперёд по нормали."""
    out = pos.copy()
    for side in (1.0, -1.0):
        sel = pos[:, 0] * side > 0
        if not sel.any():
            continue
        q = pos[sel]
        c = q.mean(0)
        n = nrm[sel].mean(0)
        n /= np.linalg.norm(n)
        d = q - c
        along = d @ n
        flat = d - along[:, None] * n
        r = np.linalg.norm(flat, axis=1).max()
        out[sel] = c + flat * scale + (along + lift * r)[:, None] * n
    return out


def _accessor_kind(g: Glb, i: int) -> tuple[int, str]:
    a = g.j["accessors"][i]
    return a["componentType"], a["type"]


def normalize(g: Glb, breed: str) -> dict:
    spec = BREEDS[breed]
    j = g.j
    if len(j["meshes"]) != 1:
        raise ValueError(f"ждали один меш, а их {len(j['meshes'])}")
    mesh = j["meshes"][0]
    src_names = [m.get("name") for m in j["materials"]]
    rename = spec["materials"]
    missing = [k for k in rename if k not in src_names]
    if missing:
        raise KeyError(f"нет материалов {missing} (есть {src_names})")
    prims_by = {}
    for p in mesh["primitives"]:
        nm = rename.get(src_names[p["material"]])
        if nm is None:
            raise KeyError(f"материал {src_names[p['material']]} без пары в раскладке Шибы")
        prims_by[nm] = p
    mats_by = {rename[n]: dict(j["materials"][i], name=rename[n]) for i, n in enumerate(src_names) if n in rename}

    if "Eyes_Pupil" not in prims_by:
        black = prims_by["Eyes_Black"]
        a = black["attributes"]
        pos = g.accessor(a["POSITION"])
        nrm = g.accessor(a["NORMAL"])
        attrs = dict(a)
        attrs["POSITION"] = _append(g, lift_disk(pos, nrm, IRIS_SCALE, IRIS_LIFT).astype(np.float32), 5126, "VEC3",
                                    minmax=True)
        black["attributes"] = dict(a, POSITION=_append(g, lift_disk(pos, nrm, 1.0, PUPIL_LIFT).astype(np.float32),
                                                       5126, "VEC3", minmax=True))
        p = {"attributes": attrs, "indices": black["indices"], "mode": black.get("mode", 4)}
        prims_by["Eyes_Pupil"] = p
        mats_by["Eyes_Pupil"] = {"name": "Eyes_Pupil", "pbrMetallicRoughness": {
            "baseColorFactor": IRIS_COLOR, "metallicFactor": 0.0, "roughnessFactor": 0.5}}

    j["materials"] = [mats_by[n] for n in ORDER]
    prims = []
    for k, n in enumerate(ORDER):
        p = prims_by[n]
        p["material"] = k
        prims.append(p)
    mesh["primitives"] = prims
    mesh["name"] = spec["mesh"]
    for nd in j["nodes"]:
        if nd.get("mesh") == 0:
            nd["name"] = spec["mesh"]
    tris = {n: j["accessors"][prims_by[n]["indices"]]["count"] // 3 for n in ORDER}
    return {"breed": breed, "materials": ORDER, "tris": tris, "total_tris": sum(tris.values())}


def save(g: Glb, path: str) -> None:
    g.j["buffers"][0]["byteLength"] = len(g.bin)
    js = json.dumps(g.j, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    bn = bytes(g.bin) + b"\0" * ((-len(g.bin)) % 4)
    total = 12 + 8 + len(js) + 8 + len(bn)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(bn), b"BIN\0") + bn)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--breed", default="husky", choices=sorted(BREEDS))
    a = ap.parse_args()
    g = Glb.load(a.src)
    rep = normalize(g, a.breed)
    save(g, a.out)
    print(json.dumps(rep, ensure_ascii=False))


if __name__ == "__main__":
    main()
