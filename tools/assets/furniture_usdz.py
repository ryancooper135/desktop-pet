"""Мебель комнаты из glb в usdz (волна 53): цветок в горшке, мишка и книжки на полке — Kenney Furniture Kit (CC0).

У Kenney в одном glb несколько узлов со своими трансформами и несколько примитивов — по одному на материал
(плоские цвета без текстур). Приложению нужен один меш (PetProps берёт первый ModelEntity), поэтому:
  - вершины всех примитивов переводим в мировые координаты (трансформы узлов запекаем) и сливаем в один меш;
  - каждый материал glb становится GeomSubset со своим UsdPreviewSurface — в RealityKit это части меша
    со своими материалами;
  - цвета перекрашиваем в пастель стиля B (--color имя=RRGGBB, имя — материал в glb);
  - высота — --height метров, низ на y=0, середина по x/z в нуле.

    python -P tools/assets/furniture_usdz.py <pottedPlant.glb> app/Resources/Room/plant.usdz --height 0.16 \
        --color wood=FFB892 --color woodDark=F29E7C --color plant=8ADBBD

Проверка: треугольники ≤ 2000, файл ≤ 120 КБ, ARKit-совместимость. Код выхода 1, если не прошло.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import Glb, globals_from_local, qmat  # noqa: E402
from props_usdz import compliance  # noqa: E402

MAX_TRIS = 2000
MAX_BYTES = 120 * 1024


def local_mat(n: dict) -> np.ndarray:
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    r = np.array(n.get("rotation", [0, 0, 0, 1]), dtype=np.float64)
    m[:3, :3] = qmat(r) @ np.diag(n.get("scale", [1, 1, 1]))
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def read(g: Glb) -> tuple[np.ndarray, np.ndarray, list[tuple[str, np.ndarray, tuple]]]:
    """Все треугольники в мировых координатах: точки, нормали и куски по материалам (имя, индексы, цвет)."""
    j = g.j
    nodes = j["nodes"]
    parents = [-1] * len(nodes)
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parents[c] = i
    world = globals_from_local([local_mat(n) for n in nodes], parents)
    pts, nrm, parts = [], [], {}
    base = 0
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        w = world[i]
        nm = np.linalg.inv(w[:3, :3]).T
        for p in j["meshes"][n["mesh"]]["primitives"]:
            a = p["attributes"]
            v = g.accessor(a["POSITION"]).astype(np.float64)
            v = (w[:3, :3] @ v.T).T + w[:3, 3]
            if "NORMAL" in a:
                nn = (nm @ g.accessor(a["NORMAL"]).astype(np.float64).T).T
                nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
            else:
                nn = np.zeros_like(v)
            idx = g.accessor(p["indices"]).reshape(-1).astype(np.int64) + base
            mat = j["materials"][p["material"]] if "material" in p else {"name": "default"}
            name = mat.get("name", f"m{p.get('material', 0)}")
            col = tuple(mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.8, 0.8, 0.8, 1])[:3])
            prev = parts.get(name)
            parts[name] = (np.concatenate([prev[0], idx]) if prev else idx, col)
            pts.append(v)
            nrm.append(nn)
            base += len(v)
    return np.concatenate(pts), np.concatenate(nrm), [(k, v[0], v[1]) for k, v in parts.items()]


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_color(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))


def safe(name: str) -> str:
    s = "".join(ch if ch.isalnum() else "_" for ch in name)
    return s if s and not s[0].isdigit() else "m_" + s


def write(src: Path, out: Path, height: float, colors: dict[str, tuple]) -> dict:
    pts, nrm, parts = read(Glb.load(str(src)))
    lo, hi = pts.min(0), pts.max(0)
    k = height / float(hi[1] - lo[1])
    c = (lo + hi) / 2
    pts = (pts - np.array([c[0], lo[1], c[2]])) * k
    lo, hi = pts.min(0), pts.max(0)
    tris = sum(len(p[1]) for p in parts) // 3
    name = safe(out.stem.capitalize())
    with tempfile.TemporaryDirectory() as tmp:
        usdc = Path(tmp) / f"{out.stem}.usdc"
        stage = Usd.Stage.CreateNew(str(usdc))
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1.0)
        root = UsdGeom.Xform.Define(stage, "/Root")
        stage.SetDefaultPrim(root.GetPrim())
        mesh = UsdGeom.Mesh.Define(stage, f"/Root/{name}")
        mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, v)) for v in pts]))
        all_idx = np.concatenate([p[1] for p in parts])
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * tris))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray([int(i) for i in all_idx]))
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, lo)), Gf.Vec3f(*map(float, hi))]))
        mesh.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, v)) for v in nrm]))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim())
        face = 0
        used = []
        for pname, idx, col in parts:
            n = len(idx) // 3
            rgb = colors.get(pname, tuple(float(x) for x in col))
            mname = safe(pname)
            mat = UsdShade.Material.Define(stage, f"/Root/Materials/{mname}")
            sh = UsdShade.Shader.Define(stage, f"/Root/Materials/{mname}/Surface")
            sh.CreateIdAttr("UsdPreviewSurface")
            sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(1.0)
            sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
            sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*map(float, rgb)))
            mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
            sub = UsdGeom.Subset.Define(stage, f"/Root/{name}/{mname}")
            sub.CreateElementTypeAttr(UsdGeom.Tokens.face)
            sub.CreateFamilyNameAttr(UsdShade.Tokens.materialBind)
            sub.CreateIndicesAttr(Vt.IntArray(list(range(face, face + n))))
            UsdShade.MaterialBindingAPI.Apply(sub.GetPrim()).Bind(mat)
            face += n
            used.append(pname)
        UsdGeom.Subset.SetFamilyType(mesh, UsdShade.Tokens.materialBind, UsdGeom.Tokens.partition)
        stage.GetRootLayer().Save()
        out.parent.mkdir(parents=True, exist_ok=True)
        dst = str(out.resolve())
        cwd = os.getcwd()
        os.chdir(tmp)
        try:
            ok = UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(usdc.name), dst)
        finally:
            os.chdir(cwd)
        if not ok:
            raise RuntimeError("usdz не собрался")
    errors = compliance(out)
    size = out.stat().st_size
    return {"file": str(out), "bytes": size, "tris": tris, "verts": int(len(pts)), "scale": round(k, 5),
            "extent_m": [round(float(x), 4) for x in (hi - lo)], "materials": used, "arkit_errors": errors,
            "ok": tris <= MAX_TRIS and size <= MAX_BYTES and not errors}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--height", type=float, required=True)
    ap.add_argument("--color", action="append", default=[], help="материал=RRGGBB (sRGB)")
    a = ap.parse_args()
    colors = {}
    for s in a.color:
        k, v = s.split("=", 1)
        colors[k] = hex_color(v)
    rep = write(Path(a.src), Path(a.out), a.height, colors)
    print(json.dumps(rep, ensure_ascii=False))
    sys.exit(0 if rep["ok"] else 1)


if __name__ == "__main__":
    main()
