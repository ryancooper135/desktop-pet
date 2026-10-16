"""GLB Quaternius → GLB с ОДНОЙ анимацией «Clips» + clips.json (таблица отрезков).

Зачем: USD/USDZ хранит одну анимацию на скелет, RealityKit видит в availableAnimations
только её. Поэтому все клипы кладём подряд на одну шкалу времени, а в приложении режем
по clips.json (AnimationView(trimStart:trimEnd:)).

Что делает:
  1. берёт анимации без префикса «AnimalArmature|» (это дубли) и переименовывает по RENAME;
  2. строит процедурные позы из poses.json (сидеть/лежать/спать) поверх кадра 0 idle,
     ступни (IK-кости) следуют за ногами, тело опускается до пола автоматически;
  3. пересэмплирует всё в 24 fps и склеивает: клип, 1 пустой кадр, клип, ...;
  4. пишет GLB (меши/скин как в исходнике) и clips.json.

    python tools/assets/build_clips.py tools/assets/source/shiba.glb --poses tools/assets/poses.json \
        --out-glb build/shiba_clips.glb --out-json build/clips.json

Нужен только numpy.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import (Glb, GlbWriter, apply_style, globals_from_local, mat_to_q, qeuler, qinv,  # noqa: E402
                     qmul, qnorm, qslerp, sample_track, trs_mat)

FPS = 24
GAP_FRAMES = 1  # пустых кадров между клипами (интерполяция туда не попадает при обрезке)

# исходное имя → короткое имя в приложении, признак цикла
RENAME = {
    "Idle": ("idle", True),
    "Idle_2": ("idle_2", True),
    "Idle_2_HeadLow": ("idle_headlow", True),
    "Walk": ("walk", True),
    "Gallop": ("gallop", True),
    "Gallop_Jump": ("gallop_jump", False),
    "Jump_ToIdle": ("jump_to_idle", False),
    "Eating": ("eat", True),
    "Attack": ("attack", False),
    "Idle_HitReact_Left": ("hit_left", False),
    "Idle_HitReact_Right": ("hit_right", False),
    "Death": ("death", False),
}

# IK-кость ступни → кость голени, за которой она должна следовать
IK_FOLLOW = {
    "IKBackLeg.L": "BackLowerLeg.L",
    "IKBackLeg.R": "BackLowerLeg.R",
    "IKFrontLeg.L": "FrontLowerLeg.L",
    "IKFrontLeg.R": "FrontLowerLeg.R",
}


def rot_part(m: np.ndarray) -> np.ndarray:
    r = m[:3, :3]
    return r / np.linalg.norm(r, axis=0, keepdims=True)


def smoothstep(u: float) -> float:
    return u * u * (3 - 2 * u)


class Rig:
    def __init__(self, g: Glb):
        self.g = g
        self.par = g.parents()
        self.n = len(g.j["nodes"])
        self.names = [nd.get("name", f"node{i}") for i, nd in enumerate(g.j["nodes"])]
        self.idx = {nm: i for i, nm in enumerate(self.names)}
        self.rest = g.rest_trs()
        self.ik_nodes = set()
        for ik in IK_FOLLOW:
            if ik in self.idx:
                self._collect(self.idx[ik], self.ik_nodes)
        # порядок обхода: родители раньше детей; поддеревья IK — после остальных
        depth = []
        for i in range(self.n):
            d, p = 0, self.par[i]
            while p >= 0:
                d, p = d + 1, self.par[p]
            depth.append(d)
        order = sorted(range(self.n), key=lambda i: depth[i])
        self.order = [i for i in order if i not in self.ik_nodes] + [i for i in order if i in self.ik_nodes]
        self.skin_model = None

    def _collect(self, i: int, out: set) -> None:
        out.add(i)
        for c in self.g.j["nodes"][i].get("children", []):
            self._collect(c, out)

    def expand(self, spec: dict) -> dict:
        """«BackLeg.*» → BackLeg.L как есть и BackLeg.R зеркально (y, z со сменой знака)."""
        out = {}
        for name, deg in spec.items():
            x, y, z = deg
            if name.endswith(".*"):
                b = name[:-2]
                out[b + ".L"] = (x, y, z)
                out[b + ".R"] = (x, -y, -z)
            else:
                out[name] = (x, y, z)
        for name in out:
            if name not in self.idx:
                raise KeyError(f"no bone {name}")
        return out

    def locals_at(self, tracks: dict, t: float) -> list[list[np.ndarray]]:
        out = []
        for i, (tr, r, s) in enumerate(self.rest):
            tr, r, s = tr.copy(), r.copy(), s.copy()
            for path in ("translation", "rotation", "scale"):
                if (i, path) in tracks:
                    tt, vv, ip = tracks[(i, path)]
                    v = sample_track(tt, vv, t, path, ip)
                    if path == "translation":
                        tr = v
                    elif path == "rotation":
                        r = qnorm(v)
                    else:
                        s = v
            out.append([tr, r, s])
        return out

    @staticmethod
    def mats(loc) -> list[np.ndarray]:
        return [trs_mat(*x) for x in loc]

    def apply(self, base, rot: dict, offset) -> list[list[np.ndarray]]:
        """base — локальные TRS; rot — {кость: (x,y,z)°} в мировых осях (X — к левому боку собаки,
        Y — вверх, Z — вперёд), применяются поверх текущей позы родителя; offset — сдвиг корня Body
        в мировых единицах."""
        base_g = globals_from_local(self.mats(base), self.par)
        loc = [[t.copy(), r.copy(), s.copy()] for t, r, s in base]
        G: list[np.ndarray | None] = [None] * self.n
        body = self.idx.get("Body")
        for i in self.order:
            p = self.par[i]
            PG = G[p] if p >= 0 else np.eye(4)
            name = self.names[i]
            if name in IK_FOLLOW and self.idx.get(IK_FOLLOW[name]) is not None:
                low = self.idx[IK_FOLLOW[name]]
                W = G[low] @ np.linalg.inv(base_g[low]) @ base_g[i]
                Lm = np.linalg.inv(PG) @ W
                loc[i][0] = Lm[:3, 3].copy()
                loc[i][1] = mat_to_q(rot_part(Lm))
            if i == body and offset is not None and np.any(offset):
                loc[i][0] = loc[i][0] + np.linalg.inv(PG[:3, :3]) @ np.asarray(offset, float)
            if name in rot:
                qw = qeuler(rot[name])
                pr = mat_to_q(rot_part(PG)) if p >= 0 else np.array([0, 0, 0, 1.0])
                loc[i][1] = qnorm(qmul(qmul(qmul(qinv(pr), qw), pr), loc[i][1]))
            G[i] = PG @ trs_mat(*loc[i])
        return loc

    def min_y(self, loc) -> float:
        if self.skin_model is None:
            from preview import Model  # тот же скиннинг, что и в превью
            self.skin_model = Model(self.g)
        meshes = self.skin_model.skinned(self.mats(loc))
        return float(min(v[:, 1].min() for v, _, _ in meshes))


def build_poses(rig: Rig, base, spec: dict) -> dict:
    floor = rig.min_y(base)
    poses: dict[str, dict] = {}

    def make(name: str) -> dict:
        if name in poses:
            return poses[name]
        ps = spec[name]
        parent = ps.get("from")
        start = base if not parent else make(parent)["loc"]
        rot = rig.expand(ps.get("rot", {}))
        off = np.array(ps.get("offset", [0, 0, 0]), float)
        loc = rig.apply(start, rot, off)
        if ps.get("ground", True):
            for _ in range(3):  # опускаем/поднимаем тело, пока низ меша не на полу
                dy = floor - rig.min_y(loc)
                if abs(dy) < 1e-4:
                    break
                off = off + np.array([0, dy, 0])
                loc = rig.apply(start, rot, off)
        poses[name] = {"loc": loc, "start": start, "rot": rot, "offset": off}
        return poses[name]

    for name in spec:
        make(name)
    return poses


def frames_of(dur: float) -> int:
    return max(int(round(dur * FPS)) + 1, 2)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("--poses", help="poses.json; без него — только клипы исходника")
    ap.add_argument("--style", help="style_a.json: перекрасить материалы (плоский цвет, без бликов)")
    ap.add_argument("--out-glb", required=True)
    ap.add_argument("--out-json", required=True)
    args = ap.parse_args()

    g = Glb.load(args.glb)
    rig = Rig(g)
    anims = {a["name"]: a for a in g.j.get("animations", [])}
    missing = [k for k in RENAME if k not in anims]
    if missing:
        print("WARN: missing animations", missing)

    # --- исходные клипы: кадры локальных TRS ---
    clips: list[tuple[str, bool, str, list]] = []  # (имя, цикл, источник, [кадры loc])
    for src, (name, loop) in RENAME.items():
        if src not in anims:
            continue
        tr = g.animation_tracks(anims[src])
        end = max(float(t[-1]) for t, _, _ in tr.values())
        n = frames_of(end)
        clips.append((name, loop, src, [rig.locals_at(tr, k / FPS) for k in range(n)]))

    idle_src = next(k for k, v in RENAME.items() if v[0] == "idle")
    base = rig.locals_at(g.animation_tracks(anims[idle_src]), 0.0)

    # --- процедурные позы ---
    if args.poses:
        ps = json.loads(Path(args.poses).read_text(encoding="utf-8"))
        poses = build_poses(rig, base, ps["poses"])
        named = {"idle": base, **{k: v["loc"] for k, v in poses.items()}}
        for cname, c in ps["clips"].items():
            n = frames_of(c["dur"])
            frames = []
            if "to" in c:  # переход A → B
                fa, fb = c.get("from", "idle"), c["to"]
                parent_of = {k: (v.get("from") or "idle") for k, v in ps["poses"].items()}
                if parent_of.get(fb) == fa or parent_of.get(fa) == fb:
                    # поза = родитель + повороты: доводим повороты от 0 до 1 —
                    # так ступни (IK) остаются на ногах в каждом кадре
                    child = fb if parent_of.get(fb) == fa else fa
                    p = poses[child]
                    for k in range(n):
                        u = smoothstep(k / (n - 1))
                        u = u if child == fb else 1 - u
                        rot = {b: tuple(np.array(d, float) * u) for b, d in p["rot"].items()}
                        frames.append(rig.apply(p["start"], rot, p["offset"] * u))
                else:  # общий случай: интерполяция локальных TRS
                    A, B = named[fa], named[fb]
                    for k in range(n):
                        u = smoothstep(k / (n - 1))
                        frames.append([[a[0] * (1 - u) + b[0] * u, qslerp(a[1], b[1], u), a[2] * (1 - u) + b[2] * u]
                                       for a, b in zip(A, B)])
            else:  # удержание позы + «дыхание» (бесшовный цикл)
                p = poses[c["pose"]]
                breath = c.get("breath", [])
                for k in range(n):
                    t = k / FPS
                    if not breath:
                        frames.append(p["loc"])
                        continue
                    rot = dict(p["rot"])
                    for b in breath:
                        w = np.sin(2 * np.pi * (t / b["period"] + b.get("phase", 0.0)))
                        for bn, d in rig.expand({b["bone"]: b["deg"]}).items():
                            add = np.array(d, float) * w
                            # поверх позы: доп. поворот в мировых осях
                            rot[bn] = tuple(np.array(rot.get(bn, (0, 0, 0)), float) + add)
                    frames.append(rig.apply(p["start"], rot, p["offset"]))
            clips.append((cname, bool(c.get("loop", False)), "procedural", frames))

    # --- какие каналы писать ---
    chans: set[tuple[int, str]] = set()
    for src in RENAME:
        if src in anims:
            chans |= {k for k in g.animation_tracks(anims[src]) if k[1] != "weights"}
    eps = 1e-6
    for _, _, how, frames in clips:
        if how != "procedural":
            continue
        for loc in frames:
            for i, (t, r, s) in enumerate(loc):
                rt, rr, rs = rig.rest[i]
                if np.abs(t - rt).max() > eps:
                    chans.add((i, "translation"))
                if 1 - abs(float(np.dot(qnorm(r), qnorm(rr)))) > eps:
                    chans.add((i, "rotation"))
                if np.abs(s - rs).max() > eps:
                    chans.add((i, "scale"))
    chans_l = sorted(chans)

    # --- склейка ---
    times, table, frame = [], {c: [] for c in chans_l}, 0
    out_clips = {}
    for name, loop, how, frames in clips:
        f0 = frame
        for k, loc in enumerate(frames):
            times.append((f0 + k) / FPS)
            for (i, path) in chans_l:
                v = loc[i][{"translation": 0, "rotation": 1, "scale": 2}[path]]
                table[(i, path)].append(np.asarray(v, float))
        f1 = f0 + len(frames) - 1
        out_clips[name] = {"start": round(f0 / FPS, 6), "end": round(f1 / FPS, 6),
                           "frames": [f0, f1], "loop": loop, "source": how}
        frame = f1 + 1 + GAP_FRAMES

    # --- GLB ---
    j = copy.deepcopy(g.j)
    w = GlbWriter()
    remap: dict[int, int] = {}

    def acc(i: int) -> int:
        if i not in remap:
            remap[i] = w.copy_accessor(g, i)
        return remap[i]

    for m in j.get("meshes", []):
        for p in m["primitives"]:
            p["attributes"] = {k: acc(v) for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc(p["indices"])
            if "targets" in p:
                p["targets"] = [{k: acc(v) for k, v in t.items()} for t in p["targets"]]
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc(s["inverseBindMatrices"])
    if j.get("images"):
        raise NotImplementedError("текстуры в исходнике: добавь копирование bufferView картинок")

    t_acc = w.add(np.array(times, float).reshape(-1, 1), 5126, "SCALAR", minmax=True)
    samplers, channels = [], []
    for (i, path) in chans_l:
        vals = np.stack(table[(i, path)])
        if path == "rotation":  # непрерывность знака кватернионов
            for k in range(1, len(vals)):
                if np.dot(vals[k], vals[k - 1]) < 0:
                    vals[k] = -vals[k]
        o = w.add(vals, 5126, "VEC4" if path == "rotation" else "VEC3")
        samplers.append({"input": t_acc, "output": o, "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": i, "path": path}})
    j["animations"] = [{"name": "Clips", "samplers": samplers, "channels": channels}]
    if args.style:
        miss = apply_style(j, json.loads(Path(args.style).read_text(encoding="utf-8")))
        if miss:
            print("WARN: no color in style for", miss)
    Path(args.out_glb).parent.mkdir(parents=True, exist_ok=True)
    w.save(j, args.out_glb)

    info = {"fps": FPS, "animation": "Clips", "duration": round((frame - 1 - GAP_FRAMES) / FPS, 6),
            "note": "start/end - seconds on the single timeline; trim in RealityKit", "clips": out_clips}
    Path(args.out_json).write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"clips: {len(out_clips)}, frames: {frame - GAP_FRAMES}, channels: {len(channels)}")
    for k, v in out_clips.items():
        print(f"  {k:14s} {v['start']:8.3f} - {v['end']:8.3f}  loop={v['loop']}")
    print("->", args.out_glb, args.out_json)


if __name__ == "__main__":
    main()
