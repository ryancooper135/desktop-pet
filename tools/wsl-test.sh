#!/usr/bin/env bash
# Логика приложения и её тесты на Linux у себя (WSL, Swift 6.2 в /opt/swift-6.2.4) — то же, что logic.yml в CI.
# Запуск из Windows:  wsl -e bash /mnt/c/Users/ryanc/desktop-pet/tools/wsl-test.sh [папка-репо] [фильтр тестов]
# Код копируется в ~/petbuild/<имя папки>: сборка с /mnt/c в разы медленнее, а .build там переживает перезапуски.
# Полные логи — ~/petbuild/<имя>/build.log и test.log.
set -uo pipefail
src="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
filter="${2:-}"
dst="$HOME/petbuild/$(basename "$src")"
mkdir -p "$dst"
rsync -a --delete --exclude .git --exclude .build --exclude builds --exclude node_modules \
  --exclude RESEARCH --exclude refs --exclude .claude --exclude build.log --exclude test.log "$src/" "$dst/"
cd "$dst/app"
if ! swift build --build-tests >"$dst/build.log" 2>&1; then
  grep -E "error:" "$dst/build.log" | sort -u | head -40
  echo "СБОРКА УПАЛА (полный лог: $dst/build.log)"
  exit 1
fi
args=(--skip-build)
[ -n "$filter" ] && args+=(--filter "$filter")
swift test "${args[@]}" >"$dst/test.log" 2>&1
rc=$?
grep -E "error:|failed \(|Executed [0-9]+ tests" "$dst/test.log" | tail -40
exit $rc
