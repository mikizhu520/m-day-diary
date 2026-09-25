import SwiftUI

// MARK: - 写作热力图

/// 一格一天，颜色越深那天写得越多。
///
/// 布局跟 GitHub 的个人主页一个路数：横轴是「周」，纵轴是「星期几」，
/// 所以同一列永远是同一周，一眼能看出「最近是不是连着几天没写」。
///
/// 颜色不走红绿，而是品牌赤陶的透明度梯度 —— 深浅关系比色相更好读，
/// 也不至于跟「涨红跌绿」那套约定打架。
struct WritingHeatmap: View {
    /// 每天的写作字数，键是 `yyyy-MM-dd`
    var counts: [String: Int]
    /// 显示多少周（26 周 ≈ 半年）
    var weeks: Int = 26
    /// 点某一天。参数是那天的零点。
    var onPick: (Date) -> Void = { _ in }

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            monthRow
            HStack(alignment: .top, spacing: 4) {
                weekdayColumn
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                        VStack(spacing: gap) {
                            ForEach(Array(col.enumerated()), id: \.offset) { _, day in
                                cellView(day)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 格子

    @ViewBuilder
    private func cellView(_ day: Date?) -> some View {
        if let day {
            let words = counts[Fmt.day.string(from: day)] ?? 0
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(WritingHeatmap.levelColor(words))
                .frame(width: cell, height: cell)
                .overlay {
                    // 今天描一圈边，好在图里一眼找到自己站的位置
                    if Calendar.current.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Color.rjAccent, lineWidth: 1.4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onPick(day) }
                .help(WritingHeatmap.tip(day: day, words: words))
        } else {
            // 未来的日子留白，不画格子
            Color.clear.frame(width: cell, height: cell)
        }
    }

    // MARK: 左侧星期

    private var weekdayColumn: some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { i in
                Text(WritingHeatmap.weekdayLabel(i))
                    .font(.rj(8.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: cell, alignment: .trailing)
            }
        }
        .padding(.top, 0)
    }

    // MARK: 上方月份
    //
    // 这一行原来是 HStack + 每个标签一个 `frame(width: cell)`（11pt）。
    // 但「9月」两个字符在 9pt 字号下要 18pt 宽，比格子还宽 ——
    // Text 被压窄之后就只能折行或被切掉，用户看到的就是「热力图上面的日期没展示完整」。
    //
    // 改成：ZStack 里按精确 x 定位（x = 星期列宽 + 列号 × 格距），
    // 标签自己 `.fixedSize()` 保证不被压缩。这样它想写多宽就多宽，
    // 反正相邻两个月份标签之间至少隔 4 列（56pt），不会撞在一起。
    private var monthRow: some View {
        let labels = monthLabels()
        // 星期列（18）+ HStack 间距（4）
        let inset: CGFloat = 22
        let grid = CGFloat(weeks) * (cell + gap) - gap
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: grid + inset, height: 11)
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                if !label.isEmpty {
                    // 最后一个标签可能贴着右边界，往里收一点，别被裁掉尾字
                    let x = min(inset + CGFloat(idx) * (cell + gap), grid + inset - 22)
                    Text(label)
                        .font(.rj(9))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .offset(x: x)
                }
            }
        }
        .frame(height: 11, alignment: .topLeading)
    }

    /// 每列给一个月份标签，只有「这一列的周一换了月」才写出月份，其余留空 ——
    /// 每列都写会挤成一团。
    private func monthLabels() -> [String] {
        var out: [String] = []
        var lastMonth = -1
        let cal = Calendar.current
        for col in columns {
            let ref = col.compactMap { $0 }.first
            guard let ref else { out.append(""); continue }
            let m = cal.component(.month, from: ref)
            if m != lastMonth {
                out.append("\(m)月")
                lastMonth = m
            } else {
                out.append("")
            }
        }
        return out
    }

    // MARK: 日期网格

    /// 每列一周（周日在上），最后包含今天
    private var columns: [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 本周的周日
        let weekday = cal.component(.weekday, from: today)
        let thisSunday = cal.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        // 往前推 weeks-1 周，让最后一列正好是本周
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisSunday) ?? thisSunday

        var cols: [[Date?]] = []
        for w in 0..<weeks {
            var col: [Date?] = []
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                col.append(date > today ? nil : date)
            }
            cols.append(col)
        }
        return cols
    }

    // MARK: 分档

    /// 一档一档往上加。分界按「一天大概能写多少」来定：
    /// 100 字是随手记两笔，600 字往上基本是认真写过的。
    static func level(_ words: Int) -> Int {
        switch words {
        case ..<1: return 0
        case 1..<120: return 1
        case 120..<300: return 2
        case 300..<600: return 3
        default: return 4
        }
    }

    static func levelColor(_ words: Int) -> Color { legendColor(level(words)) }

    /// 按档取色。图例要用它 —— 图例直接传「代表色」，不用凑字数。
    static func legendColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.07)
        case 1: return Color.rjAccent.opacity(0.28)
        case 2: return Color.rjAccent.opacity(0.5)
        case 3: return Color.rjAccent.opacity(0.74)
        default: return Color.rjAccent
        }
    }

    static func tip(day: Date, words: Int) -> String {
        let d = Fmt.friendlyDay(day)
        if words <= 0 { return "\(d) · 没写" }
        return "\(d) · \(words) 字"
    }

    static func weekdayLabel(_ index: Int) -> String {
        // 只标三个，全标会糊成一片
        switch index {
        case 1: return "一"
        case 3: return "三"
        case 5: return "五"
        default: return ""
        }
    }
}
