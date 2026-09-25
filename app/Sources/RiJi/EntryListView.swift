import SwiftUI

// MARK: - 条目列表（中栏）

struct EntryListView: View {
    @EnvironmentObject var store: Store
    var title: String
    var subtitle: String
    var entries: [Entry]
    @Binding var selectedId: String?
    var emptySymbol: String = "square.and.pencil"
    var emptyTitle: String = "这里还没有日记"
    var emptySubtitle: String = "点击下面的按钮，写下第一篇"
    var onCreate: (() -> Void)? = nil
    var showDayHeader: Bool = true

    /// 排序方式。选完记在 UserDefaults 里，下次打开还是它。
    @AppStorage(EntrySort.storageKey) private var sortRaw: String = EntrySort.newest.rawValue
    private var sort: EntrySort { EntrySort(rawValue: sortRaw) ?? .newest }
    /// 按字数 / 标题排的时候不插日期表头
    private var groupByDay: Bool { showDayHeader && sort.groupsByDay }

    private var grouped: [(String, [Entry])] {
        var order: [String] = []
        var map: [String: [Entry]] = [:]
        // 先排序、再按天归拢 —— 这样「组的先后」自动跟着排序规则走，
        // 不用再单独去反转日期数组
        for e in sort.apply(entries) {
            if map[e.dayKey] == nil { order.append(e.dayKey) }
            map[e.dayKey, default: []].append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: title, subtitle: subtitle) {
                sortMenu
                if let onCreate {
                    IconButton(symbol: "plus", help: "新建日记 (⌘N)",
                               active: true, size: 30, iconSize: 13, action: onCreate)
                }
            }
            HairLine()
            if entries.isEmpty {
                EmptyHint(symbol: emptySymbol, title: emptyTitle, subtitle: emptySubtitle,
                          actionTitle: onCreate == nil ? nil : "写一篇",
                          action: onCreate)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8, pinnedViews: groupByDay ? [.sectionHeaders] : []) {
                        ForEach(grouped, id: \.0) { day, list in
                            if groupByDay {
                                Section {
                                    VStack(spacing: 8) {
                                        ForEach(list) { e in card(e) }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 8)
                                } header: {
                                    dayHeader(day, list: list)
                                }
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(list) { e in card(e) }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 表头右上角的排序菜单
    private var sortMenu: some View {
        Menu {
            Picker("排序方式", selection: $sortRaw) {
                ForEach(EntrySort.allCases) { s in
                    Label(s.name, systemImage: s.symbol).tag(s.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.rj(12, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("排序方式（当前：\(sort.name)）")
    }

    private func dayHeader(_ day: String, list: [Entry]) -> some View {
        HStack(spacing: 7) {
            let date = Fmt.day.date(from: day) ?? Date()
            Text(Fmt.friendlyDay(date))
                .font(.rj(12, weight: .bold))
                .foregroundStyle(.secondary)
            if list.count > 1 {
                Text("\(list.count) 篇")
                    .font(.rj(11.5))
                    .foregroundStyle(.tertiary)
            }
            if let w = list.compactMap({ $0.weather }).first {
                HStack(spacing: 3) {
                    Image(systemName: w.icon).font(.rj(11.5))
                    Text(w.summary).font(.rj(11.5))
                }
                .foregroundStyle(w.kind.tint)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .background(Color.rjBar)
    }

    // MARK: 卡片

    private func card(_ e: Entry) -> some View {
        let selected = selectedId == e.id
        let journal = store.journal(for: e.journalId)
        let accent = journal.map { Color(hex: $0.colorHex) } ?? .rjAccent
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedId = e.id }
        } label: {
            EntryCardBody(entry: e, selected: selected)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 选中时是淡淡一层本色底 + 本色描边，字色照常（见 CardBackground / CardInk）
                .card(selected: selected, accent: accent)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.985, pressedOpacity: 0.95))
        .contextMenu {
            Menu("移动到") {
                ForEach(store.journals) { j in
                    Button(j.name) { store.move(e, to: j.id) }
                }
            }
            Divider()
            Button("删除", role: .destructive) {
                store.delete(e)
                if selectedId == e.id { selectedId = nil }
            }
        }
    }
}

// MARK: - 搜索结果

struct SearchResultsView: View {
    @EnvironmentObject var store: Store
    var query: String
    @Binding var selectedId: String?

    var body: some View {
        let results = store.search(query)
        VStack(spacing: 0) {
            ColumnHeader(title: "搜索「\(query)」", subtitle: "\(results.count) 条结果")
            HairLine()
            if results.isEmpty {
                EmptyHint(symbol: "magnifyingglass", title: "没找到相关内容", subtitle: "换个词试试，或者检查一下标签")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results) { e in
                            resultRow(e)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func resultRow(_ e: Entry) -> some View {
        let selected = selectedId == e.id
        let ink = CardInk(selected: selected)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedId = e.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(e.displayTitle)
                        .font(.rj(14, weight: .semibold))
                        .foregroundStyle(ink.title)
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.day.string(from: e.createdAt))
                        .font(.rj(11.5, design: .rounded)).foregroundStyle(ink.faint)
                }
                Text(highlighted(e))
                    .font(.rj(12.5))
                    .foregroundStyle(ink.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(selected: selected)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.985, pressedOpacity: 0.95))
    }

    private func highlighted(_ e: Entry) -> String {
        let plain = e.plainText
        guard let range = plain.range(of: query, options: [.caseInsensitive]) else {
            return String(plain.prefix(140))
        }
        let start = plain.index(range.lowerBound, offsetBy: -50, limitedBy: plain.startIndex) ?? plain.startIndex
        let end = plain.index(range.upperBound, offsetBy: 90, limitedBy: plain.endIndex) ?? plain.endIndex
        var snippet = String(plain[start..<end])
        if start != plain.startIndex { snippet = "…" + snippet }
        if end != plain.endIndex { snippet += "…" }
        return snippet.replacingOccurrences(of: "\n", with: " ")
    }
}
