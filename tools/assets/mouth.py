"""Рот Шибы: кость Jaw (нижняя челюсть), тёмная полость рта и язык — прямо в GLB, на numpy.

У Quaternius рот не открывается: морда — один кусок, только линия губ уже «шов» (вершины на ней
продублированы). Здесь:
  1. кость Jaw — ребёнок Head, шарнир у углов рта; грани ниже линии губ (низ морды, подбородок)
     переходят на Jaw весом smoothstep от углов рта к кончику (углы не рвутся, кончик — целиком);
  2. полость рта — «мешок» из тёмного материала Black от верхней губы через нёбо и горло к дну
     и нижней губе; в покое он сплющен и спрятан внутри головы, при открытой пасти виден изнутри;
  3. язык — новый примитив с материалом Tongue на костях Tongue (корень, ребёнок Jaw) и TongueTip;
     в покое лежит на дне рта, высовывается сдвигом Tongue вперёд («slide» в poses.json).

Координаты ниже — в осях кости Head из её inverse bind matrix (×1000, как в разборе модели):
X — вбок, Y — вперёд к носу, Z — вверх. Линию губ находим по сетке, а не по таблице.
"""
from __future__ import annotations

import numpy as np

from gltf_io import NCOMP, Glb

MOUTH_BONES = ["Jaw", "Tongue", "TongueTip"]
S = 1000.0  # мм-подобные единицы разбора → единицы кости Head

# шарнир челюсти и вес: от углов рта (y≈3.15) до y≈4.6 — с 0 до 1
JAW_PIVOT = (0.0, 2.9, -0.6)
JAW_W_FROM, JAW_W_TO = 3.0, 4.6
# грани «низа морды»: под линией губ, впереди y>2, выше шеи
JAW_Y_MIN, JAW_Z_MIN = 2.0, -6.0
# корень и середина языка
TONGUE_ROOT = (0.0, 3.7, -0.75)
TONGUE_MID = (0.0, 4.9, -0.55)
TONGUE_COLOR = "#E98C93"


def _smooth(u):
    u = np.clip(u, 0.0, 1.0)
    return u * u * (3 - 2 * u)


def jaw_weight(y):
    return _smooth((np.asarray(y, float) - JAW_W_FROM) / (JAW_W_TO - JAW_W_FROM))


def _append(g: Glb, arr: np.ndarray, comp: int, typ: str, minmax: bool = False) -> int:
    """Новый accessor в конце бинарного буфера исходника (build_clips потом копирует его как обычный)."""
    from gltf_io import COMP
    dt = np.dtype(COMP[comp])
    data = np.ascontiguousarray(arr.astype(dt)).tobytes()
    pad = (-len(g.bin)) % 4
    off = len(g.bin) + pad
    g.bin = bytes(g.bin) + b"\0" * pad + data
    g.j["buffers"][0]["byteLength"] = len(g.bin)
    g.j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
    acc = {"bufferView": len(g.j["bufferViews"]) - 1, "componentType": comp,
           "count": int(arr.shape[0]), "type": typ}
    if minmax:
        a2 = arr.reshape(arr.shape[0], -1)
        acc["min"] = [float(x) for x in a2.min(0)]
        acc["max"] = [float(x) for x in a2.max(0)]
    g.j["accessors"].append(acc)
    assert NCOMP[typ] == (arr.shape[1] if arr.ndim > 1 else 1)
    return len(g.j["accessors"]) - 1


def _lip_line(LY, LZ, y):
    return np.interp(y, LY, LZ)


def _vertex_normals(pos, tri):
    n = np.zeros_like(pos)
    fn = np.cross(pos[tri[:, 1]] - pos[tri[:, 0]], pos[tri[:, 2]] - pos[tri[:, 0]])
    for k in range(3):
        np.add.at(n, tri[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def _two_sided(pos, jn, wt, tri):
    """Обе стороны: копия вершин с обратным обходом (материал односторонний, смотрим изнутри)."""
    nrm = _vertex_normals(pos, tri)
    n = len(pos)
    pos2 = np.r_[pos, pos]
    nrm2 = np.r_[nrm, -nrm]
    jn2 = np.r_[jn, jn]
    wt2 = np.r_[wt, wt]
    tri2 = np.r_[tri, tri[:, ::-1] + n]
    return pos2, nrm2, jn2, wt2, tri2


def add_mouth(g: Glb, log=print) -> dict:
    """Добавляет Jaw/Tongue/TongueTip, перевешивает низ морды, полость рта и язык. Меняет g на месте."""
    j = g.j
    names = [n.get("name") for n in j["nodes"]]
    if "Jaw" in names:
        return {"skipped": "Jaw уже есть"}
    head = names.index("Head")
    skin = j["skins"][0]
    joints = skin["joints"]
    hj = joints.index(head)
    ibm_all = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    ibm_h = ibm_all[hj]
    to_mesh = np.linalg.inv(ibm_h)

    def head_local(pos):
        return (ibm_h @ np.c_[pos, np.ones(len(pos))].T).T[:, :3] * S

    def mesh_pos(hl):
        hl = np.asarray(hl, float) / S
        return (to_mesh @ np.c_[hl, np.ones(len(hl))].T).T[:, :3]

    # --- новые узлы и кости ---
    def node(name, t):
        j["nodes"].append({"name": name, "translation": [float(x) / S for x in t]})
        return len(j["nodes"]) - 1

    jaw = node("Jaw", JAW_PIVOT)
    tongue = node("Tongue", np.subtract(TONGUE_ROOT, JAW_PIVOT))
    tip = node("TongueTip", np.subtract(TONGUE_MID, TONGUE_ROOT))
    j["nodes"][head].setdefault("children", []).append(jaw)
    j["nodes"][jaw]["children"] = [tongue]
    j["nodes"][tongue]["children"] = [tip]
    J_JAW, J_TONGUE, J_TIP = len(joints), len(joints) + 1, len(joints) + 2
    joints += [jaw, tongue, tip]

    def ibm_at(p):
        t = np.eye(4)
        t[:3, 3] = -np.asarray(p, float) / S
        return t @ ibm_h

    ibm_new = np.concatenate([ibm_all, np.stack([ibm_at(JAW_PIVOT), ibm_at(TONGUE_ROOT), ibm_at(TONGUE_MID)])])
    skin["inverseBindMatrices"] = _append(g, ibm_new.transpose(0, 2, 1).reshape(-1, 16), 5126, "MAT4")

    prims = j["meshes"][0]["primitives"]
    mats = [m.get("name") for m in j["materials"]]

    def attrs(p):
        a = p["attributes"]
        return (g.accessor(a["POSITION"]), g.accessor(a["NORMAL"]), g.accessor(a["JOINTS_0"]).astype(np.int64),
                g.accessor(a["WEIGHTS_0"]), g.accessor(p["indices"])[:, 0].reshape(-1, 3).astype(np.int64))

    def write(p, pos, nrm, jn, wt, tri):
        jt = 5123  # как в исходнике (uint16)
        p["attributes"] = {"POSITION": _append(g, pos, 5126, "VEC3", minmax=True),
                           "NORMAL": _append(g, nrm, 5126, "VEC3"),
                           "JOINTS_0": _append(g, jn, jt, "VEC4"),
                           "WEIGHTS_0": _append(g, wt, 5126, "VEC4")}
        p["indices"] = _append(g, tri.reshape(-1, 1), 5125 if len(pos) > 65535 else 5123, "SCALAR")

    # --- линия губ: вершины, где сходятся грани «над» и «под» (впереди углов рта) ---
    # грубая линия по средним точкам (для разметки граней), потом точная — по общим вершинам
    LY = np.array([3.15, 3.82, 4.61, 5.93, 6.36])
    LZ = np.array([-0.45, -0.34, -0.19, 0.09, 0.17])
    report = {"jaw_faces": 0, "split": 0}
    lips_up: dict[tuple, tuple] = {}   # позиция → (суставы, веса) верхней губы
    lips_lo: dict[tuple, tuple] = {}   # … нижней (после перевеса)
    for p in prims:
        pos, nrm, jn, wt, tri = attrs(p)
        wt = wt / np.maximum(wt.sum(1, keepdims=True), 1e-9)
        hl = head_local(pos)
        hw = np.where(jn == hj, wt, 0).sum(1)
        c = hl[tri].mean(1)
        jawf = ((c[:, 2] < _lip_line(LY, LZ, c[:, 1])) & (c[:, 1] > JAW_Y_MIN) & (c[:, 2] > JAW_Z_MIN)
                & (hw[tri].max(1) > 0.01))
        if not jawf.any():
            continue
        report["jaw_faces"] += int(jawf.sum())
        used_j = np.zeros(len(pos), bool)
        used_h = np.zeros(len(pos), bool)
        used_j[tri[jawf].ravel()] = True
        used_h[tri[~jawf].ravel()] = True
        wj = jaw_weight(hl[:, 1]) * hw
        # общая вершина с ненулевым весом челюсти — дублируем для граней челюсти
        dup = np.where(used_j & used_h & (wj > 1e-3))[0]
        report["split"] += len(dup)
        remap = np.arange(len(pos))
        remap[dup] = len(pos) + np.arange(len(dup))
        pos = np.r_[pos, pos[dup]]
        nrm = np.r_[nrm, nrm[dup]]
        jn = np.r_[jn, jn[dup]]
        wt = np.r_[wt, wt[dup]]
        hl = np.r_[hl, hl[dup]]
        own = used_j & ~used_h  # только у граней челюсти; общие без дубля — остаются на Head
        wj = np.r_[np.where(own, wj, 0.0), wj[dup]]
        tri = tri.copy()
        tri[jawf] = remap[tri[jawf]]
        # вес Head → Jaw (столько, сколько дал smoothstep), в свободный слот или вместо Head
        for v in np.where(wj > 1e-4)[0]:
            ks = list(np.where(jn[v] == hj)[0])
            k = ks[0]
            take = min(wj[v], wt[v, k])
            free = [s for s in range(4) if wt[v, s] <= 1e-9]
            if take >= wt[v, k] - 1e-9:
                jn[v, k] = J_JAW
            elif free:
                wt[v, k] -= take
                jn[v, free[0]], wt[v, free[0]] = J_JAW, take
            else:  # слотов нет: забираем у самого слабого не-Head
                s = min((s for s in range(4) if s != k), key=lambda s: wt[v, s])
                wt[v, k] += wt[v, s] - take
                jn[v, s], wt[v, s] = J_JAW, take
        # губы: вершины на линии (обе копии), впереди углов
        up_v = set(tri[~jawf].ravel().tolist())
        lo_v = set(tri[jawf].ravel().tolist())
        keys = [tuple(np.round(x, 3)) for x in hl]
        up_k = {keys[v]: v for v in up_v}
        for v in lo_v:
            kk = keys[v]
            if kk in up_k and kk[1] >= LY[0] - 0.05 and kk[2] > -1.0:
                u = up_k[kk]
                lips_up[kk] = (jn[u].copy(), wt[u].copy())
                lips_lo[kk] = (jn[v].copy(), wt[v].copy())
        write(p, pos, nrm, jn, wt, tri)

    if len(lips_lo) < 5:
        raise RuntimeError(f"линия губ не найдена ({len(lips_lo)} точек)")
    # по кругу от левого угла через кончик к правому
    lip = sorted(lips_lo, key=lambda k: np.arctan2(k[0], k[1] - 3.0))
    L = np.array(lip, float)
    report["lip_points"] = len(lip)
    log(f"рот: граней челюсти {report['jaw_faces']}, дублей вершин {report['split']}, точек губ {len(lip)}")

    # --- полость рта: строки от верхней губы к нижней, у каждой точки губ ---
    def onehot(*pairs):
        jn = np.zeros(4, np.int64)
        wt = np.zeros(4)
        for s, (a, w) in enumerate(pairs):
            jn[s], wt[s] = a, w
        return jn, wt

    rows = []  # [ (позиции head-local ×1000 (n,3), суставы, веса) ]
    head_only = onehot((hj, 1.0))
    for i, (x, y, z) in enumerate(L):
        w = float(jaw_weight(y))
        k = lip[i]
        depth = 0.5 + 0.3 * w
        r = [
            ((x, y, z), *lips_up[k]),                                            # верхняя губа
            ((x * (1 - 0.3 * w), y - depth, z + 0.35 * w), *head_only),            # нёбо
            ((x * 0.55, 2.7, -0.15), *head_only),                                  # горло сверху
            ((x * 0.55, 2.7, -0.95), *onehot((hj, 0.85), (J_JAW, 0.15))),          # горло снизу
            ((x * (1 - 0.3 * w), y - depth, z - 0.8 * w), *onehot((hj, 1 - w), (J_JAW, w))),  # дно
            ((x, y, z), *lips_lo[k]),                                            # нижняя губа
        ]
        rows.append(r)
    nl, nr = len(rows), len(rows[0])
    bag_hl = np.array([[c[0] for c in r] for r in rows], float).reshape(-1, 3)
    bag_jn = np.array([[c[1] for c in r] for r in rows]).reshape(-1, 4)
    bag_wt = np.array([[c[2] for c in r] for r in rows], float).reshape(-1, 4)
    tri = []
    for i in range(nl - 1):
        for r in range(nr - 1):
            a, b, c, d = i * nr + r, (i + 1) * nr + r, (i + 1) * nr + r + 1, i * nr + r + 1
            tri += [(a, b, c), (a, c, d)]
    # торцы у углов рта (сплющенный «веер» — на всякий случай закрыт)
    for i in (0, nl - 1):
        for r in range(1, nr - 2):
            tri.append((i * nr, i * nr + r, i * nr + r + 1))
    # щёки: у боковых строк (|x| >= 1.0) сама строка залита пластиной — сбоку в щели тёмное, не насквозь
    for i in range(nl):
        if abs(L[i][0]) >= 1.0:
            o = i * nr
            tri += [(o, o + 1, o + 4), (o, o + 4, o + 5), (o + 1, o + 2, o + 3), (o + 1, o + 3, o + 4)]
    tri = np.array(tri, np.int64)
    pos, nrm, jn, wt, tri = _two_sided(mesh_pos(bag_hl), bag_jn, bag_wt, tri)
    black = mats.index("Black")
    bp = next(p for p in prims if p.get("material") == black)
    p0, n0, j0, w0, t0 = attrs(bp)
    write(bp, np.r_[p0, pos], np.r_[n0, nrm], np.r_[j0, jn], np.r_[w0, wt], np.r_[t0, tri + len(p0)])

    # --- язык: шестигранная «лопатка» вдоль Y, кончик скруглён ---
    ys = np.array([3.5, 4.1, 4.7, 5.25, 5.65, 5.9])
    half = np.array([0.45, 0.62, 0.72, 0.74, 0.62, 0.36])
    thick = np.array([0.10, 0.13, 0.13, 0.12, 0.10, 0.07])
    zc = np.interp(ys, [3.5, 6.0], [-0.80, -0.38])
    ring = [(-1.0, 0.0), (-0.55, 1.0), (0.0, 1.15), (0.55, 1.0), (1.0, 0.0), (0.55, -1.0), (0.0, -1.0), (-0.55, -1.0)]
    # «бороздка» по середине языка: верхняя средняя точка чуть ниже соседних
    ring[2] = (0.0, 0.7)
    tpos = []
    for y, h, t, z in zip(ys, half, thick, zc):
        for (u, v) in ring:
            tpos.append((u * h, y, z + v * t))
    nring = len(ring)
    tip_pt = len(tpos)
    tpos.append((0.0, 6.0, zc[-1]))
    back_pt = len(tpos)
    tpos.append((0.0, ys[0] - 0.1, zc[0]))
    ttri = []
    for s in range(len(ys) - 1):
        for k in range(nring):
            a, b = s * nring + k, s * nring + (k + 1) % nring
            c, d = (s + 1) * nring + (k + 1) % nring, (s + 1) * nring + k
            ttri += [(a, d, c), (a, c, b)]
    last = (len(ys) - 1) * nring
    for k in range(nring):
        ttri.append((last + k, tip_pt, last + (k + 1) % nring))
        ttri.append((k, (k + 1) % nring, back_pt))
    tpos = np.array(tpos, float)
    ttri = np.array(ttri, np.int64)
    # снаружи — нормали наружу (проверяем по центру)
    cen = tpos.mean(0)
    fc = tpos[ttri].mean(1)
    fn = np.cross(tpos[ttri[:, 1]] - tpos[ttri[:, 0]], tpos[ttri[:, 2]] - tpos[ttri[:, 0]])
    if np.mean(np.sum(fn * (fc - cen), 1)) < 0:
        ttri = ttri[:, ::-1]
    wtip = _smooth((tpos[:, 1] - 4.3) / 1.1)
    tjn = np.zeros((len(tpos), 4), np.int64)
    twt = np.zeros((len(tpos), 4))
    tjn[:, 0], twt[:, 0] = J_TONGUE, 1 - wtip
    tjn[:, 1], twt[:, 1] = J_TIP, wtip
    tm = mesh_pos(tpos)
    j["materials"].append({"name": "Tongue", "pbrMetallicRoughness": {
        "baseColorFactor": [*_hex_lin(TONGUE_COLOR), 1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0}})
    tp = {"attributes": {}, "material": len(j["materials"]) - 1, "mode": 4}
    prims.append(tp)
    write(tp, tm, _vertex_normals(tm, ttri), tjn, twt, ttri)
    report.update(tongue_tris=len(ttri), bag_tris=len(tri))
    return report


def _hex_lin(h: str) -> list[float]:
    from gltf_io import hex_to_linear
    return hex_to_linear(h)
