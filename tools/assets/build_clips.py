"""GLB Quaternius → GLB с ОДНОЙ анимацией «Clips» + clips.json (таблица отрезков).

Зачем: USD/USDZ хранит одну анимацию на скелет, RealityKit видит в availableAnimations
только её. Поэтому все клипы кладём подряд на одну шкалу времени, а в приложении режем
по clips.json (AnimationView(trimStart:trimEnd:)).

Что делает:
  1. берёт клипы исходника по SOURCES (дубли «AnimalArmature|…» — только где они лучше);
  2. строит процедурные позы из poses.json (сидеть/лежать/спать) поверх кадра 0 idle,
     ступни (IK-кости) следуют за ногами, тело опускается до пола автоматически;
  3. переходы (sit_in, lie_out, …): цепочка костей с задержкой и перелётом (голова, уши и хвост
     догоняют корпус), короткие клипы-оверлеи поверх idle (виляние, наклон головы, отряхивание…);
  4. дыхание в циклах, посадка на пол по каждому кадру, замыкание швов циклов;
  5. пересэмплирует всё в 24 fps и склеивает: клип, 1 пустой кадр, клип, ...;
  6. пишет GLB (меши/скин как в исходнике) и clips.json.

    python tools/assets/build_clips.py tools/assets/source/shiba.glb --poses tools/assets/poses.json \
        --out-glb build/shiba_clips.glb --out-json build/clips.json

Проверка готового GLB (швы, пол, обязательные клипы; код выхода 1 при провале):
    python tools/assets/build_clips.py build/shiba_clips.glb --check build/clips.json \
        --poses tools/assets/poses.json --summary "$GITHUB_STEP_SUMMARY"

Самопроверка математики (без сборки): python tools/assets/build_clips.py --selftest

Нужен только numpy.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import (Glb, GlbWriter, apply_style, globals_from_local, mat_to_q, qeuler, qinv,  # noqa: E402
                     qmul, qnorm, qslerp, sample_track, trs_mat)

FPS = 24
GAP_FRAMES = 1  # пустых кадров между клипами (интерполяция туда не попадает при обрезке)

# (имя анимации в исходнике, короткое имя в приложении, цикл)
SOURCES = [
    ("Idle", "idle", True),
    ("Idle_2", "idle_2", True),
    ("Idle_2_HeadLow", "idle_headlow", True),
    ("Walk", "walk", True),
    ("Gallop", "gallop", True),
    ("Gallop_Jump", "gallop_jump", False),
    ("Jump_ToIdle", "jump_to_idle", False),
    # eat — из дубля с префиксом: 2.667 с, шов 0°; у «Eating» без префикса 2.5 с и шов 5.8°
    ("AnimalArmature|Eating", "eat", True),
    ("Attack", "attack", False),
    ("Idle_HitReact_Left", "hit_left", False),
    ("Idle_HitReact_Right", "hit_right", False),
    ("Death", "death", False),
]

# 21 клип, которые уже есть в приложении (имена не менять)
REQUIRED = ["idle", "idle_2", "idle_headlow", "walk", "gallop", "gallop_jump", "jump_to_idle", "eat",
            "attack", "hit_left", "hit_right", "death",
            "sit_in", "sit", "sit_out", "lie_in", "lie", "lie_out", "sleep_in", "sleep", "sleep_out"]
# новые короткие клипы (PetClipNames.optional в приложении)
EXTRA = ["idle_wag", "happy_wag", "head_tilt", "shake", "hop", "play_bow", "ear_flick", "sniff",
         "look_l", "look_r", "yawn"]

# посадка на пол: snap — нижняя точка всегда на полу; flight — только кадры у пола (прыжок не трогаем);
# lift — только вытащить из-под пола (по умолчанию для всего остального)
# idle — snap: дыхание качает плечи, лапы не должны ни висеть, ни уходить в пол
SOURCE_GROUND = {"jump_to_idle": "flight", "death": "snap", "idle": "snap"}

SEAM_MAX_DEG = 0.5    # шов цикла по любой кости
SEAM_BLEND = 6        # кадров на замыкание шва
FLOOR_TOL = 0.005     # ±0.5% роста — допуск посадки
FLIGHT_LO, FLIGHT_HI = 0.01, 0.02  # flight: ниже 1% роста — на пол, выше 2% — полёт, между — плавно
MIN_Y_FAIL = -0.01    # проверка: ниже −1% роста — провал (кроме death)
HOVER_FAIL = 0.01     # проверка: snap-клип висит выше 1% роста — провал
OVERSHOOT = 0.08      # перелёт головы/ушей/хвоста в переходах

# IK-кость ступни → кость голени, за которой она должна следовать
IK_FOLLOW = {
    "IKBackLeg.L": "BackLowerLeg.L",
    "IKBackLeg.R": "BackLowerLeg.R",
    "IKFrontLeg.L": "FrontLowerLeg.L",
    "IKFrontLeg.R": "FrontLowerLeg.R",
}


def overlap_of(name: str) -> tuple[float, bool]:
    """Задержка кости в переходе (доля длительности) и есть ли перелёт."""
    for prefix, delay, back in (("Torso", 0.05, False), ("Neck", 0.12, False), ("Head", 0.18, True),
                                ("Ear", 0.25, True), ("Tail", 0.30, True)):
        if name.startswith(prefix):
            return delay, back
    return 0.0, False  # Body, Back, лапы и всё прочее — без задержки


def rot_part(m: np.ndarray) -> np.ndarray:
    r = m[:3, :3]
    return r / np.linalg.norm(r, axis=0, keepdims=True)


def clamp01(u: float) -> float:
    return min(max(u, 0.0), 1.0)


def smoothstep(u: float) -> float:
    u = clamp01(u)
    return u * u * (3 - 2 * u)


_BACK_C: dict[float, float] = {}


def back_c(overshoot: float) -> float:
    """Параметр easeOutBack, при котором перелёт ровно overshoot (0.08 → c ≈ 1.5)."""
    if overshoot not in _BACK_C:
        lo, hi = 0.0, 10.0
        for _ in range(80):  # пик easeOutBack: 1 + 4c³ / (27(c+1)²)
            c = (lo + hi) / 2
            lo, hi = (c, hi) if 4 * c ** 3 / (27 * (c + 1) ** 2) < overshoot else (lo, c)
        _BACK_C[overshoot] = (lo + hi) / 2
    return _BACK_C[overshoot]


def ease_out_back(u: float, overshoot: float = OVERSHOOT) -> float:
    u = clamp01(u)
    c = back_c(overshoot)
    return 1 + (c + 1) * (u - 1) ** 3 + c * (u - 1) ** 2


def envelope(keys: list, x: float) -> float:
    """Огибающая по ключам [[доля, вес], …], между ключами — smoothstep."""
    if x <= keys[0][0]:
        return float(keys[0][1])
    for (x0, w0), (x1, w1) in zip(keys, keys[1:]):
        if x <= x1:
            return float(w0 + (w1 - w0) * smoothstep((x - x0) / (x1 - x0) if x1 > x0 else 1.0))
    return float(keys[-1][1])


def wave_hz(w: dict) -> float:
    return float(w["hz"]) if "hz" in w else 1.0 / float(w["period"])


def qangle(a: np.ndarray, b: np.ndarray) -> float:
    """Угол между кватернионами в градусах (через atan2 — точно и около нуля)."""
    r = qmul(qinv(qnorm(a)), qnorm(b))
    return float(np.degrees(2 * math.atan2(float(np.linalg.norm(r[:3])), abs(float(r[3])))))


def cp(loc) -> list:
    return [[t.copy(), r.copy(), s.copy()] for t, r, s in loc]


class Rig:
    def __init__(self, g: Glb):
        self.g = g
        self.par = g.parents()
        self.n = len(g.j["nodes"])
        self.names = [nd.get("name", f"node{i}") for i, nd in enumerate(g.j["nodes"])]
        self.idx = {nm: i for i, nm in enumerate(self.names)}
        self.rest = g.rest_trs()
        self.joints = list(g.j["skins"][0]["joints"])
        js = set(self.joints)
        # корни скелета: кости, у которых родитель — не кость (Body и IK-ступни); их двигаем при посадке
        self.roots = [i for i in self.joints if self.par[i] not in js]
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

    def floor_height(self, loc) -> tuple[float, float]:
        """Пол = низ меша в позе loc (кадр 0 idle), рост = верх − низ."""
        if self.skin_model is None:
            self.min_y(loc)
        meshes = self.skin_model.skinned(self.mats(loc))
        lo = float(min(v[:, 1].min() for v, _, _ in meshes))
        hi = float(max(v[:, 1].max() for v, _, _ in meshes))
        return lo, hi - lo

    def shift_y(self, loc, dy: float) -> list:
        """Жёсткий сдвиг всей собаки по мировому Y: двигаем корни скелета (Body и IK-ступни)."""
        out = cp(loc)
        G = globals_from_local(self.mats(loc), self.par)
        for i in self.roots:
            p = self.par[i]
            PG = G[p] if p >= 0 else np.eye(4)
            out[i][0] = out[i][0] + np.linalg.inv(PG[:3, :3]) @ np.array([0.0, dy, 0.0])
        return out

    def refollow_ik(self, frames: list, ref) -> list:
        """IK-ступни снова на концах голеней (связь «голень → ступня» как в кадре ref)."""
        Gr = globals_from_local(self.mats(ref), self.par)
        rel = {}
        for ik, low in IK_FOLLOW.items():
            if ik in self.idx and low in self.idx:
                i, lo = self.idx[ik], self.idx[low]
                rel[i] = (lo, np.linalg.inv(Gr[lo]) @ Gr[i])
        out = []
        for loc in frames:
            loc = cp(loc)
            G = globals_from_local(self.mats(loc), self.par)
            for i, (lo, R) in rel.items():
                p = self.par[i]
                PG = G[p] if p >= 0 else np.eye(4)
                Lm = np.linalg.inv(PG) @ G[lo] @ R
                loc[i][0] = Lm[:3, 3].copy()
                loc[i][1] = mat_to_q(rot_part(Lm))
            out.append(loc)
        return out

    def seam_deg(self, a, b) -> float:
        return max(qangle(a[i][1], b[i][1]) for i in self.joints)


# --- обработка клипов (кадры = списки локальных TRS) ---

def sample_curve(frames: list, i: int, e: float) -> list:
    """Кость i по доле e ∈ [0, 1] (между кадрами — slerp); e > 1 — продолжение последнего шага."""
    n = len(frames)
    if e <= 0:
        t, r, s = frames[0][i]
        return [t.copy(), r.copy(), s.copy()]
    if e < 1:
        pos = e * (n - 1)
        k = min(int(pos), n - 2)
        u = pos - k
        a, b = frames[k][i], frames[k + 1][i]
        return [a[0] * (1 - u) + b[0] * u, qnorm(qslerp(qnorm(a[1]), qnorm(b[1]), u)), a[2] * (1 - u) + b[2] * u]
    a, b = frames[-2][i], frames[-1][i]
    x = (e - 1) * (n - 1)  # в шагах последнего отрезка
    d = qmul(qinv(qnorm(a[1])), qnorm(b[1]))
    q = qnorm(qmul(qnorm(b[1]), qslerp(np.array([0, 0, 0, 1.0]), qnorm(d), x)))
    return [b[0] + (b[0] - a[0]) * x, q, b[2].copy()]


def overlap(rig: Rig, frames: list, chain: bool = True) -> list:
    """Перекрытие: кость отстаёт на свою задержку, голова/уши/хвост — с перелётом.
    Кадры на входе — с линейным ходом (без easing), easing даёт пересэмплирование.
    chain=False — только smoothstep для всех костей, без задержек."""
    n = len(frames)
    if n < 3:
        return frames
    out = [cp(f) for f in frames]
    for i in range(rig.n):
        if i in rig.ik_nodes:
            continue  # ступни потом ставим заново за голенями
        delay, back = overlap_of(rig.names[i]) if chain else (0.0, False)
        for k in range(n):
            u = clamp01((k / (n - 1) - delay) / (1 - delay))
            e = ease_out_back(u) if back else smoothstep(u)
            out[k][i] = sample_curve(frames, i, e)
    return rig.refollow_ik(out, frames[0])


def ground(rig: Rig, frames: list, mode: str, floor: float, height: float) -> list:
    out = []
    for loc in frames:
        gap = rig.min_y(loc) - floor
        if mode == "snap":
            dy = -gap
        elif mode == "flight":
            w = 1.0 if gap <= 0 else 1 - smoothstep((gap / height - FLIGHT_LO) / (FLIGHT_HI - FLIGHT_LO))
            dy = -gap * w
        else:  # lift
            dy = max(0.0, -FLOOR_TOL * height - gap)
        out.append(rig.shift_y(loc, dy) if abs(dy) > 1e-9 else cp(loc))
    return out


def close_seam(rig: Rig, frames: list) -> tuple[list, str]:
    """Замыкание шва цикла. Если шов — ровно «недостающий последний шаг» (исходник без
    замыкающего кадра), дописываем кадр 0; иначе slerp последних кадров к кадру 0."""
    n = len(frames)
    seam = rig.seam_deg(frames[-1], frames[0])
    if n < 3 or seam <= SEAM_MAX_DEG:
        return frames, "ok"
    one_step = all(
        qangle(frames[-1][i][1], frames[0][i][1])
        <= 1.5 * max(qangle(frames[-2][i][1], frames[-1][i][1]), qangle(frames[0][i][1], frames[1][i][1])) + SEAM_MAX_DEG
        for i in rig.joints)
    if one_step:
        return [cp(f) for f in frames] + [cp(frames[0])], f"+1 кадр (шов {seam:.1f}°)"
    m = min(SEAM_BLEND, n - 1)
    out = [cp(f) for f in frames]
    f0 = frames[0]
    for i in range(1, m + 1):
        k = n - 1 - m + i
        w = smoothstep(i / m)
        out[k] = [[t * (1 - w) + a[0] * w, qnorm(qslerp(qnorm(r), qnorm(a[1]), w)), s * (1 - w) + a[2] * w]
                  for (t, r, s), a in zip(out[k], f0)]
    return out, f"slerp {m} кадров (шов {seam:.1f}°)"


def wave_rot(rig: Rig, waves: list, t: float, x: float, keys: list | None) -> dict:
    """Синусы поверх позы: {кость: (x,y,z)°}; keys — общая огибающая (None — без неё)."""
    rot: dict = {}
    for w in waves:
        k = w.get("keys", keys)
        env = 1.0 if k is None else envelope(k, lagged(x, w.get("lag", 0.0)))
        s = math.sin(2 * math.pi * (t * wave_hz(w) + w.get("phase", 0.0))) * env
        for bn, d in rig.expand({w["bone"]: w["deg"]}).items():
            rot[bn] = tuple(np.array(rot.get(bn, (0, 0, 0)), float) + np.array(d, float) * s)
    return rot


def lagged(x: float, lag: float) -> float:
    return clamp01((x - lag) / (1 - lag)) if lag > 0 else x


def add_rot(a: dict, b: dict) -> dict:
    out = dict(a)
    for k, v in b.items():
        out[k] = tuple(np.array(out.get(k, (0, 0, 0)), float) + np.array(v, float))
    return out


def check_loop_waves(name: str, dur: float, waves: list) -> None:
    for w in waves:
        cyc = wave_hz(w) * dur
        if abs(cyc - round(cyc)) > 1e-6:
            raise ValueError(f"{name}: волна {w['bone']} — {cyc:.3f} периода на цикл, нужно целое")


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


def build_transition(rig: Rig, ps: dict, poses: dict, named: dict, c: dict) -> list:
    """Переход A → B с линейным ходом u (easing и перекрытие — потом, в overlap)."""
    n = frames_of(c["dur"])
    fa, fb = c.get("from", "idle"), c["to"]
    parent_of = {k: (v.get("from") or "idle") for k, v in ps["poses"].items()}
    frames = []
    if parent_of.get(fb) == fa or parent_of.get(fa) == fb:
        # поза = родитель + повороты: доводим повороты от 0 до 1 —
        # так ступни (IK) остаются на ногах в каждом кадре
        child = fb if parent_of.get(fb) == fa else fa
        p = poses[child]
        for k in range(n):
            u = k / (n - 1)
            u = u if child == fb else 1 - u
            rot = {b: tuple(np.array(d, float) * u) for b, d in p["rot"].items()}
            frames.append(rig.apply(p["start"], rot, p["offset"] * u))
    else:  # общий случай: интерполяция локальных TRS
        A, B = named[fa], named[fb]
        for k in range(n):
            u = k / (n - 1)
            frames.append([[a[0] * (1 - u) + b[0] * u, qslerp(a[1], b[1], u), a[2] * (1 - u) + b[2] * u]
                           for a, b in zip(A, B)])
    return frames


def build_hold(rig: Rig, poses: dict, name: str, c: dict) -> list:
    """Удержание позы + волны (дыхание, хвост) — бесшовный цикл."""
    n = frames_of(c["dur"])
    p = poses[c["pose"]]
    waves = c.get("wave", [])
    if c.get("loop"):
        check_loop_waves(name, (n - 1) / FPS, waves)
    frames = []
    for k in range(n):
        if not waves:
            frames.append(cp(p["loc"]))
            continue
        rot = add_rot(p["rot"], wave_rot(rig, waves, k / FPS, k / (n - 1), None))
        frames.append(rig.apply(p["start"], rot, p["offset"]))
    return frames


def build_overlay(rig: Rig, base, name: str, c: dict, height: float) -> list:
    """Короткий клип поверх кадра 0 idle: поза overlay × огибающая keys + волны + подскок lift.
    Не-loop: огибающая 0 на концах → начало и конец ровно в позе idle."""
    n = frames_of(c["dur"])
    loop = bool(c.get("loop", False))
    keys = c.get("keys", [[0, 1], [1, 1]] if loop else [[0, 0], [0.25, 1], [0.75, 1], [1, 0]])
    ov = rig.expand(c.get("overlay", {}))
    lag = {}
    for nm, v in c.get("lag", {}).items():
        for bn in rig.expand({nm: (0, 0, 0)}):
            lag[bn] = float(v)
    waves = c.get("wave", [])
    if loop:
        check_loop_waves(name, (n - 1) / FPS, waves)
    lift = float(c.get("lift", 0.0)) * height
    lift_keys = c.get("lift_keys", keys)
    frames = []
    for k in range(n):
        x, t = k / (n - 1), k / FPS
        rot = {b: tuple(np.array(d, float) * envelope(keys, lagged(x, lag.get(b, 0.0)))) for b, d in ov.items()}
        rot = add_rot(rot, wave_rot(rig, waves, t, x, keys))
        frames.append(rig.apply(base, rot, np.array([0.0, lift * envelope(lift_keys, x), 0.0])))
    return frames


def ground_modes(poses_spec: dict | None) -> dict:
    modes = dict(SOURCE_GROUND)
    if poses_spec:
        for name, c in poses_spec.get("clips", {}).items():
            if "ground" in c:
                modes[name] = c["ground"]
            else:
                modes[name] = "snap"  # переходы, удержания и оверлеи стоят на полу
    return modes


def build(args) -> None:
    g = Glb.load(args.glb)
    rig = Rig(g)
    anims = {a["name"]: a for a in g.j.get("animations", [])}
    missing = [s for s, _, _ in SOURCES if s not in anims]
    if missing:
        print("WARN: missing animations", missing)

    # --- исходные клипы: кадры локальных TRS ---
    clips: list[tuple[str, bool, str, list]] = []  # (имя, цикл, источник, [кадры loc])
    for src, name, loop in SOURCES:
        if src not in anims:
            continue
        tr = g.animation_tracks(anims[src])
        end = max(float(t[-1]) for t, _, _ in tr.values())
        n = frames_of(end)
        clips.append((name, loop, src, [rig.locals_at(tr, k / FPS) for k in range(n)]))

    idle_src = next(s for s, nm, _ in SOURCES if nm == "idle")
    base = rig.locals_at(g.animation_tracks(anims[idle_src]), 0.0)
    floor, height = rig.floor_height(base)
    print(f"пол {floor:.4f}, рост {height:.4f}")

    ps = json.loads(Path(args.poses).read_text(encoding="utf-8")) if args.poses else None
    modes = ground_modes(ps)
    overlap_names = set()

    # --- волны поверх исходных циклов (дыхание idle) ---
    if ps:
        for name, spec in ps.get("source_wave", {}).items():
            i = next(k for k, c in enumerate(clips) if c[0] == name)
            cname, loop, src, frames = clips[i]
            if loop:
                check_loop_waves(name, (len(frames) - 1) / FPS, spec)
            frames = [rig.apply(loc, wave_rot(rig, spec, k / FPS, 0.0, None), None) for k, loc in enumerate(frames)]
            clips[i] = (cname, loop, src, frames)

    # --- процедурные позы, переходы, оверлеи ---
    if ps:
        poses = build_poses(rig, base, ps["poses"])
        named = {"idle": base, **{k: v["loc"] for k, v in poses.items()}}
        for cname, c in ps["clips"].items():
            if "to" in c:
                chain = c.get("overlap", True)
                frames = overlap(rig, build_transition(rig, ps, poses, named, c), chain)
                if chain:
                    overlap_names.add(cname)
                how = "procedural"
            elif "over" in c:
                frames = build_overlay(rig, base, cname, c, height)
                how = "overlay"
            else:
                frames = build_hold(rig, poses, cname, c)
                how = "procedural"
            clips.append((cname, bool(c.get("loop", False)), how, frames))

    # --- посадка на пол и швы ---
    for k, (name, loop, how, frames) in enumerate(clips):
        frames = ground(rig, frames, modes.get(name, "lift"), floor, height)
        note = ""
        if loop:
            frames, note = close_seam(rig, frames)
            if note.startswith("slerp"):  # смешанные кадры могли уйти от пола — сажаем заново
                frames = ground(rig, frames, modes.get(name, "lift"), floor, height)
        clips[k] = (name, loop, how, frames)
        if note and note != "ok":
            print(f"  шов {name}: {note}")

    # --- какие каналы писать: всё, что хоть где-то отличается от покоя ---
    chans: set[tuple[int, str]] = set()
    for src, _, _ in SOURCES:
        if src in anims:
            chans |= {k for k in g.animation_tracks(anims[src]) if k[1] != "weights"}
    eps = 1e-6
    for _, _, _, frames in clips:
        for loc in frames:
            for i, (t, r, s) in enumerate(loc):
                rt, rr, rs = rig.rest[i]
                if np.abs(t - rt).max() > eps:
                    chans.add((i, "translation"))
                if 1 - abs(float(np.dot(qnorm(r), qnorm(rr)))) > eps:
                    chans.add((i, "rotation"))
                if np.abs(s - rs).max() > eps:
                    chans.add((i, "scale"))
    js = set(rig.joints)
    src_nodes = {i for src, _, _ in SOURCES if src in anims for i, _ in g.animation_tracks(anims[src])}
    bad = sorted({rig.names[i] for i, _ in chans if i not in js and i not in src_nodes})
    if bad:  # не-кости (арматура, корень) анимировать нельзя: RealityKit берёт только SkelAnimation
        raise RuntimeError(f"анимируются не кости: {bad}")
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
        print(f"  {k:14s} {v['start']:8.3f} - {v['end']:8.3f}  loop={v['loop']}"
              f"{'  overlap' if k in overlap_names else ''}")
    print("->", args.out_glb, args.out_json)


# --- проверка готового GLB ---

def check(args) -> int:
    g = Glb.load(args.glb)
    rig = Rig(g)
    info = json.loads(Path(args.check).read_text(encoding="utf-8"))
    clips = info["clips"]
    fps = info["fps"]
    tracks = g.animation_tracks(g.j["animations"][0])
    ps = json.loads(Path(args.poses).read_text(encoding="utf-8")) if args.poses else None
    modes = ground_modes(ps)
    problems: list[str] = []
    for nm in REQUIRED + EXTRA:
        if nm not in clips:
            problems.append(f"нет клипа {nm}")
    if "idle" not in clips:
        print("FAIL: нет idle")
        return 1
    idle0 = rig.locals_at(tracks, clips["idle"]["frames"][0] / fps)
    floor, height = rig.floor_height(idle0)
    rows = []
    for name, c in clips.items():
        f0, f1 = c["frames"]
        frames = [rig.locals_at(tracks, f / fps) for f in range(f0, f1 + 1)]
        ys = [(rig.min_y(loc) - floor) / height * 100 for loc in frames]
        miny, hover = min(ys), max(ys)
        seam = rig.seam_deg(frames[-1], frames[0]) if c["loop"] else None
        move = None  # шов по положению суставов в мире, % роста (seam_deg видит только повороты)
        if c["loop"]:
            ga = globals_from_local(rig.mats(frames[0]), rig.par)
            gb = globals_from_local(rig.mats(frames[-1]), rig.par)
            move = max(float(np.linalg.norm(gb[i][:3, 3] - ga[i][:3, 3])) for i in rig.joints) / height * 100
        ends = None
        if c.get("source") == "overlay" and not c["loop"]:
            ends = max(rig.seam_deg(frames[0], idle0), rig.seam_deg(frames[-1], idle0))
        mode = modes.get(name, "lift")
        bad = []
        if c["loop"] and seam is not None and seam > SEAM_MAX_DEG:
            bad.append(f"шов {seam:.2f}°")
        if move is not None and move > FLOOR_TOL * 100:
            bad.append(f"шов сдвиг {move:.2f}%")
        if c["loop"] and len(frames) < 4:
            bad.append(f"цикл {len(frames)} кадров")
        if name != "death" and miny < MIN_Y_FAIL * 100:
            bad.append(f"min Y {miny:.2f}%")
        if mode == "snap" and hover > HOVER_FAIL * 100:
            bad.append(f"висит {hover:.2f}%")
        if ends is not None and ends > SEAM_MAX_DEG:
            bad.append(f"концы не в idle {ends:.2f}°")
        problems += [f"{name}: {b}" for b in bad]
        rows.append((name, len(frames), (f1 - f0) / fps, c["loop"], seam, miny, hover, mode, "; ".join(bad), move))

    lines = ["### Клипы: швы и пол", "",
             f"Рост {height:.3f}, пол {floor:.4f}. Порог: шов ≤ {SEAM_MAX_DEG}° и ≤ {FLOOR_TOL * 100:.1f}% сдвига, min Y ≥ {MIN_Y_FAIL * 100:.0f}% "
             f"(кроме death), snap-клип не выше {HOVER_FAIL * 100:.0f}%.", "",
             "| клип | длина | шов° | min Y % | max низа % | пол | |", "|---|---|---|---|---|---|---|"]
    for name, nfr, dur, loop, seam, miny, hover, mode, bad, _ in rows:
        lines.append(f"| {name} | {dur:.3f} с · {nfr} к{' · loop' if loop else ''} | "
                     f"{'—' if seam is None else f'{seam:.3f}'} | {miny:.2f} | {hover:.2f} | {mode} | "
                     f"{'❌ ' + bad if bad else '✅'} |")
    lines += ["", f"**{'FAIL: ' + str(len(problems)) + ' проблем' if problems else 'OK'}**", ""]
    md = "\n".join(lines)
    print(md)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(md + "\n")
    if args.report:
        Path(args.report).write_text(json.dumps({"height": height, "floor": floor, "problems": problems, "clips": [
            {"name": r[0], "frames": r[1], "dur": r[2], "loop": r[3], "seam_deg": r[4], "min_y_pct": r[5],
             "max_low_pct": r[6], "ground": r[7], "seam_move_pct": r[9]} for r in rows]}, ensure_ascii=False, indent=1), encoding="utf-8")
    if problems:
        print("FAIL:", *problems, sep="\n  ")
        return 1
    return 0


# --- самопроверка ---

def selftest(glb: str) -> int:
    fails = []

    def ok(cond: bool, what: str) -> None:
        print(("ok   " if cond else "FAIL ") + what)
        if not cond:
            fails.append(what)

    ok(abs(ease_out_back(0.0)) < 1e-12 and abs(ease_out_back(1.0) - 1) < 1e-12, "easeOutBack(0)=0, (1)=1")
    peak = max(ease_out_back(i / 1000) for i in range(1001))
    ok(abs(peak - 1 - OVERSHOOT) < 1e-3, f"easeOutBack: перелёт {peak - 1:.4f} ≈ {OVERSHOOT}")
    ok(abs(back_c(0.08) - 1.5) < 1e-3, f"easeOutBack c(0.08) = {back_c(0.08):.4f} ≈ 1.5")
    ok(abs(envelope([[0, 0], [0.5, 1], [1, 0]], 0.5) - 1) < 1e-12 and envelope([[0, 0], [1, 1]], 2) == 1,
       "огибающая по ключам")

    # синтетический «скелет» из одной кости: открытый цикл 0 → 20° за 24 кадра
    class One:
        joints = [0]

        def seam_deg(self, a, b):
            return qangle(a[0][1], b[0][1])

    def fr(deg, y=0.0):
        return [[np.array([0, y, 0.0]), qeuler((0, 0, deg)), np.ones(3)]]

    one = One()
    frames = [fr(20 * k / 23 + 5 * math.sin(k)) for k in range(24)]  # шов не «один шаг» → slerp
    closed, how = close_seam(one, frames)
    ok(how.startswith("slerp") and one.seam_deg(closed[-1], closed[0]) < 0.1,
       f"замыкание шва slerp: {one.seam_deg(frames[-1], frames[0]):.2f}° → {one.seam_deg(closed[-1], closed[0]):.4f}° ({how})")
    ok(all(qangle(a[0][1], b[0][1]) < 1e-9 for a, b in zip(closed[:-SEAM_BLEND], frames)),
       "замыкание трогает только последние кадры")
    steady = [fr(10 * k) for k in range(12)]  # равномерное вращение без замыкающего кадра
    closed2, how2 = close_seam(one, [fr(10 * k) for k in range(36)])
    ok(how2.startswith("+1") and len(closed2) == 37 and one.seam_deg(closed2[-1], closed2[0]) < 0.1,
       f"шов в один шаг → дописан кадр 0 ({how2})")
    del steady

    # продолжение кривой за конец (перелёт) — по последнему шагу
    lin = [fr(2 * k) for k in range(11)]
    over = sample_curve(lin, 0, 1.1)
    ok(abs(qangle(over[1], qeuler((0, 0, 22))) ) < 1e-6, "кривая за концом продолжается последним шагом")

    # посадка и перекрытие — на настоящем скелете
    g = Glb.load(glb)
    rig = Rig(g)
    anims = {a["name"]: a for a in g.j["animations"]}
    base = rig.locals_at(g.animation_tracks(anims["Idle"]), 0.0)
    floor, height = rig.floor_height(base)
    sunk = rig.shift_y(base, -0.1 * height)
    ok(abs(rig.min_y(sunk) - floor + 0.1 * height) < 1e-6, "сдвиг корней жёсткий (весь меш на dy)")
    snapped = ground(rig, [sunk, rig.shift_y(base, 0.05 * height)], "snap", floor, height)
    ok(all(abs(rig.min_y(f) - floor) < 1e-6 for f in snapped), "посадка snap: минимум ровно на полу")
    flown = ground(rig, [rig.shift_y(base, 0.3 * height), rig.shift_y(base, 0.005 * height),
                         rig.shift_y(base, -0.05 * height)], "flight", floor, height)
    ys = [(rig.min_y(f) - floor) / height for f in flown]
    ok(abs(ys[0] - 0.3) < 1e-6 and abs(ys[1]) < 1e-6 and abs(ys[2]) < 1e-6,
       f"посадка flight: полёт не тронут, у пола и под полом — на пол ({', '.join(f'{y:.3f}' for y in ys)})")
    lifted = ground(rig, [rig.shift_y(base, -0.05 * height)], "lift", floor, height)
    ok(abs((rig.min_y(lifted[0]) - floor) / height + FLOOR_TOL) < 1e-6, "посадка lift: из-под пола до −0.5%")

    # перекрытие: концы на месте, ступни остаются на голенях
    pose = rig.apply(base, rig.expand({"Back": (-30, 0, 0), "Head": (20, 0, 0), "Tail1": (0, 30, 0)}), None)
    tr = [rig.apply(base, rig.expand({"Back": (-30 * u, 0, 0), "Head": (20 * u, 0, 0), "Tail1": (0, 30 * u, 0)}), None)
          for u in np.linspace(0, 1, 19)]
    ov = overlap(rig, tr)
    ok(rig.seam_deg(ov[0], base) < 1e-6 and rig.seam_deg(ov[-1], pose) < 1e-4, "перекрытие: начало и конец как были")
    head, back = rig.idx["Head"], rig.idx["Back"]
    early = 2  # доля 0.11: корпус уже пошёл, голова (задержка 0.18) ещё на месте
    ok(qangle(ov[early][head][1], base[head][1]) < 1e-6 < qangle(ov[early][back][1], base[back][1]),
       "перекрытие: голова отстаёт от корпуса")
    tail = rig.idx["Tail1"]
    peak_t = max(qangle(f[tail][1], base[tail][1]) for f in ov)
    ok(peak_t > 30 * 1.04, f"перекрытие: хвост перелетает ({peak_t:.1f}° при цели 30°)")
    G0 = globals_from_local(rig.mats(base), rig.par)
    worst = 0.0
    for loc in ov:
        G = globals_from_local(rig.mats(loc), rig.par)
        for ik, low in IK_FOLLOW.items():
            i, lo = rig.idx[ik], rig.idx[low]
            R0 = np.linalg.inv(G0[lo]) @ G0[i]
            R = np.linalg.inv(G[lo]) @ G[i]
            worst = max(worst, float(np.abs(R - R0).max()))
    ok(worst < 1e-6, f"перекрытие: ступни на голенях (отклонение {worst:.2e})")

    print("selftest:", "FAIL" if fails else "OK")
    return 1 if fails else 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("glb", nargs="?", default=str(Path(__file__).resolve().parent / "source" / "shiba.glb"))
    ap.add_argument("--poses", help="poses.json; без него — только клипы исходника")
    ap.add_argument("--style", help="style_a.json: перекрасить материалы (плоский цвет, без бликов)")
    ap.add_argument("--out-glb")
    ap.add_argument("--out-json")
    ap.add_argument("--check", metavar="CLIPS_JSON", help="проверить готовый GLB (glb — это shiba_clips.glb)")
    ap.add_argument("--summary", help="дописать таблицу проверки (markdown), например $GITHUB_STEP_SUMMARY")
    ap.add_argument("--report", help="таблица проверки в JSON")
    ap.add_argument("--selftest", action="store_true", help="самопроверка математики на исходнике")
    args = ap.parse_args()
    for st in (sys.stdout, sys.stderr):  # консоль Windows (cp1251) не знает ≈, ° и значков
        try:
            st.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    if args.selftest:
        sys.exit(selftest(args.glb))
    if args.check:
        sys.exit(check(args))
    if not args.out_glb or not args.out_json:
        ap.error("нужны --out-glb и --out-json (или --check / --selftest)")
    build(args)


if __name__ == "__main__":
    main()
