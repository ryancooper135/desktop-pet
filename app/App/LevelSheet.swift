// Волна 34 I: лист «Уровень» — открывается тапом по «ур. 7» под кошельком (HomeChips.LevelChip).
// Сверху уровень и опыт «320 / 430» с полоской, сколько набрано сегодня из потолка 150, рост пса
// («Щенок · примерно 6 дней до подростка») и что даёт стадия. Ниже — что даст следующий уровень, лента ближайших
// открытий и за что дают опыт. Логика и тексты — LevelInfo (Shared), тут только вид. Только чтение: ничего не пишет.
// Волна 39 C: под шапкой — карточка «Достижения · 4 из 25», открывает AchievementsSheet поверх.

import SwiftUI
@preconcurrency import PetCore

struct LevelSheet: View {
    @Environment(AppModel.self) private var model
    @State private var showAchieve = false

    var body: some View {
        let now = model.snap.t
        ScrollView {
            VStack(spacing: 14) {
                if let f = model.file {
                    let p = DogLevel.progress(f)
                    header(p, f, now: now)
                    achieveCard(f)
                    growthCard(f)
                    nextCard(p)
                    sourcesCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("level.sheet")
        .sheet(isPresented: $showAchieve) {
            AchievementsSheet()
                .environment(model)
                .presentationDetents([.large])
        }
    }

    // MARK: достижения (волна 39 C)

    private func achieveCard(_ f: SaveFile) -> some View {
        let got = Achievements.gotCount(f), all = Achievements.all.count
        return Button {
            showAchieve = true
        } label: {
            card {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(PetPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Достижения")
                            .petFont(15, .semibold)
                            .foregroundStyle(PetPalette.ink)
                        Text("\(got) из \(all)")
                            .petFont(13, .medium)
                            .monospacedDigit()
                            .foregroundStyle(PetPalette.soft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PetPalette.soft)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Достижения: получено \(got) из \(all)")
        .accessibilityHint("Открыть список достижений")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("level.achievements")
    }

    // MARK: уровень и опыт

    private func header(_ p: LevelProgress, _ f: SaveFile, now: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                SheetCloseButton(id: "level.close")
            }
            Text("Уровень \(p.level)")
                .petFont(24, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("level.title")
            XpBar(fraction: p.fraction, height: 10)
                .padding(.horizontal, 24)
            Text(p.isMax ? "Это предел — выше уровней нет" : "Опыт \(LevelInfo.xpLine(p))")
                .petFont(15, .semibold)
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .accessibilityLabel(LevelInfo.xpSpeech(p))
                .accessibilityIdentifier("level.xp")
            Text(LevelInfo.todayLine(f, now: now))
                .petFont(13, .medium)
                .foregroundStyle(PetPalette.soft)
                .accessibilityIdentifier("level.today")
        }
    }

    // MARK: рост

    private func growthCard(_ f: SaveFile) -> some View {
        card {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LevelInfo.growthLine(f))
                        .petFont(15, .semibold)
                        .foregroundStyle(PetPalette.ink)
                    Text(LevelInfo.perksLine(Growth.phase(f)))
                        .petFont(13, .medium)
                        .foregroundStyle(PetPalette.soft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "ruler.fill")
                    .foregroundStyle(PetPalette.accent)
                    .accessibilityHidden(true)
            }
        }
        // Волна 36 O: одна фраза словами (без «·» и имени значка); id тот же — теперь на самом элементе,
        // а не на строке внутри .combine.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LevelInfo.growthSpeech(f))
        .accessibilityIdentifier("level.growth")
    }

    // MARK: что дальше

    private func nextCard(_ p: LevelProgress) -> some View {
        let feed = LevelInfo.upcoming(after: p.level)
        return card {
            VStack(alignment: .leading, spacing: 10) {
                title("Дальше")
                if p.isMax {
                    Text("Все уровни пройдены")
                        .petFont(14, .medium)
                        .foregroundStyle(PetPalette.soft)
                } else {
                    // Следующий уровень — всегда, даже без открытий: монеты за него есть всегда.
                    row(level: p.level + 1, unlocks: DogLevel.unlocks(p.level + 1), strong: true)
                        .accessibilityIdentifier("level.next")
                    ForEach(feed.filter { $0.level > p.level + 1 }) { s in
                        row(level: s.level, unlocks: s.unlocks, strong: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("level.feed")
    }

    private func row(level: Int, unlocks: [LevelUnlock], strong: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("ур. \(level)")
                .petFont(14, .bold)
                .monospacedDigit()
                .foregroundStyle(strong ? PetPalette.accent : PetPalette.soft)
                .frame(minWidth: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if !unlocks.isEmpty {
                    Text(unlocks.map(\.text).joined(separator: ", "))
                        .petFont(14, strong ? .semibold : .medium)
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(LevelInfo.rewardText(level))
                    .petFont(12, .medium)
                    .foregroundStyle(PetPalette.soft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LevelInfo.rowSpeech(level: level, unlocks: unlocks))
    }

    // MARK: за что опыт

    private func sourcesCard() -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                title("За что опыт")
                ForEach(LevelInfo.sources()) { s in
                    HStack(spacing: 8) {
                        Text(s.title)
                            .petFont(14, .medium)
                            .foregroundStyle(PetPalette.ink)
                        Spacer(minLength: 8)
                        Text(LevelInfo.sourceValue(s))
                            .petFont(13, .semibold)
                            .monospacedDigit()
                            .foregroundStyle(PetPalette.soft)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(LevelInfo.sourceSpeech(s))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("level.sources")
    }

    // MARK: общее

    private func title(_ text: String) -> some View {
        Text(text)
            .petFont(16, .bold)
            .foregroundStyle(PetPalette.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
    }
}
