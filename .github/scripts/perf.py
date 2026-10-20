#!/usr/bin/env python3
"""Числа PerfUITests из `xcresulttool get test-results metrics` (волны 26–27).

  perf.py print perf-2.json        строки «PERF <тест> | <метрика> = <среднее> (n, min, max)» — шаг «Perf metrics»
  perf.py ab out/perf              сводка A/B режима perf: файлы perf-<head|base>-<раунд>.json, оба сборки на
                                   одном раннере вперемешку (ABBA), поэтому сравниваем пары одного раунда, а не
                                   раннер с раннером (разброс между раннерами больше эффекта — RESEARCH/13-perf.md)
"""
import json
import pathlib
import re
import statistics
import sys


def rows(data):
    """(тест, метрика, единица, значения итераций) для каждой метрики каждого теста."""
    out = []

    def walk(x, test=None):
        if isinstance(x, dict):
            test = x.get("testIdentifier") or x.get("testIdentifierURL") or test
            runs = x.get("testRuns")
            if isinstance(runs, list):
                for run in runs:
                    for m in run.get("metrics", []):
                        vals = m.get("measurements") or []
                        if vals:
                            out.append((test, m.get("displayName"), m.get("unitOfMeasurement", ""), vals))
            for v in x.values():
                walk(v, test)
        elif isinstance(x, list):
            for v in x:
                walk(v, test)

    walk(data)
    return out


def cmd_print(path):
    data = json.load(open(path))
    found = rows(data)
    for test, name, unit, vals in found:
        mean = sum(vals) / len(vals)
        print(f"PERF {test} | {name} = {mean:.4g} {unit} (n={len(vals)}, min={min(vals):.4g}, max={max(vals):.4g})")
    if not found:
        print("строк метрик не нашлось, сырой JSON:")
        print(json.dumps(data, ensure_ascii=False)[:4000])


# Метрики, которые на симуляторе всегда 0 (CPU Cycles, Instructions Retired), в сводке A/B не нужны.
SKIP = re.compile(r"Cycles|Instructions", re.I)


def cmd_ab(folder):
    table = {}  # (тест, метрика, ед.) -> {сторона: {раунд: [значения]}}
    for f in sorted(pathlib.Path(folder).glob("perf-*-*.json")):
        m = re.fullmatch(r"perf-(head|base)-(\d+)\.json", f.name)
        if not m:
            continue
        side, rnd = m[1], int(m[2])
        try:
            data = json.load(open(f))
        except ValueError:
            print(f"{f.name}: не JSON, пропущен")
            continue
        for test, name, unit, vals in rows(data):
            if SKIP.search(name or ""):
                continue
            table.setdefault((test, name, unit), {}).setdefault(side, {})[rnd] = vals
    if not table:
        print("A/B: метрик нет")
        return
    print("A/B: среднее по итерациям каждого раунда; head — эта ветка, base — сравниваемый ref.")
    for (test, name, unit), sides in sorted(table.items()):
        h, b = sides.get("head", {}), sides.get("base", {})
        mh = {r: statistics.mean(v) for r, v in h.items()}
        mb = {r: statistics.mean(v) for r, v in b.items()}
        fmt = lambda d: " ".join(f"{d[r]:.3g}" for r in sorted(d)) or "—"
        line = f"AB {test} | {name} ({unit}) | head [{fmt(mh)}] | base [{fmt(mb)}]"
        pairs = [mh[r] / mb[r] for r in sorted(mh) if r in mb and mb[r]]
        if pairs:
            line += (f" | head/base по раундам [{' '.join(f'{p:.2f}' for p in pairs)}]"
                     f" медиана {statistics.median(pairs):.2f}")
        allh = [x for v in h.values() for x in v]
        allb = [x for v in b.values() for x in v]
        if allh and allb:
            line += f" | все итерации: head {statistics.median(allh):.3g}, base {statistics.median(allb):.3g} (медианы)"
        print(line)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("print", "ab"):
        sys.exit(__doc__)
    (cmd_print if sys.argv[1] == "print" else cmd_ab)(sys.argv[2])
