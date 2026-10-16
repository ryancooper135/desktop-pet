"""Минимальное чтение/запись GLB и математика скелета (numpy).

Без внешних зависимостей, кроме numpy. Кватернионы в порядке glTF: (x, y, z, w).
"""
from __future__ import annotations

import json
import struct

import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


class Glb:
    def __init__(self, gltf: dict, bin_data: bytes):
        self.j = gltf
        self.bin = bin_data

    # --- чтение/запись файла ---
    @staticmethod
    def load(path: str) -> "Glb":
        d = open(path, "rb").read()
        magic, ver, _ = struct.unpack("<4sII", d[:12])
        if magic != b"glTF" or ver != 2:
            raise ValueError(f"{path}: не GLB 2.0")
        off, gltf, bin_data = 12, None, b""
        while off < len(d):
            ln, typ = struct.unpack("<I4s", d[off:off + 8])
            chunk = d[off + 8:off + 8 + ln]
            if typ == b"JSON":
                gltf = json.loads(chunk)
            elif typ == b"BIN\0":
                bin_data = chunk
            off += 8 + ln
        return Glb(gltf, bin_data)

    def accessor(self, i: int) -> np.ndarray:
        a = self.j["accessors"][i]
        if "sparse" in a:
            raise NotImplementedError("sparse accessor")
        n = NCOMP[a["type"]]
        dt = np.dtype(COMP[a["componentType"]])
        bv = self.j["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        cnt = a["count"]
        stride = bv.get("byteStride") or n * dt.itemsize
        raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * (cnt - 1) + n * dt.itemsize, offset=off)
        if stride == n * dt.itemsize:
            arr = raw.view(dt).reshape(cnt, n)
        else:
            arr = np.stack([raw[k * stride:k * stride + n * dt.itemsize].view(dt) for k in range(cnt)])
        arr = arr.astype(np.float64) if dt == np.float32 else arr.copy()
        if a.get("normalized"):
            arr = arr / float(np.iinfo(dt).max)
        return arr

    # --- узлы ---
    def node_index(self, name: str) -> int:
        for i, n in enumerate(self.j["nodes"]):
            if n.get("name") == name:
                return i
        raise KeyError(name)

    def parents(self) -> list[int]:
        par = [-1] * len(self.j["nodes"])
        for i, n in enumerate(self.j["nodes"]):
            for c in n.get("children", []):
                par[c] = i
        return par

    def rest_trs(self) -> list[tuple[np.ndarray, np.ndarray, np.ndarray]]:
        out = []
        for n in self.j["nodes"]:
            if "matrix" in n:
                raise NotImplementedError("node.matrix")
            out.append((np.array(n.get("translation", [0, 0, 0]), float),
                        np.array(n.get("rotation", [0, 0, 0, 1]), float),
                        np.array(n.get("scale", [1, 1, 1]), float)))
        return out

    def animation_tracks(self, anim: dict) -> dict:
        """{(node, path): (times, values)} для одной анимации glTF."""
        tracks = {}
        for ch in anim["channels"]:
            s = anim["samplers"][ch["sampler"]]
            if s.get("interpolation", "LINEAR") == "CUBICSPLINE":
                raise NotImplementedError("CUBICSPLINE")
            t = self.accessor(s["input"])[:, 0]
            v = self.accessor(s["output"])
            tracks[(ch["target"]["node"], ch["target"]["path"])] = (t, v, s.get("interpolation", "LINEAR"))
        return tracks


class GlbWriter:
    """Собирает новый бинарный буфер: каждый accessor — свой плотный bufferView."""

    def __init__(self):
        self.buf = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def add(self, arr: np.ndarray, comp: int, typ: str, target: int | None = None,
            normalized: bool = False, minmax: bool = False) -> int:
        dt = np.dtype(COMP[comp])
        data = np.ascontiguousarray(arr.astype(dt)).tobytes()
        while len(self.buf) % 4:
            self.buf.append(0)
        view = {"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.buf.extend(data)
        self.views.append(view)
        acc = {"bufferView": len(self.views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            acc["normalized"] = True
        if minmax:
            a2 = arr.reshape(arr.shape[0], -1)
            acc["min"] = [float(x) for x in a2.min(0)]
            acc["max"] = [float(x) for x in a2.max(0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def copy_accessor(self, src: Glb, i: int) -> int:
        a = src.j["accessors"][i]
        arr = src.accessor(i)
        if a.get("normalized"):
            arr = np.round(arr * float(np.iinfo(COMP[a["componentType"]]).max))
        new = self.add(arr, a["componentType"], a["type"], normalized=a.get("normalized", False))
        for k in ("min", "max"):
            if k in a:
                self.accessors[new][k] = a[k]
        return new

    def save(self, gltf: dict, path: str) -> None:
        while len(self.buf) % 4:
            self.buf.append(0)
        gltf = dict(gltf)
        gltf["buffers"] = [{"byteLength": len(self.buf)}]
        gltf["bufferViews"] = self.views
        gltf["accessors"] = self.accessors
        js = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        js += b" " * (-len(js) % 4)
        total = 12 + 8 + len(js) + 8 + len(self.buf)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<I4s", len(js), b"JSON") + js)
            f.write(struct.pack("<I4s", len(self.buf), b"BIN\0") + bytes(self.buf))


# --- кватернионы (x, y, z, w) ---
def qmul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by,
                     aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw,
                     aw * bw - ax * bx - ay * by - az * bz])


def qnorm(q: np.ndarray) -> np.ndarray:
    return q / np.linalg.norm(q)


def qinv(q: np.ndarray) -> np.ndarray:
    return np.array([-q[0], -q[1], -q[2], q[3]]) / np.dot(q, q)


def qaxis(axis, deg: float) -> np.ndarray:
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis)
    h = np.radians(deg) / 2
    return np.array([*(axis * np.sin(h)), np.cos(h)])


def qeuler(xyz_deg) -> np.ndarray:
    """Поворот X, потом Y, потом Z (локальные оси кости)."""
    x, y, z = xyz_deg
    return qmul(qmul(qaxis([0, 0, 1], z), qaxis([0, 1, 0], y)), qaxis([1, 0, 0], x))


def qslerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        return qnorm(a + (b - a) * t)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def qmat(q: np.ndarray) -> np.ndarray:
    x, y, z, w = qnorm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def mat_to_q(m: np.ndarray) -> np.ndarray:
    m = m[:3, :3]
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    return qnorm(np.array(q))


def trs_mat(t, r, s) -> np.ndarray:
    m = np.eye(4)
    m[:3, :3] = qmat(np.asarray(r, float)) * np.asarray(s, float)
    m[:3, 3] = t
    return m


def globals_from_local(local: list[np.ndarray], parents: list[int]) -> list[np.ndarray]:
    out: list[np.ndarray | None] = [None] * len(local)

    def g(i):
        if out[i] is None:
            out[i] = local[i] if parents[i] < 0 else g(parents[i]) @ local[i]
        return out[i]

    for i in range(len(local)):
        g(i)
    return out  # type: ignore[return-value]


def sample_track(times: np.ndarray, values: np.ndarray, t: float, path: str, interp: str = "LINEAR") -> np.ndarray:
    if t <= times[0]:
        return values[0].copy()
    if t >= times[-1]:
        return values[-1].copy()
    k = int(np.searchsorted(times, t, side="right")) - 1
    if interp == "STEP":
        return values[k].copy()
    t0, t1 = times[k], times[k + 1]
    u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
    if path == "rotation":
        return qslerp(qnorm(values[k]), qnorm(values[k + 1]), u)
    return values[k] * (1 - u) + values[k + 1] * u


# --- стиль A: плоский цвет без бликов ---
def hex_to_linear(h: str) -> list[float]:
    h = h.lstrip("#")
    c = np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return [float(x) for x in lin]


def apply_style(gltf: dict, style: dict) -> list[str]:
    """Перекрашивает материалы по имени: цвет из палитры (sRGB hex), metallic/roughness из params.
    Возвращает имена материалов, которых нет в палитре."""
    params = style.get("params", {})
    missing = []
    for m in gltf.get("materials", []):
        spec = style.get("materials", {}).get(m.get("name", ""))
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if spec is None:
            missing.append(m.get("name", "?"))
        else:
            pbr["baseColorFactor"] = hex_to_linear(spec["color"]) + [1.0]
        pbr["metallicFactor"] = float(params.get("metallic", 0.0))
        pbr["roughnessFactor"] = float(params.get("roughness", 1.0))
    return missing
