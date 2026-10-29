#!/usr/bin/env python3
"""Время каждого теста из `xcresulttool get test-results tests` (волна 45 P).

  test_times.py tests-3.json [N]   сумма по классам и N самых долгих тестов (по умолчанию 15) — шаг «Test times»

xcodebuild идёт с -quiet, и без этого шага время теста видно только в xcresult. Нужен для балансировки шардов
(RESEARCH/11-ci-testing.md, «Минуты») и чтобы видеть тесты, подошедшие к потолку execution time allowance.
"""
import json
import re
import sys
from collections import defaultdict


def seconds(node):
    """Длительность узла в секундах: durationInSeconds, иначе разбор строки «1m 2s» / «12s» / «0,5s»."""
    v = node.get("durationInSeconds")
    if isinstance(v, (int, float)):
        return float(v)
    text = str(node.get("duration") or "")
    total = 0.0
    for num, unit in re.findall(r"([\d.,]+)\s*(h|min|m|s)", text):
        n = float(num.replace(",", "."))
        total += n * {"h": 3600, "min": 60, "m": 60, "s": 1}[unit]
    return total


def cases(data):
    """(класс, тест, секунды, результат) для каждого Test Case."""
    out = []

    def walk(x, suite=None):
        if isinstance(x, dict):
            kind = x.get("nodeType")
            if kind == "Test Suite":
                suite = x.get("name") or suite
            if kind == "Test Case":
                out.append((suite or "?", x.get("name") or "?", seconds(x), x.get("result") or "?"))
                return
            for v in x.get("children") or []:
                walk(v, suite)
            for v in x.get("testNodes") or []:
                walk(v, suite)
        elif isinstance(x, list):
            for v in x:
                walk(v, suite)

    walk(data)
    return out


def main():
    path = sys.argv[1]
    top = int(sys.argv[2]) if len(sys.argv) > 2 else 15
    rows = cases(json.load(open(path)))
    if not rows:
        print("тестов в xcresult нет")
        return
    by_class = defaultdict(float)
    for suite, _, sec, _ in rows:
        by_class[suite] += sec
    total = sum(by_class.values())
    print(f"TIME всего {total / 60:.1f} мин, тестов {len(rows)}")
    for suite, sec in sorted(by_class.items(), key=lambda kv: -kv[1]):
        print(f"TIME класс {suite}: {sec / 60:.1f} мин")
    for suite, name, sec, result in sorted(rows, key=lambda r: -r[2])[:top]:
        print(f"TIME тест {suite}/{name}: {sec:.0f} с ({result})")


if __name__ == "__main__":
    main()
