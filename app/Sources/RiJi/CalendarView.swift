import SwiftUI

// MARK: - 日历视图（中栏）

struct CalendarPane: View {
    @EnvironmentObject var store: Store
    @Binding var selectedId: String?

    @State private var month = Date()
    @State private var selectedDay = Date()

    private let cal = Calendar.current
    private let weekNames = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            HairLine()
            weekdayHeader
            grid
            HairLine()
            dayList
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // 热力图点了某一天 → 跳过来选中它
        .onReceive(NotificationCenter.default.publisher(for: .rjCalendarDay)) { note in
            guard let d = note.object as? Date else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                selectedDay = d
                month = d
            }
        }
    }

    // MARK: 月份头

    private var monthHeader: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "chevron.left", help: "上个月", size: 26, iconSize: 12) {
                withAnimation(.easeOut(duration: 0.18)) {
                    month = cal.date(byAdding: .month, value: -1, to: month) ?? month
                }
            }

            Text(monthTitle).font(.rj(14.5, weight: .bold)).frame(minWidth: 100)

            IconButton(symbol: "chevron.right", help: "下个月", size: 26, iconSize: 12) {
                withAnimation(.easeOut(duration: 0.18)) {
                    month = cal.date(byAdding: .month, value: 1, to: month) ?? month
                }
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    month = Date()
                    selectedDay = Date()
                }
            } label: {
                Text("今天").font(.rj(12.5, weight: .semibold))
            }
            .buttonStyle(RJSubtleButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.rjBar)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekNames, id: \.self) { w in
                Text(w).font(.rj(11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: 网格

    private var grid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                cell(day)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func cell(_ day: Date?) -> some View {
        Group {
            if let day {
                let key = Fmt.day.string(from: day)
                CalendarCell(day: day,
                             isToday: cal.isDateInToday(day),
                             isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                             hasEntry: store.dayKeys.contains(key)) {
                    withAnimation(.easeOut(duration: 0.15)) { selectedDay = day }
                }
            } else {
                Color.clear.frame(height: CalendarCell.height)
            }
        }
    }

    private func monthDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let weekday = cal.component(.weekday, from: first)   // 1 = 周日
        let leading = (weekday + 5) % 7                       // 周一为第一列
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            out.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        return out
    }

    // MARK: 当天条目（农历 / 黄历 / 星座 / 日记）

    private var dayList: some View {
        let list = store.entries(on: selectedDay)
        let isToday = cal.isDateInToday(selectedDay)

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text(Fmt.friendlyDay(selectedDay)).font(.rj(12.5, weight: .bold))
                    Text("\(list.count) 篇").font(.rj(11)).foregroundStyle(.tertiary)
                    if let w = list.compactMap({ $0.weather }).first {
                        HStack(spacing: 3) {
                            Image(systemName: w.icon).font(.rj(11))
                            Text(w.summary).font(.rj(11))
                        }
                        .foregroundStyle(w.kind.tint)
                    }
                    Spacer(minLength: 0)
                }

                // 农历 + 节日 + 假期
                LunarDateLine(date: selectedDay)

                // 黄历
                AlmanacCard(date: selectedDay)

                // 星座运势。只对今天显示 —— 挑个历史日期看「今日运势」没有意义。
                if isToday {
                    ZodiacCard(date: selectedDay, birthday: store.settings.birthday)
                }

                HairLine().padding(.vertical, 2)

                entries(list)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func entries(_ list: [Entry]) -> some View {
        if list.isEmpty {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.05)).frame(width: 52, height: 52)
                    Image(systemName: "calendar.badge.plus").font(.rj(21, weight: .light)).foregroundStyle(.tertiary)
                }
                Text("这天没有日记").font(.rj(13)).foregroundStyle(.secondary)
                Button {
                    let e = store.createEntry(date: noon(of: selectedDay))
                    selectedId = e.id
                } label: {
                    Label("补写一篇", systemImage: "square.and.pencil").font(.rj(12.5, weight: .semibold))
                }
                .buttonStyle(RJSubtleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        } else {
            VStack(spacing: 6) {
                ForEach(list) { e in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selectedId = e.id }
                    } label: {
                        HStack(spacing: 9) {
                            Text(e.timeText).font(.rj(12, design: .rounded)).foregroundStyle(.tertiary)
                            Text(e.displayTitle).font(.rj(13.5, weight: .medium)).lineLimit(1)
                            Spacer()
                            if let w = e.weather {
                                Image(systemName: w.icon).font(.rj(12)).foregroundStyle(w.kind.tint)
                            }
                            if !e.mood.isEmpty { Text(e.mood).font(.rj(12.5)) }
                        }
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .card(selected: selectedId == e.id)
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.985, pressedOpacity: 0.95))
                }
            }
        }
    }

    private func noon(of date: Date) -> Date {
        var c = cal.dateComponents([.year, .month, .day], from: date)
        let now = cal.dateComponents([.hour, .minute], from: Date())
        c.hour = now.hour
        c.minute = now.minute
        return cal.date(from: c) ?? date
    }
}

// MARK: - 统计视图（详情栏）

struct StatsView: View {
    @EnvironmentObject var store: Store

    /// 热力图显示多少周：半年 / 一年
    @State private var heatWeeks = 26

    /// 每天写了多少字（键是 yyyy-MM-dd）
    private var heatCounts: [String: Int] {
        var m: [String: Int] = [:]
        for e in store.entries { m[e.dayKey, default: 0] += e.wordCount }
        return m
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("统计").font(.rj(20.5, weight: .bold, design: .rounded))

                HStack(spacing: 12) {
                    statCard("全部日记", "\(store.entries.count)", "篇", "books.vertical.fill", .blue)
                    statCard("累计字数", "\(store.totalWords())", "字", "character", .orange)
                    statCard("连续记录", "\(store.streak)", "天", "flame.fill", .red)
                    statCard("标签", "\(store.allTags.count)", "个", "number", .purple)
                }

                if !last30.isEmpty {
                    card("写作热力图") {
                        VStack(alignment: .leading, spacing: 9) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                WritingHeatmap(counts: heatCounts, weeks: heatWeeks) { date in
                                    // 点某天 → 切到日历页并选中那天
                                    NotificationCenter.default.post(name: .rjScopeCalendar, object: nil)
                                    NotificationCenter.default.post(name: .rjCalendarDay, object: date)
                                }
                            }

                            HStack(spacing: 6) {
                                Text("少").font(.rj(10)).foregroundStyle(.tertiary)
                                ForEach(0..<5, id: \.self) { lv in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(WritingHeatmap.legendColor(lv))
                                        .frame(width: 11, height: 11)
                                }
                                Text("多").font(.rj(10)).foregroundStyle(.tertiary)

                                Spacer(minLength: 8)

                                Picker("", selection: $heatWeeks) {
                                    Text("半年").tag(26)
                                    Text("一年").tag(53)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 118)
                            }

                            Text("每一格是一天，颜色越深那天写得越多。点一下可以跳到那天。")
                                .font(.rj(10.5))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }

                if !last30.isEmpty {
                    card("最近 30 天记录情况") {
                        let maxV = max(last30.map { $0.1 }.max() ?? 1, 1)
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(last30.enumerated()), id: \.offset) { _, item in
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(item.1 == 0 ? Color.secondary.opacity(0.15) : Color.rjAccent.opacity(0.85))
                                        .frame(height: max(3, CGFloat(item.1) / CGFloat(maxV) * 62))
                                    Text(item.0)
                                        .font(.rj(8))
                                        .foregroundStyle(.quaternary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 86, alignment: .bottom)
                    }
                }

                if !journalStats.isEmpty {
                    card("日记本分布") {
                        VStack(spacing: 8) {
                            ForEach(journalStats, id: \.0) { name, count, color in
                                HStack(spacing: 8) {
                                    JournalDot(color: color, size: 7)
                                    Text(name).font(.rj(12.5)).frame(width: 66, alignment: .leading)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.secondary.opacity(0.12))
                                            Capsule().fill(color.opacity(0.85))
                                                .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(max(store.entries.count, 1))))
                                        }
                                    }
                                    .frame(height: 8)
                                    Text("\(count) 篇").font(.rj(11.5)).foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                                }
                            }
                        }
                    }
                }

                if !allTagStats.isEmpty {
                    card("常用标签") {
                        FlowTags(tags: allTagStats)
                    }
                }

                card("写作习惯") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("平均每篇", "\(avgWords) 字")
                        infoRow("最长一篇", "\(store.entries.map { $0.wordCount }.max() ?? 0) 字")
                        infoRow("最常写的时间", mostActiveHour)
                        infoRow("有记录的天数", "\(store.dayKeys.count) 天")
                    }
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 组件

    private func statCard(_ title: String, _ value: String, _ unit: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.rj(11)).foregroundStyle(color)
                Text(title).font(.rj(11.5)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.rj(23.5, weight: .bold, design: .rounded))
                Text(unit).font(.rj(11.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.rj(13, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.rj(12.5)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.rj(12.5, weight: .medium))
        }
    }

    // MARK: 数据

    private var last30: [(String, Int)] {
        let cal = Calendar.current
        var out: [(String, Int)] = []
        for i in stride(from: 29, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let key = Fmt.day.string(from: day)
            let count = store.entries.filter { $0.dayKey == key }.count
            let label = "\(cal.component(.day, from: day))"
            out.append((label, count))
        }
        return out
    }

    private var journalStats: [(String, Int, Color)] {
        store.journals.map { j in
            (j.name, store.entries.filter { $0.journalId == j.id }.count, Color(hex: j.colorHex))
        }.filter { $0.1 > 0 }
    }

    private var allTagStats: [(String, Int)] { Array(store.allTags.prefix(20)) }

    private var avgWords: Int {
        guard !store.entries.isEmpty else { return 0 }
        return store.totalWords() / store.entries.count
    }

    private var mostActiveHour: String {
        var buckets: [Int: Int] = [:]
        for e in store.entries {
            let h = Calendar.current.component(.hour, from: e.createdAt)
            buckets[h, default: 0] += 1
        }
        guard let best = buckets.max(by: { $0.value < $1.value })?.key else { return "—" }
        return String(format: "%02d:00 – %02d:00", best, (best + 1) % 24)
    }
}

// MARK: - 标签流式布局

struct FlowTags: View {
    var tags: [(String, Int)]

    var body: some View {
        var rows: [[(String, Int)]] = []
        var current: [(String, Int)] = []
        var width = 0
        for t in tags {
            let w = t.0.count * 11 + 34
            if width + w > 520 && !current.isEmpty {
                rows.append(current); current = []; width = 0
            }
            current.append(t); width += w
        }
        if !current.isEmpty { rows.append(current) }

        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.0) { tag, count in
                        HStack(spacing: 4) {
                            Text("#\(tag)").font(.rj(12))
                            Text("\(count)").font(.rj(10.5)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.rjAccent.opacity(0.10)))
                        .foregroundStyle(Color.rjAccent)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - 日历格子

struct CalendarCell: View {
    var day: Date
    var isToday: Bool
    var isSelected: Bool
    var hasEntry: Bool
    var action: () -> Void

    @State private var hovering = false

    /// 格子高度。比原来高 —— 多了一行农历，不抬高点会挤成一条线。
    static let height: CGFloat = 46

    private var almanac: AlmanacDay { Almanac.day(day) }
    private var mark: HolidayMark? { Holiday.mark(day) }

    /// 副行文字。优先级：调休 > 节日 > 节气 > 初一显示月名 > 农历日
    private var subText: String {
        if let m = mark, !m.isRest { return "班" }
        let a = almanac
        if let f = a.festivals.first { return CalendarCell.short(f) }
        if !a.term.isEmpty { return a.term }
        if a.lunarDayName == "初一" { return a.lunarMonthName }
        return a.lunarDayName
    }

    private var subColor: Color {
        if isSelected { return Color.white.opacity(0.85) }
        if let m = mark { return m.isRest ? Color.rjAccent.opacity(0.9) : .secondary }
        let a = almanac
        if !a.festivals.isEmpty || !a.term.isEmpty { return Color.rjAccent.opacity(0.85) }
        return Color.secondary.opacity(0.7)
    }

    /// 休息日（和周末无关，只认放假安排）用红字，符合「红字即休」的习惯
    private var isRedDay: Bool {
        if isSelected { return true }
        if isToday { return true }
        if let m = mark { return m.isRest }
        return false
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(Almanac.gregorian.component(.day, from: day))")
                    .font(.rj(13, weight: isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isRedDay ? Color.rjAccent : Color.primary)

                Text(subText)
                    .font(.rj(9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(subColor)

                Circle()
                    .fill(hasEntry ? (isSelected ? Color.white : Color.rjAccent) : Color.clear)
                    .frame(width: 4, height: 4)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(Color.rjAccent)
                          : AnyShapeStyle(isToday ? Color.rjAccent.opacity(0.12)
                                          : (hovering ? Color.primary.opacity(0.07) : Color.clear)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Color.rjAccent.opacity(0.45) : Color.clear,
                                  lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .help(tip)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.92))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    private var tip: String {
        var s = Fmt.day.string(from: day) + " " + almanac.lunarText
        if let f = almanac.festivals.first { s += " · \(f)" }
        if !almanac.term.isEmpty { s += " · \(almanac.term)" }
        if let m = mark { s += " · \(m.label)" }
        return s
    }

    /// 节日名太长会把格子撑破，这里用简称
    private static let shortFestivals: [String: String] = [
        "中秋节": "中秋", "国庆节": "国庆", "清明节": "清明", "端午节": "端午",
        "元宵节": "元宵", "重阳节": "重阳", "中元节": "中元", "腊八节": "腊八",
        "劳动节": "劳动", "儿童节": "儿童", "教师节": "教师", "妇女节": "妇女",
        "建党节": "建党", "建军节": "建军", "植树节": "植树", "情人节": "情人",
        "圣诞节": "圣诞",
    ]

    static func short(_ f: String) -> String { shortFestivals[f] ?? f }
}
