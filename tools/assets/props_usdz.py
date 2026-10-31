"""Вещи комнаты из glb в usdz (волна 58): миска «Dog bowl» и мяч «Tennis ball» (Poly by Google, CC-BY 3.0).

Пишем usdz напрямую через usd-core (pxr), без Blender: у вещи один меш без скелета, а приложению нужен меш
в метрах, Y вверх, без своего трансформа — сцена берёт из файла только MeshResource и материал (PetProps) и
ставит его в ту же точку, где раньше стоял примитив. Поэтому размер запекаем в вершины:
  - миска — радиус по полу 0,09 м и высота ~0,05 м, середина в нуле (как generateCylinder(0.05, 0.09));
  - мяч — радиус 0,05 м, центр в нуле (как generateSphere(0.05), RoomPlan.Keep.ballRadius).
Материал: UsdPreviewSurface, матовый. У мяча — текстура из glb (PNG 256×256), у миски — матовый графит
(оригинал чистый чёрный; в приложении всё равно матовый RoomColors.bowl). UV glTF → st USD: v переворачиваем.

    python -P tools/assets/props_usdz.py <dogbowl.glb> app/Resources/Pets/bowl.usdz --kind bowl
    python -P tools/assets/props_usdz.py <ball.glb>    app/Resources/Pets/ball.usdz --kind ball

Проверка: треугольники ≤ 2000, файл ≤ 300 КБ, ARKit-совместимость (UsdUtils.ComplianceChecker).
Код выхода 1, если бюджет или проверка не прошли.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import struct
import sys
import tempfile
from pathlib import Path

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import Glb  # noqa: E402

MAX_TRIS = 2000
MAX_BYTES = 300 * 1024

KINDS = {
    # radius — по полу (x/z), height — во сколько ужать по y (None — пропорционально), color — если нет текстуры.
    "bowl": {"name": "Bowl", "radius": 0.09, "color": (0x34 / 255, 0x32 / 255, 0x3A / 255)},
    "ball": {"name": "Ball", "radius": 0.05, "color": (0xF2 / 255, 0xC9 / 255, 0x4C / 255)},
}


def read_mesh(g: Glb) -> dict:
    j = g.j
    if len(j["meshes"]) != 1 or len(j["meshes"][0]["primitives"]) != 1:
        raise ValueError("ждали один меш с одним примитивом")
    for n in j["nodes"]:
        if any(k in n for k in ("matrix", "rotation", "scale", "translation")):
            raise ValueError(f"узел {n.get('name')} со своим трансформом — допиши его применение")
    p = j["meshes"][0]["primitives"][0]
    a = p["attributes"]
    out = {
        "pos": g.accessor(a["POSITION"]),
        "nrm": g.accessor(a["NORMAL"]) if "NORMAL" in a else None,
        "uv": g.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else None,
        "idx": g.accessor(p["indices"]).reshape(-1),
        "image": None,
    }
    mat = j["materials"][p["material"]] if "material" in p else {}
    tex = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
    if tex is not None:
        img = j["images"][j["textures"][tex["index"]]["source"]]
        bv = j["bufferViews"][img["bufferView"]]
        off = bv.get("byteOffset", 0)
        out["image"] = (bytes(g.bin[off:off + bv["byteLength"]]), img.get("mimeType", "image/png"))
    return out


def fit(pos: np.ndarray, radius: float) -> tuple[np.ndarray, float]:
    """Центр рамки в ноль, радиус по полу — radius (масштаб одинаковый по всем осям)."""
    c = (pos.min(0) + pos.max(0)) / 2
    q = pos - c
    r = float(np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2).max())
    k = radius / r
    return q * k, k


def write(kind: str, m: dict, out: Path) -> dict:
    spec = KINDS[kind]
    pos, k = fit(m["pos"], spec["radius"])
    tris = len(m["idx"]) // 3
    with tempfile.TemporaryDirectory() as tmp:
        usdc = Path(tmp) / f"{kind}.usdc"
        stage = Usd.Stage.CreateNew(str(usdc))
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1.0)
        root = UsdGeom.Xform.Define(stage, "/Root")
        stage.SetDefaultPrim(root.GetPrim())
        mesh = UsdGeom.Mesh.Define(stage, f"/Root/{spec['name']}")
        mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, v)) for v in pos]))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * tris))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray([int(i) for i in m["idx"]]))
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        lo, hi = pos.min(0), pos.max(0)
        mesh.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, lo)), Gf.Vec3f(*map(float, hi))]))
        if m["nrm"] is not None:
            mesh.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, v)) for v in m["nrm"]]))
            mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        pv = UsdGeom.PrimvarsAPI(mesh)
        if m["uv"] is not None:
            st = pv.CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
            st.Set(Vt.Vec2fArray([Gf.Vec2f(float(u), float(1 - v)) for u, v in m["uv"]]))

        mat = UsdShade.Material.Define(stage, f"/Root/Materials/{spec['name']}Mat")
        sh = UsdShade.Shader.Define(stage, f"/Root/Materials/{spec['name']}Mat/Surface")
        sh.CreateIdAttr("UsdPreviewSurface")
        sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(1.0)
        sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
        files = []
        if m["image"] is not None and m["uv"] is not None and kind == "ball":
            data, mime = m["image"]
            ext = "png" if "png" in mime else "jpg"
            tex_name = f"{kind}_color.{ext}"
            (Path(tmp) / tex_name).write_bytes(data)
            files.append(tex_name)
            reader = UsdShade.Shader.Define(stage, f"/Root/Materials/{spec['name']}Mat/St")
            reader.CreateIdAttr("UsdPrimvarReader_float2")
            reader.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
            tex = UsdShade.Shader.Define(stage, f"/Root/Materials/{spec['name']}Mat/Color")
            tex.CreateIdAttr("UsdUVTexture")
            tex.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(tex_name)
            tex.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
            tex.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("repeat")
            tex.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("repeat")
            tex.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
            sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(tex.ConnectableAPI(), "rgb")
        else:
            sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*spec["color"]))
        mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(mat)
        stage.GetRootLayer().Save()

        out.parent.mkdir(parents=True, exist_ok=True)
        dst = str(out.resolve())
        cwd = os.getcwd()
        os.chdir(tmp)  # пакуем по относительным путям — текстура ляжет рядом с usdc внутри usdz
        try:
            ok = UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(usdc.name), dst)
        finally:
            os.chdir(cwd)
        if not ok:
            raise RuntimeError("usdz не собрался")

    errors = compliance(out)
    st = Usd.Stage.Open(str(out))
    if UsdGeom.GetStageUpAxis(st) != UsdGeom.Tokens.y or UsdGeom.GetStageMetersPerUnit(st) != 1.0:
        errors.append("ждали Y вверх и метры")
    if not st.GetDefaultPrim():
        errors.append("нет defaultPrim")
    size = out.stat().st_size
    rep = {"kind": kind, "file": str(out), "bytes": size, "tris": tris, "verts": int(len(pos)), "scale": round(k, 5),
           "extent_m": [round(float(x), 4) for x in (hi - lo)], "texture": files, "arkit_errors": errors,
           "ok": tris <= MAX_TRIS and size <= MAX_BYTES and not errors}
    return rep


def compliance(path: Path) -> list[str]:
    """ARKit-проверки (как usdchecker). В колесе usd-core их может не быть — тогда как в check_usdz.py:
    complianceChecker.py из исходников OpenUSD в PYTHONPATH (CI), иначе пропускаем."""
    Checker = getattr(UsdUtils, "ComplianceChecker", None)
    if Checker is None:
        try:
            from pxr.UsdUtils.complianceChecker import ComplianceChecker as Checker
        except ImportError:
            try:
                from complianceChecker import ComplianceChecker as Checker
            except ImportError:
                print("ARKit-проверка недоступна (нет complianceChecker) — пропущена", file=sys.stderr)
                return []
    c = Checker(arkit=True, skipARKitRootLayerCheck=False, rootPackageOnly=False, skipVariants=False, verbose=False)
    c.CheckCompliance(str(path))
    return list(c.GetErrors()) + list(c.GetFailedChecks())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--kind", required=True, choices=sorted(KINDS))
    a = ap.parse_args()
    rep = write(a.kind, read_mesh(Glb.load(a.src)), Path(a.out))
    print(json.dumps(rep, ensure_ascii=False))
    sys.exit(0 if rep["ok"] else 1)


if __name__ == "__main__":
    main()
