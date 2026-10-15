# PROGRESS

## Ждёт Вадима
- **Поставить зонд на iPhone** и пройти чек-лист из `probe/README.md`: файл `builds/PetProbe-0.1.ipa`, ставить через Sideloadly своим Apple ID (вход — только сам). Прислать скрины разделов 1–3.

## Журнал

### 15.10.2026
- Получено ТЗ (PROMPT.md) и референсы стиля (refs/).
- Заведён git-репо, документы VISION / ROADMAP / DECISIONS / PROGRESS / ECONOMY.
- Relay-тулбокс: по iOS/виджетам/тамагочи готового нет; есть `gen_image.py` (картинки через Codex) — пригодится для концептов.
- На ПК нет Blender и GitHub CLI — понадобятся для пайплайна ассетов и CI.
- Запущены исследования этапа 1 (5 направлений) → RESEARCH/.
- Написана сборка-зонд `probe/` (XcodeGen: приложение + одно расширение с виджетом, Live Activity и кнопкой Пункта управления, App Group с поиском реального ID в рантайме, шаги, уведомления, «Команды») и workflow `.github/workflows/probe-ipa.yml` (неподписанный .ipa + ad-hoc подпись с entitlements). Инструкция и чек-лист — `probe/README.md`. Ещё не собиралась ни разу.
- Создан приватный репо ryancooper135/desktop-pet, первая облачная сборка зонда прошла (Xcode 26.6, 27 с): в .ipa приложение + appex, entitlements с группой на месте. Файл — `builds/PetProbe-0.1.ipa`.
- Готовы исследования 01 (подпись), 02 (iOS), 05 (сервер) → выводы в DECISIONS.md.
