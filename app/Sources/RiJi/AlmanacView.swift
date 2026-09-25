import SwiftUI

// MARK: - 农历 · 黄历 · 星座 的展示组件

/// 一行式农历日期：「八月十五」+ 节日 + 假期
///
/// `flush = true` 时结尾不撑开 —— 给「日期 / 篇数 / 天气 / 农历 / 节日 / 休」
/// 全挤在一行的场景用（日历那天列表的抬头）。
struct LunarDateLine: View {
    var date: Date
    var compact = false
    var flush = false

    private var almanac: AlmanacDay { Almanac.day(date) }

    var body: some View {
        let a = almanac
        let mark = Holiday.mark(date)

        HStack(spacing: 6) {
            Text(a.lunarText)
                .font(.rj(compact ? 11 : 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let f = a.festivals.first {
                Text(f)
                    .font(.rj(compact ? 10.5 : 11, weight: .medium))
                    .foregroundStyle(Color.rjAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.rjAccent.opacity(0.12)))
                    .lineLimit(1)
            }

            if let m = mark {
                Text(m.isRest ? "休" : "班")
                    .font(.rj(compact ? 9.5 : 10, weight: .bold))
                    .foregroundStyle(m.isRest ? .white : Color.secondary)
                    .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
                    .background(Circle().fill(m.isRest ? Color.rjAccent : Color.primary.opacity(0.10)))
                    .help(m.label)
            }

            if !a.term.isEmpty {
                Text(a.term)
                    .font(.rj(compact ? 10.5 : 11, weight: .medium))
                    .foregroundStyle(Color.rjAccent.opacity(0.85))
                    .lineLimit(1)
            }

            if !flush { Spacer(minLength: 0) }
        }
        // 挤在一行时，狭窄了宁可截断农历也不要换行
        .lineLimit(1)
    }
}

/// 黄历卡片：干支、值神、建除、宜忌、冲煞
struct AlmanacCard: View {
    var date: Date

    @State private var expanded = false

    private var a: AlmanacDay { Almanac.day(date) }

    var body: some View {
        let d = a
        VStack(alignment: .leading, spacing: 9) {
            header(d)
            HairLine()
            suitability(d)
            footer(d)
        }
        .padding(12)
        .rjPanel()
    }

    // MARK: 头部

    private func header(_ d: AlmanacDay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.rj(12))
                    .foregroundStyle(Color.rjAccent)
                Text(d.lunarText)
                    .font(.rj(14, weight: .bold))
                if let f = d.festivals.first {
                    Text(f)
                        .font(.rj(11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.rjAccent))
                }
                Spacer()
                if let m = Holiday.mark(date) {
                    Text(m.label)
                        .font(.rj(10.5, weight: .medium))
                        .foregroundStyle(m.isRest ? Color.rjAccent : Color.secondary)
                }
            }

            HStack(spacing: 8) {
                Text(d.ganzhiLine).font(.rj(11)).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                tag(d.deity, tint: d.isYellowRoad ? Color.rjAccent : Color.secondary)
                tag("\(d.officer)日", tint: .secondary)
                tag("冲\(d.clashZodiac)", tint: .secondary)
                if !d.term.isEmpty { tag("今日\(d.term)", tint: Color.rjAccent) }
                else if d.daysToNextTerm > 0 {
                    Text("距\(d.nextTerm) \(d.daysToNextTerm) 天")
                        .font(.rj(10.5)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.rj(10.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.11)))
    }

    // MARK: 宜忌

    private func suitability(_ d: AlmanacDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            row(title: "宜", color: Color.rjAccent, items: d.suitable)
            row(title: "忌", color: Color.secondary, items: d.avoid)
        }
    }

    private func row(title: String, color: Color, items: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.rj(11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color))
                .padding(.top, 1)

            // 折叠时只露前面几条，展开看全部 —— 一行塞不下七八个词
            InlineTags(items: items, tint: color, limit: expanded ? 99 : 5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if items.count > 5 {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.rj(9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: 脚注

    private func footer(_ d: AlmanacDay) -> some View {
        Text("黄历宜忌属民间传统说法，各流派并不一致，这里只作参考。")
            .font(.rj(10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 星座运势卡

struct ZodiacCard: View {
    var date: Date
    /// 设置里的生日（"1992-06-23" 这种），空着就用当天的太阳星座
    var birthday: String

    private var sign: ZodiacSign {
        if let b = Zodiac.sign(fromBirthday: birthday) { return b }
        return Zodiac.sign(for: date)
    }

    private var isOwn: Bool { Zodiac.sign(fromBirthday: birthday) != nil }

    var body: some View {
        let s = sign
        let f = Zodiac.fortune(for: s, date: date)

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(s.emoji)
                    .font(.rj(17))
                    .foregroundStyle(Color.rjAccent)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(s.name).font(.rj(13.5, weight: .bold))
                        Text(s.element).font(.rj(10)).foregroundStyle(.tertiary)
                    }
                    Text(isOwn ? "你的星座 · \(s.dateRange)" : "今天的太阳星座 · \(s.dateRange)")
                        .font(.rj(10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                starsRow(f.stars)
            }

            Text(f.summary)
                .font(.rj(12))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                detail("感情", f.love)
                detail("事业", f.career)
                detail("财运", f.money)
            }

            HStack(spacing: 10) {
                Text("幸运色 \(f.luckyColor)").font(.rj(10.5)).foregroundStyle(.secondary)
                Text("幸运数字 \(f.luckyNumber)").font(.rj(10.5)).foregroundStyle(.secondary)
                Spacer()
            }

            Text(isOwn
                 ? "运势属娱乐向，没有天文或统计依据，看着玩玩就好。"
                 : "想看自己星座的运势？在设置里填上生日就行。")
                .font(.rj(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .rjPanel()
    }

    private func starsRow(_ n: Int) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < n ? "star.fill" : "star")
                    .font(.rj(9))
                    .foregroundStyle(i < n ? Color.rjAccent : Color.secondary.opacity(0.35))
            }
        }
        .help("综合指数 \(n)/5")
    }

    private func detail(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(title)
                .font(.rj(10.5, weight: .semibold))
                .foregroundStyle(Color.rjAccent)
                .frame(width: 26, alignment: .leading)
            Text(text)
                .font(.rj(11.5))
                .foregroundStyle(.primary.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 行内标签（会自动折行）

/// 一排小胶囊。宽度是估的 —— 精确测量要走到 Layout 协议，
/// 为几个词不值当，宁可留点余量。
struct InlineTags: View {
    var items: [String]
    var tint: Color
    var limit: Int = 99
    /// 认为一行能放下多少点宽度。给宽处留了余量。
    var rowWidth: CGFloat = 260

    var body: some View {
        let shown = Array(items.prefix(limit))
        var rows: [[String]] = []
        var current: [String] = []
        var used: CGFloat = 0
        for s in shown {
            // 中文按字号估宽，再加胶囊的左右内边距
            let w = CGFloat(s.count) * 11 + 16
            if used + w > rowWidth && !current.isEmpty {
                rows.append(current); current = []; used = 0
            }
            current.append(s); used += w + 5
        }
        if !current.isEmpty { rows.append(current) }

        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, s in
                        Text(s)
                            .font(.rj(10.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.11)))
                            .foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                }
            }
            if items.count > limit {
                Text("等 \(items.count) 项")
                    .font(.rj(10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
