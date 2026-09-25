import SwiftUI

// MARK: - 浏览范围

enum Scope: Hashable {
    case today
    case all
    case onThisDay
    case calendar
    case stats
    case journal(String)
    case tag(String)
}

// MARK: - 侧边栏

struct SidebarView: View {
    @EnvironmentObject var store: Store
    @Binding var scope: Scope?

    /// 正在被拖动的日记本
    @State private var draggingJournalId: String?
    /// 当前落点（哪一行的上方 / 下方）
    @State private var dropMark: JournalDropMark?
    /// 日记本行的高度（量出来的，用来判断落点在上半还是下半）
    @State private var journalRowHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    browseSection
                    journalsSection
                    if !store.allTags.isEmpty { tagsSection }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 13)
            }
            footer
        }
        .background(SidebarBackground())
        .onReceive(NotificationCenter.default.publisher(for: .rjSelectJournal)) { note in
            // 新建完日记本自动切过去
            if let id = note.object as? String { scope = .journal(id) }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Image(systemName: "book.closed.fill")
                        .font(.rj(13, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name).font(.rj(15, weight: .bold, design: .rounded))
                    Text("\(store.entries.count) 篇 · \(store.totalWords()) 字")
                        .font(.rj(11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // 召唤小迹。原来躲在窗口右上角的工具栏里，
                // 挪到左上角这一行 —— 顺手就能点到，也不用跟红黄绿抢地方。
                IconButton(symbol: "sparkles", help: "小迹 · AI 助手 (⌘J)", size: 28, iconSize: 13) {
                    NotificationCenter.default.post(name: .rjToggleAI, object: nil)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "flame.fill")
                    .font(.rj(11.5))
                    .foregroundStyle(store.streak > 0 ? Color.orange : Color.secondary)
                Text(store.streak > 0 ? "已连续记录 \(store.streak) 天" : "今天还没写")
                    .font(.rj(12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: RJ.rowRadius, style: .continuous)
                .fill(Color.primary.opacity(0.055)))

            // 每天一句，来自凯文·凯利《宝贵的人生建议》。
            // 放头部而不是内容区：内容区会滚，滚下去就看不见了，
            // 而「每天一眼」的东西必须在视线里。
            DailyAdviceCard()
        }
        .padding(.horizontal, 15)
        .padding(.top, 15)
        .padding(.bottom, 11)
    }

    // MARK: 浏览

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "浏览").padding(.horizontal, 9).padding(.bottom, 5)
            row(scope: .today, symbol: "calendar.badge.clock", title: "今天",
                count: store.entries(on: Date()).count)
            row(scope: .all, symbol: "books.vertical.fill", title: "全部日记",
                count: store.entries.count)
            row(scope: .onThisDay, symbol: "clock.arrow.circlepath", title: "那年今日",
                count: store.onThisDayEntries.count)
            row(scope: .calendar, symbol: "calendar", title: "日历", count: nil)
            row(scope: .stats, symbol: "chart.bar.fill", title: "统计", count: nil)
        }
    }

    // MARK: 日记本

    private var journalsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel(text: "日记本")
                Spacer()
                IconButton(symbol: "plus", help: "新建日记本", size: 22, iconSize: 11) {
                    store.beginNewJournal()
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            // 上下顺序就是数组顺序，直接存进 config.json。
            // 排序用的是「按行拖放」而不是 List 的 onMove ——
            // onMove 只在 List 里生效，而这里是 ScrollView 里的一堆自定义行，
            // 换成 List 会把现在这套悬停 / 选中 / 毛玻璃的行样式全部推翻。
            ForEach(store.journals) { j in
                journalRow(j)
                    // 先量出这一行有多高：判断「落在上半还是下半」要用它。
                    // 行高会随界面缩放变化，所以不能写成常量。
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .onAppear { measure(g.size.height) }
                                .onChange(of: g.size.height) { _, h in measure(h) }
                        }
                    )
                    // 插入位置提示线：拖到哪一行的上（下）半边就画在哪
                    .overlay(alignment: .top) { dropLine(for: j, below: false) }
                    .overlay(alignment: .bottom) { dropLine(for: j, below: true) }
                    .opacity(draggingJournalId == j.id ? 0.35 : 1)
                    .onDrag {
                        draggingJournalId = j.id
                        return NSItemProvider(object: j.id as NSString)
                    } preview: {
                        journalDragPreview(j)
                    }
                    .onDrop(of: [.text], delegate: JournalDropDelegate(
                        target: j,
                        store: store,
                        dragging: $draggingJournalId,
                        mark: $dropMark,
                        rowHeight: journalRowHeight))
                    .contextMenu {
                        Button("编辑日记本…") { store.beginEditJournal(j) }
                        Divider()
                        // 拖拽之外的第二条路：触控板不好拖、或者想精确挪一格的时候用
                        Button("上移") { shift(j, by: -1) }
                            .disabled(store.journals.first?.id == j.id)
                        Button("下移") { shift(j, by: 1) }
                            .disabled(store.journals.last?.id == j.id)
                        Divider()
                        Button("设为默认") {
                            store.settings.defaultJournalId = j.id
                            store.saveConfig()
                        }
                        Divider()
                        Button("删除日记本", role: .destructive) { store.deleteJournal(j) }
                    }
            }
        }
    }

    /// 在列表里把某个日记本往上 / 往下挪一格
    private func shift(_ j: Journal, by delta: Int) {
        guard let i = store.journals.firstIndex(where: { $0.id == j.id }) else { return }
        let dest = i + delta
        guard store.journals.indices.contains(dest) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            // 往下挪时 toIndex 要多加 1：它用的是「移动之前」的位置语义
            store.moveJournal(j.id, toIndex: delta > 0 ? i + 2 : dest)
        }
    }

    private func measure(_ h: CGFloat) {
        guard h > 1, abs(h - journalRowHeight) > 0.5 else { return }
        journalRowHeight = h
    }

    @ViewBuilder
    private func dropLine(for j: Journal, below: Bool) -> some View {
        if dropMark?.id == j.id && dropMark?.below == below {
            Capsule()
                .fill(Color.rjAccent)
                .frame(height: 2)
                .padding(.horizontal, 5)
                .offset(y: below ? 1 : -1)
        }
    }

    /// 拖动时跟着手指的那一小块
    private func journalDragPreview(_ j: Journal) -> some View {
        HStack(spacing: 7) {
            JournalIconBadge(symbol: j.symbol, color: Color(hex: j.colorHex), size: 17)
            Text(j.name).font(.rj(12.5, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor).opacity(0.8)))
        .softShadow()
    }

    private func journalRow(_ j: Journal) -> some View {
        let active = scope == .journal(j.id)
        let color = Color(hex: j.colorHex)
        return SidebarRow(active: active,
                          symbol: nil,
                          dotColor: color,
                          badgeSymbol: j.symbol,
                          title: j.name,
                          count: store.journalCount(j.id),
                          tint: color,
                          trailingPin: store.settings.defaultJournalId == j.id) {
            scope = .journal(j.id)
        }
    }

    // MARK: 标签

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "标签").padding(.horizontal, 9).padding(.bottom, 5)
            ForEach(store.allTags.prefix(14), id: \.0) { tag, count in
                SidebarRow(active: scope == .tag(tag),
                           symbol: "number",
                           title: tag,
                           count: count,
                           tint: .secondary) {
                    scope = .tag(tag)
                }
            }
        }
    }

    // MARK: 通用行

    private func row(scope target: Scope, symbol: String, title: String, count: Int?) -> some View {
        SidebarRow(active: scope == target,
                   symbol: symbol,
                   title: title,
                   count: count,
                   tint: .rjAccent) {
            scope = target
        }
    }

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 9) {
                Button {
                    NotificationCenter.default.post(name: .rjNewEntry, object: nil)
                } label: {
                    Label("写日记", systemImage: "square.and.pencil")
                        .font(.rj(13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(RJSubtleButtonStyle())
                .keyboardShortcut("n", modifiers: .command)

                // 九宫格日记：按住弹出模板列表，直接点就是第一张模板。
                // 用 Menu 而不是按钮，是因为模板是用户可增可改的 ——
                // 每次打开才知道有哪些。
                Menu {
                    ForEach(store.gridTemplates) { t in
                        Button {
                            NotificationCenter.default.post(name: .rjNewGridEntry, object: t.id)
                        } label: {
                            Label(t.name, systemImage: t.symbol)
                        }
                    }
                    Divider()
                    Button("新建九宫格日记…") { NotificationCenter.default.post(name: .rjNewGridEntry, object: nil) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.rj(14))
                        .frame(width: 32, height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("九宫格日记（⌘⇧N）")

                IconButton(symbol: "lock.fill", help: "锁定 (⌘L)", size: 32, iconSize: 14) {
                    store.lock()
                }
                IconButton(symbol: "gearshape.fill", help: "设置 (⌘,)", size: 32, iconSize: 14) {
                    NotificationCenter.default.post(name: .rjOpenSettings, object: nil)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
        .background(Color.rjBar)
    }
}

// MARK: - 日记本拖放排序

/// 拖动时记下的落点：落在哪一行的上方 / 下方
struct JournalDropMark: Equatable {
    var id: String
    /// true = 插到这一行的下面
    var below: Bool
}

/// 拖放排序的落点判断。
///
/// 用 `DropDelegate` 而不是 `.dropDestination`，是因为只有 delegate 的 `DropInfo`
/// 才给得出**指针在行内的坐标** —— 要判断「落在行的上半还是下半」必须靠它，
/// 否则只能一律插到目标前面，往下拖时会差一格。
///
/// 行高由 `onGeometryChange` 量出来传进来（跟着界面缩放会变），
/// 所以这里不能用写死的常量。
private struct JournalDropDelegate: DropDelegate {
    let target: Journal
    let store: Store
    @Binding var dragging: String?
    @Binding var mark: JournalDropMark?
    var rowHeight: CGFloat = 30

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        return dragging != target.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let dragging, dragging != target.id else {
            setMark(nil)
            return DropProposal(operation: .forbidden)
        }
        setMark(JournalDropMark(id: target.id, below: isBelow(info)))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        setMark(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let below = isBelow(info)
        // 落点判断读的是指针坐标，而 SwiftUI 保证拖放回调跑在主线程上，
        // 所以这里直接把它认领成 MainActor 再动 store。
        return MainActor.assumeIsolated {
            let dragId = dragging
            setMark(nil)
            dragging = nil
            guard let dragId, dragId != target.id else { return false }
            let idx = store.journals.firstIndex { $0.id == target.id } ?? 0
            store.moveJournal(dragId, toIndex: idx + (below ? 1 : 0))
            return true
        }
    }

    private func isBelow(_ info: DropInfo) -> Bool {
        JournalReorder.dropsBelow(cursorY: info.location.y, rowHeight: rowHeight)
    }

    private func setMark(_ m: JournalDropMark?) {
        if mark != m { mark = m }
    }
}

// MARK: - 侧边栏行

struct SidebarRow: View {
    var active: Bool
    var symbol: String? = nil
    var dotColor: Color? = nil
    /// 日记本行的图标。给了它就画成「彩色圆角方块 + 白色图标」，
    /// 不给就退回原来的小圆点。
    var badgeSymbol: String? = nil
    var title: String
    var count: Int? = nil
    var tint: Color = .rjAccent
    var trailingPin: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let dotColor {
                    if let badgeSymbol {
                        JournalIconBadge(symbol: badgeSymbol, color: dotColor, size: 18.5)
                            .frame(width: 20)
                    } else {
                        JournalDot(color: dotColor, size: 8.5)
                            .frame(width: 20)
                    }
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.rj(12.5, weight: .medium))
                        .foregroundStyle(active ? Color.white : tint.opacity(0.9))
                        .frame(width: 20)
                }

                Text(title)
                    .font(.rj(13, weight: active ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if trailingPin {
                    Image(systemName: "pin.fill")
                        .font(.rj(9))
                        .foregroundStyle(active ? Color.white.opacity(0.75) : Color.secondary)
                }
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.rj(11.5, weight: active ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(active ? Color.white.opacity(0.85) : Color.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: RJ.rowRadius, style: .continuous)
                    .fill(active ? AnyShapeStyle(fillGradient)
                          : AnyShapeStyle(hovering ? Color.primary.opacity(0.065) : Color.clear))
            )
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.18), value: active)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.98, pressedOpacity: 0.85))
        .onHover { hovering = $0 }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.82)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct SidebarBackground: View {
    var body: some View {
        Rectangle().fill(.ultraThinMaterial)
    }
}

extension Notification.Name {
    static let rjNewEntry = Notification.Name("rj.newEntry")
    static let rjOpenSettings = Notification.Name("rj.openSettings")
    static let rjToggleAI = Notification.Name("rj.toggleAI")
    static let rjFocusSearch = Notification.Name("rj.focusSearch")
    static let rjGoToday = Notification.Name("rj.goToday")
    static let rjScopeCalendar = Notification.Name("rj.scopeCalendar")
    static let rjScopeStats = Notification.Name("rj.scopeStats")
    /// 截图/预览用：切换编辑器显示模式，object 传 EditorMode
    static let rjEditorMode = Notification.Name("rj.editorMode")
    static let rjSettingsPage = Notification.Name("rj.settingsPage")
    /// 新建日记本成功后，object 传新日记本的 id，让侧边栏跳过去
    static let rjSelectJournal = Notification.Name("rj.selectJournal")
    /// 让 SwiftUI 自己把设置弹窗关掉。
    /// 截图流程要走这个，而不是直接调 NSWindow.endSheet —— 后者只把窗口收起来，
    /// SwiftUI 那边的 isPresented 还是 true，接着再弹别的 sheet 就会被丢掉。
    static let rjCloseSettings = Notification.Name("rj.closeSettings")
    /// 新建九宫格日记。object 可选传模板 id（nil = 用第一张模板）
    static let rjNewGridEntry = Notification.Name("rj.newGridEntry")
    /// 跳到日历页的某一天（热力图点击用），object 传 Date
    static let rjCalendarDay = Notification.Name("rj.calendarDay")
}
