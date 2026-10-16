"""Проверка shiba.usdz без Mac: usd-core (pip install usd-core).

    python tools/assets/check_usdz.py build/shiba.usdz --clips build/clips.json --report build/usdz_report.json --strict

Что смотрит:
  - ARKit-совместимость (UsdUtils.ComplianceChecker(arkit=True)) — те же проверки, что usdchecker;
  - upAxis = Y, metersPerUnit, диапазон времени и timeCodesPerSecond против clips.json;
  - есть Skeleton + SkelAnimation, сколько суставов и ключей;
  - куда смотрит морда (Head относительно Tail в позе привязки) — ждём +Z;
  - меши, треугольники, материалы.
--strict: код выхода 1, если что-то из обязательного не так.
"""
from __future__ import annotations

import argparse
import json
import sys

from pxr import Gf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("usdz")
    ap.add_argument("--clips")
    ap.add_argument("--report")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--strict-compliance", action="store_true")
    a = ap.parse_args()

    problems: list[str] = []
    warnings: list[str] = []
    rep: dict = {"file": a.usdz}

    # ARKit-проверки — предупреждения (RealityKit терпит многое); жёстко — с --strict-compliance
    try:
        checker = UsdUtils.ComplianceChecker(arkit=True, skipARKitRootLayerCheck=False,
                                             rootPackageOnly=False, skipVariants=False, verbose=False)
        checker.CheckCompliance(a.usdz)
        rep["compliance"] = {"errors": list(checker.GetErrors()), "failed": list(checker.GetFailedChecks()),
                             "warnings": list(checker.GetWarnings()) if hasattr(checker, "GetWarnings") else []}
    except Exception as e:  # noqa: BLE001
        rep["compliance"] = {"exception": repr(e)}
    comp = rep["compliance"]
    if comp.get("errors") or comp.get("failed") or comp.get("exception"):
        (problems if a.strict_compliance else warnings).append("ARKit compliance: see report.compliance")

    st = Usd.Stage.Open(a.usdz)
    rep["upAxis"] = str(UsdGeom.GetStageUpAxis(st))
    rep["metersPerUnit"] = UsdGeom.GetStageMetersPerUnit(st)
    rep["startTimeCode"] = st.GetStartTimeCode()
    rep["endTimeCode"] = st.GetEndTimeCode()
    rep["timeCodesPerSecond"] = st.GetTimeCodesPerSecond()
    rep["defaultPrim"] = str(st.GetDefaultPrim().GetPath()) if st.GetDefaultPrim() else None
    if rep["upAxis"] != "Y":
        problems.append(f"upAxis={rep['upAxis']}, want Y")
    if not rep["defaultPrim"]:
        problems.append("no defaultPrim")

    skels, anims, meshes, mats, tris = [], [], [], [], 0
    for prim in st.Traverse():
        if prim.IsA(UsdSkel.Skeleton):
            sk = UsdSkel.Skeleton(prim)
            joints = list(sk.GetJointsAttr().Get() or [])
            binds = sk.GetBindTransformsAttr().Get() or []
            l2w = UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
            pos = {}
            for j, m in zip(joints, binds):
                pos[j.split("/")[-1]] = l2w.Transform(Gf.Matrix4d(m).ExtractTranslation())
            info = {"path": str(prim.GetPath()), "joints": len(joints)}
            if "Head" in pos and "Tail3" in pos:
                d = pos["Head"] - pos["Tail3"]
                info["head_minus_tail"] = [round(x, 4) for x in d]
                axis = max(range(3), key=lambda i: abs(d[i]))
                info["facing"] = ("+" if d[axis] > 0 else "-") + "XYZ"[axis]
                if info["facing"] != "+Z":
                    problems.append(f"model faces {info['facing']}, want +Z")
            lo = [min(p[i] for p in pos.values()) for i in range(3)] if pos else []
            hi = [max(p[i] for p in pos.values()) for i in range(3)] if pos else []
            info["joint_bounds"] = [[round(x, 4) for x in lo], [round(x, 4) for x in hi]]
            skels.append(info)
        elif prim.IsA(UsdSkel.Animation):
            an = UsdSkel.Animation(prim)
            ts = an.GetRotationsAttr().GetTimeSamples()
            anims.append({"path": str(prim.GetPath()), "joints": len(an.GetJointsAttr().Get() or []),
                          "rotation_samples": len(ts), "first": ts[0] if ts else None, "last": ts[-1] if ts else None})
        elif prim.IsA(UsdGeom.Mesh):
            fvc = UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get() or []
            n = sum(max(c - 2, 0) for c in fvc)
            tris += n
            meshes.append({"path": str(prim.GetPath()), "triangles": n})
        elif prim.IsA(UsdShade.Material):
            mats.append(str(prim.GetPath()))
    rep.update(skeletons=skels, animations=anims, meshes=meshes, triangles=tris, materials=mats)
    if not skels:
        problems.append("no Skeleton")
    if len(anims) != 1:
        problems.append(f"SkelAnimation count = {len(anims)}, want 1")
    if not meshes:
        problems.append("no Mesh")

    if a.clips:
        c = json.load(open(a.clips, encoding="utf-8"))
        want_end = round(c["duration"] * c["fps"])
        rep["clips_expected_frames"] = [0, want_end]
        if abs(rep["timeCodesPerSecond"] - c["fps"]) > 1e-6:
            problems.append(f"timeCodesPerSecond={rep['timeCodesPerSecond']}, clips fps={c['fps']}")
        if abs(rep["startTimeCode"]) > 1e-6 or abs(rep["endTimeCode"] - want_end) > 1.01:
            problems.append(f"time range {rep['startTimeCode']}..{rep['endTimeCode']}, want 0..{want_end}")
        for an in anims:
            if an["first"] is not None and (abs(an["first"]) > 1e-6 or abs(an["last"] - want_end) > 1.01):
                problems.append(f"animation samples {an['first']}..{an['last']}, want 0..{want_end}")

    rep["problems"] = problems
    rep["warnings"] = warnings
    txt = json.dumps(rep, ensure_ascii=False, indent=1, default=str)
    print(txt)
    if a.report:
        open(a.report, "w", encoding="utf-8").write(txt)
    if a.strict and problems:
        print("FAIL:", *problems, sep="\n  ")
        sys.exit(1)


if __name__ == "__main__":
    main()
