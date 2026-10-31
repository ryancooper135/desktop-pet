#!/usr/bin/env python3
"""Из чего состоит вес ipa (волна 56, RESEARCH/56-lightness.md).

  python -I tools/ipa_size.py Pet.ipa [--top 25] [--budget 40]

Печатает: вес ipa (то, что качается и ставится), вес приложения после распаковки, топ файлов — сколько каждый
весит в распакованном виде и сколько сжатым в ipa, сумму по группам (бинарь, 3D, музыка, данные, картинки) и
разбор Mach-O бинарей: сегменты и таблицу символов (Release-сборка `xcodebuild build` без archive не стрипает
символы). Ничего не запускает и не распаковывает на диск — только читает zip.
--budget N: выйти с кодом 1, если ipa тяжелее N МБ (бюджет волны 56; так job ipa в CI ловит раздувание).
"""
import collections
import io
import pathlib
import struct
import sys
import zipfile

GROUPS = [
    ("бинарь", lambda n, data: data[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")),
    ("3D (usdz)", lambda n, data: n.endswith(".usdz")),
    ("музыка и звук", lambda n, data: n.endswith((".m4a", ".mp3", ".wav", ".caf", ".aac", ".ogg"))),
    ("данные (json)", lambda n, data: n.endswith(".json")),
    ("картинки", lambda n, data: n.endswith((".png", ".jpg", ".jpeg", ".heic", ".car", ".webp"))),
    ("шрифты", lambda n, data: n.endswith((".ttf", ".otf", ".woff", ".woff2"))),
]


def mb(x):
    return f"{x / 1e6:.2f} МБ"


def macho(name, b):
    """Сегменты, крупные секции и таблица символов одного тонкого arm64 Mach-O."""
    magic = struct.unpack_from("<I", b, 0)[0]
    if magic != 0xFEEDFACF:
        print(f"  {name}: не тонкий 64-битный Mach-O (magic {magic:#x})")
        return
    ncmds = struct.unpack_from("<I", b, 16)[0]
    off, segs, secs, sym = 32, [], [], None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", b, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            seg = b[off + 8:off + 24].rstrip(b"\0").decode()
            filesize = struct.unpack_from("<Q", b, off + 48)[0]
            segs.append((seg, filesize))
            nsects = struct.unpack_from("<I", b, off + 64)[0]
            for s in range(nsects):
                so = off + 72 + s * 80
                sect = b[so:so + 16].rstrip(b"\0").decode()
                secs.append((f"{seg},{sect}", struct.unpack_from("<Q", b, so + 40)[0]))
        elif cmd == 0x2:  # LC_SYMTAB
            _, nsyms, _, strsize = struct.unpack_from("<IIII", b, off + 8)
            sym = (nsyms, nsyms * 16 + strsize)
        off += size
    print(f"  {name}: {mb(len(b))}")
    print("    сегменты: " + ", ".join(f"{s} {mb(z)}" for s, z in segs if z))
    big = sorted(secs, key=lambda x: -x[1])[:8]
    print("    крупные секции: " + ", ".join(f"{s} {mb(z)}" for s, z in big))
    if sym:
        print(f"    символы: {sym[0]} шт., таблица + строки ≈ {mb(sym[1])}")


def main(path, top=25, budget=None):
    ipa = pathlib.Path(path)
    z = zipfile.ZipFile(ipa)
    infos = [i for i in z.infolist() if not i.is_dir()]
    total_u = sum(i.file_size for i in infos)
    total_c = sum(i.compress_size for i in infos)
    print(f"ipa: {mb(ipa.stat().st_size)} ({ipa.stat().st_size} Б); после установки ≈ {mb(total_u)}; "
          f"файлов {len(infos)}")
    print(f"\nтоп {top} файлов: распакованный | в ipa | файл")
    for i in sorted(infos, key=lambda i: -i.compress_size)[:top]:
        print(f"  {mb(i.file_size):>10} | {mb(i.compress_size):>10} | {i.filename.split('Pet.app/', 1)[-1]}")
    groups = collections.defaultdict(lambda: [0, 0, 0])
    binaries = []
    for i in infos:
        data = z.read(i)
        name = i.filename.split("Pet.app/", 1)[-1]
        g = next((g for g, test in GROUPS if test(name, data)), "прочее")
        groups[g][0] += i.file_size
        groups[g][1] += i.compress_size
        groups[g][2] += 1
        if g == "бинарь":
            binaries.append((name, data))
    print("\nпо группам: распакованный | в ipa | доля ipa | файлов")
    for g, (u, c, n) in sorted(groups.items(), key=lambda x: -x[1][1]):
        print(f"  {g:16} {mb(u):>10} | {mb(c):>10} | {100 * c / total_c:5.1f} % | {n}")
    print("\nбинари:")
    for name, data in binaries:
        macho(name, data)
    if budget is not None:
        size = ipa.stat().st_size / 1e6
        verdict = "в бюджете" if size <= budget else "ТЯЖЕЛЕЕ БЮДЖЕТА"
        print(f"\nбюджет ipa {budget:g} МБ, факт {size:.2f} МБ — {verdict}")
        if size > budget:
            sys.exit(1)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")  # консоль Windows в cp1251, а `-I` игнорирует PYTHONIOENCODING
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        sys.exit(__doc__)
    n = int(args[args.index("--top") + 1]) if "--top" in args else 25
    budget = float(args[args.index("--budget") + 1]) if "--budget" in args else None
    main(args[0], n, budget)
