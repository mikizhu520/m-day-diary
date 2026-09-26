import SwiftUI
import AppKit

// MARK: - 应用入口

@main
struct RiJiMain {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            MainActor.assumeIsolated { SelfTest.run() }
            return
        }
        // 诊断用：RiJi --weather 北京
        if let idx = CommandLine.arguments.firstIndex(of: "--weather") {
            let city = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "北京"
            SelfTest.probeWeather(city: city)
            return
        }
        // 一次性迁移：把早期版本存在系统钥匙串里的秘密搬进本机保险库。
        // 这一步系统可能弹一次授权框，所以只在用户显式执行时才跑。
        if CommandLine.arguments.contains("--recover-key") {
            MainActor.assumeIsolated { SelfTest.recoverLegacyKeys() }
            return
        }
        // 开发用：RiJi --render /tmp/rj-ui —— 把界面渲染成 PNG
        if let idx = CommandLine.arguments.firstIndex(of: "--render") {
            let dir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/rj-ui"
            MainActor.assumeIsolated { UIRender.run(to: dir) }
            return
        }
        RiJiApp.main()
    }
}

struct RiJiApp: App {
    @StateObject private var store = Store()
    @StateObject private var ai = AIService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(ai)
                .tint(Color.rjAccent)
                // AI 面板打开时要容得下：侧边栏 226 + 中栏 286 + 编辑区 300 + 面板 300
                .frame(minWidth: 1120, minHeight: 660)
        }
        // 去掉标题栏那条空带。
        //
        // 必须用官方 API，不能自己改 `styleMask` 插 `.fullSizeContentView`：
        // 手动改完 SwiftUI 不会重算安全区，三栏会一起顶到窗口最上沿。
        // `.hiddenTitleBar` 是系统自己做的同一件事，安全区交给系统管。
        // 各栏内容的让位用 TitlebarSpacer（Theme.swift）。
        //
        // ⚠️ 曾经以为 `.hiddenTitleBar` / `.searchable` 是「界面顶部乱了」的元凶，
        // 真凶是 DailyAdviceCard 里删掉 lineLimit 的 Text（见 DailyAdvice.swift 的长注释）。
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建日记") { post(.rjNewEntry) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("新建九宫格日记…") { post(.rjNewGridEntry) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appSettings) {
                Divider()
                Button("锁定 \(AppInfo.name)") { store.lock() }
                    .keyboardShortcut("l", modifiers: .command)
            }
            CommandMenu("日记") {
                Button("回到今天") { post(.rjGoToday) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("搜索") { post(.rjFocusSearch) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("AI 助手") { post(.rjToggleAI) }
                    .keyboardShortcut("j", modifiers: .command)
                Divider()
                Button("设置…") { post(.rjOpenSettings) }
                    .keyboardShortcut(",", modifiers: .command)
                Button("备份为 JSON…") { Exporter.backupJSON(store: store) }
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var monitor: Any?

    var body: some View {
        Group {
            if !store.hasLoaded {
                splash
            } else if store.isLocked {
                LockView()
                    .transition(.opacity)
            } else if !store.settings.isConfigured {
                OnboardingView(onFinish: { store.settings.isConfigured = true; store.saveConfig() })
            } else {
                MainView()
            }
        }
        .preferredColorScheme(colorScheme)
        .animation(.easeOut(duration: 0.22), value: store.isLocked)
        .onAppear {
            if SnapshotRunner.enabled {
                store.enterSnapshotDemo()
            } else {
                store.bootstrap()
            }
            installMonitor()
        }
        .task {
            if SnapshotRunner.enabled { await SnapshotRunner.run(store: store) }
        }
        // 检查更新：启动后等 5 秒再查 —— 先把界面、日记、天气这些正事办完，
        // 别跟启动抢资源。节流（同一天最多一次）和「查不到就闭嘴」都在 Store 里。
        .task {
            guard !SnapshotRunner.enabled else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await store.checkForUpdates(manual: false)
        }
        .onDisappear { removeMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rjToast)) { note in
            if let msg = note.object as? String { store.show(msg) }
        }
        // 新建 / 编辑日记本。挂在根视图上而不是 MainView：
        // MainView 已经有「设置」那个 sheet 了，同一个视图上叠两个 sheet，
        // 在一张还没关干净的时候请求另一张会被系统直接丢掉。
        .sheet(item: $store.journalDraft) { draft in
            JournalEditor(draft: draft).environmentObject(store)
        }
        // 日记本单独上锁的解锁面板。和上面那个编辑窗同一级，
        // 都是「整个窗口的一次请求」，所以挂在根视图上而不是任何一栏里。
        .sheet(item: $store.journalGate) { gate in
            JournalUnlockView(
                journalId: gate.id,
                onUnlocked: { id in
                    store.cancelJournalGate()
                    // 解开之后顺手切过去 —— 用户点它本来就是为了看里面的内容
                    NotificationCenter.default.post(name: .rjSelectJournal, object: id)
                },
                onCancel: { store.cancelJournalGate() }
            )
            .environmentObject(store)
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var splash: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.65)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Image(systemName: "book.closed.fill")
                        .font(.rj(22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .softShadow()
                ProgressView().controlSize(.small)
            }
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { event in
            store.touch()
            return event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - 主界面

struct MainView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIService
    @AppStorage("rj.uiScale") private var uiScale: Double = 1.30
    /// AI 面板宽度。拖过之后记住，下次打开还是这个宽度。
    @AppStorage(PanelResizer.widthKey) private var aiPanelWidth: Double = PanelResizer.defaultWidth

    @State private var scope: Scope? = .today
    @State private var selectedId: String?
    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var showAI = false
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didInitialSelect = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(scope: $scope)
                // 窗口用了 `.hiddenTitleBar`（见 RiJiApp），内容会铺满整窗，
                // 三栏各自在内容顶部让出标题栏那一条 —— 不让的话侧边栏标题会被红黄绿压住、
                // 中栏和编辑区的第一行会被窗口上边缘切掉（「界面顶部乱了」）。
                // 侧边栏的让位在 SidebarView 自己内部，那儿才有正确的背景。
                .navigationSplitViewColumnWidth(min: 226, ideal: 252, max: 320)
        } content: {
            // 中栏不 Escape 让标题栏：红绿灯只在侧边栏那栏的左上角，
            // 中栏内容直接从窗口顶部开始，顶部不留一条空白（用户要求「往上提」）。
            middleColumn
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationSplitViewColumnWidth(min: 286, ideal: 350, max: 460)
        } detail: {
            HStack(spacing: 0) {
                detailColumn
                    // 工具栏上原来挤着「AI 助手 / 保存 / 设置」三个按钮。
                    // 现在：保存是自动的（每敲一下都会落盘），没必要留个按钮让人操心；
                    // 设置侧边栏底部本来就有齿轮；AI 助手挪到左上角侧边栏顶部了。
                    // 所以这里不再挂 toolbar —— 顶栏整条留给内容。

                // AI 面板自己停靠在右边，不用系统的 .inspector。
                // 原因：inspector 会参与 NavigationSplitView 的列宽协商，
                // 一旦打开就要求额外的宽度，宽不够时系统会把侧边栏整栏折叠 —— 表现为「左侧导航被挤跑了」。
                // 放在详情栏内部就没有这个问题：它只压缩编辑区，侧边栏和中栏纹丝不动。
                if showAI {
                    // 拖拽条自己就是那条分隔线，不用再单放一个 Divider
                    PanelResizer(width: $aiPanelWidth, minWidth: PanelResizer.minWidth,
                                 maxWidth: PanelResizer.maxWidth)
                    AIPanel(currentEntryId: selectedId, isPresented: $showAI)
                        .frame(width: CGFloat(aiPanelWidth))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // 顶部让位在编辑区 / AI 面板 / 统计页各自内部做（它们底色各不相同）
        }
        // 界面字号改变时整块重建，保证所有文字立刻跟着变
        .id(uiScale)
        .searchable(text: $searchText, isPresented: $searchPresented,
                    placement: .sidebar, prompt: "搜索日记、标签、内容")
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store).environmentObject(ai)
        }
        // 九宫格面板。挂在窗口这一层（和日记本编辑窗同一级），
        // 保证无论在编辑区还是日历/统计页，⌘⇧N 都能弹出来。
        .sheet(item: $store.gridDraft) { d in
            GridJournalSheet(draft: d, onDone: { id in jumpTo(entryId: id) })
                .environmentObject(store)
        }
        .alert("开启\(store.biometryName)解锁？", isPresented: $store.showBiometricOffer) {
            Button("开启") { store.confirmBiometricOffer() }
            Button("以后再说", role: .cancel) { store.dismissBiometricOffer() }
        } message: {
            Text("开启后，锁屏时按一下\(store.biometryName)就能进，不用再输密码。密码会加密保存在本机，只在你这台 Mac 上有效。")
        }
        .overlay(alignment: .top) { toastView }
        .onReceive(NotificationCenter.default.publisher(for: .rjNewEntry)) { _ in newEntry() }
        .onReceive(NotificationCenter.default.publisher(for: .rjNewGridEntry)) { note in
            store.beginGridJournal(templateId: note.object as? String)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rjGoToday)) { _ in goToday() }
        .onReceive(NotificationCenter.default.publisher(for: .rjToggleAI)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { showAI.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rjOpenSettings)) { _ in showSettings = true }
        .onReceive(NotificationCenter.default.publisher(for: .rjCloseSettings)) { _ in showSettings = false }
        .onReceive(NotificationCenter.default.publisher(for: .rjFocusSearch)) { _ in
            searchPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .rjScopeCalendar)) { _ in scope = .calendar }
        .onReceive(NotificationCenter.default.publisher(for: .rjScopeStats)) { _ in scope = .stats }
        .onChange(of: store.unlockedJournals) { _, _ in
            // 正在看的那一本被重新锁上（右键「立即重新上锁」）→ 退回「今天」，
            // 别把一个空列表留在屏幕上让人以为是丢数据了。
            if case .journal(let id) = scope ?? .today, store.isJournalLocked(id) {
                scope = .today
                selectedId = nil
            }
        }
        .onAppear { initialSelect() }
        // 解锁后（以及刚打开时）把新写的日记沉淀进记忆，让小迹越用越懂你。
        // 没填 API Key、没开自动更新、或者没有新日记时，这一步什么也不做。
        .task { await store.refreshMemory(using: ai) }
    }

    // MARK: 提示条

    @ViewBuilder
    private var toastView: some View {
        if let toast = store.toast {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.rj(13))
                    .foregroundStyle(Color.rjAccent)
                Text(toast).font(.rj(13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            )
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: 中栏

    @ViewBuilder
    private var middleColumn: some View {
        if !searchText.trimmed.isEmpty {
            SearchResultsView(query: searchText.trimmed, selectedId: $selectedId)
        } else {
            switch scope ?? .today {
            case .calendar:
                CalendarPane(selectedId: $selectedId)
            case .stats:
                statsPane
            default:
                EntryListView(
                    title: listTitle,
                    subtitle: listSubtitle,
                    entries: listEntries,
                    selectedId: $selectedId,
                    emptySymbol: emptySymbol,
                    emptyTitle: emptyTitle,
                    emptySubtitle: emptySubtitle,
                    onCreate: { newEntry() },
                    showDayHeader: (scope ?? .today) != .today
                )
            }
        }
    }

    /// 统计页的中栏：只放右边仪表盘里没有的数字，避免左右两张表报同一批数
    private var statsPane: some View {
        let cal = Calendar.current
        let now = Date()
        let today = store.entries(on: now)
        let thisWeek = store.visible.filter {
            cal.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear)
        }
        let thisMonth = store.visible.filter {
            cal.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }
        let weekWords = thisWeek.reduce(0) { $0 + $1.wordCount }
        let dayKeys = store.dayKeys
        let activeDays = max(dayKeys.count, 1)
        let lastAt = store.visible.map(\.createdAt).max()
        let openTodos = store.visible.reduce(0) { acc, e in
            acc + e.body.split(separator: "\n").filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]")
            }.count
        }

        return VStack(spacing: 0) {
            ColumnHeader(title: "速览", subtitle: "最近在写什么")
            HairLine()
            ScrollView {
                VStack(spacing: 8) {
                    miniStat("今天", "\(today.count) 篇")
                    miniStat("本周", "\(thisWeek.count) 篇")
                    miniStat("本月", "\(thisMonth.count) 篇")
                    miniStat("本周字数", "\(weekWords) 字")
                    miniStat("平均每个记录日", "\(store.totalWords() / activeDays) 字")
                    miniStat("待办未完成", "\(openTodos) 项")
                    if let lastAt {
                        miniStat("最近一次", Fmt.relative(lastAt))
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.rj(13)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.rj(13, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card()
    }

    // MARK: 详情栏

    @ViewBuilder
    private var detailColumn: some View {
        // 注意：AI 面板不在这里。它由上层 detail 栏的 HStack 停靠在右侧，
        // 这样打开时只会压缩编辑区，不会挤到侧边栏（见 App.swift 里 detail: 那段注释）。
        if scope == .stats {
            StatsView()
        } else if let selectedId, store.visible.contains(where: { $0.id == selectedId }) {
            EditorView(entryId: selectedId,
                       onDeleted: { self.selectedId = nil },
                       onOpenAI: { withAnimation(.easeOut(duration: 0.2)) { showAI = true } })
                .id(selectedId)
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.rjAccent.opacity(0.16), Color.rjAccent.opacity(0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: "square.and.pencil")
                    .font(.rj(32, weight: .light))
                    .foregroundStyle(Color.rjAccent)
            }
            VStack(spacing: 7) {
                Text("写下今天吧").font(.rj(19, weight: .semibold, design: .rounded))
                Text(Prompts.today())
                    .font(.rj(13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 18)

            HStack(spacing: 10) {
                Button { newEntry() } label: {
                    Label("新建日记", systemImage: "plus")
                        .font(.rj(13.5, weight: .semibold))
                }
                .buttonStyle(RJPrimaryButtonStyle())
                .keyboardShortcut("n", modifiers: .command)

                Button { withAnimation { showAI = true } } label: {
                    Label("问问小迹", systemImage: "sparkles")
                        .font(.rj(13.5, weight: .semibold))
                }
                .buttonStyle(RJSubtleButtonStyle())
            }
            .padding(.top, 20)

            Spacer()

            HStack(spacing: 18) {
                shortcutHint("square.and.pencil", "⌘N", "新建")
                shortcutHint("magnifyingglass", "⌘F", "搜索")
                shortcutHint("sparkles", "⌘J", "小迹")
                shortcutHint("lock.fill", "⌘L", "锁定")
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shortcutHint(_ symbol: String, _ key: String, _ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.rj(11.5))
            Text(key).font(.rj(12, weight: .semibold, design: .rounded))
            Text(name).font(.rj(12))
        }
        .foregroundStyle(.quaternary)
    }

    // MARK: 列表数据

    private var listTitle: String {
        switch scope ?? .today {
        case .today: return "今天"
        case .all: return "全部日记"
        case .onThisDay: return "那年今日"
        case .journal(let id): return store.journal(for: id)?.name ?? "日记本"
        case .tag(let t): return "#\(t)"
        default: return "日记"
        }
    }

    private var listSubtitle: String {
        switch scope ?? .today {
        case .today:
            // 光一个「2026年9月25日 星期五」信息量太少，把农历和假期一起带上
            let now = Date()
            var s = Fmt.full.string(from: now) + " · " + Almanac.day(now).lunarText
            if let m = Holiday.mark(now) { s += " · " + m.label }
            return s
        case .all:
            // 有锁着的本子时把这件事说明白，不然「怎么少了几篇」会让人心里没底
            let head = "共 \(store.visible.count) 篇 · \(store.totalWords()) 字"
            return store.hasClosedJournals ? head + " · 有日记本未解锁" : head
        case .onThisDay: return "往年同一天写下的"
        case .tag(let t): return "共 \(store.visible.filter { $0.allTags.contains(t) }.count) 篇"
        default: return "共 \(listEntries.count) 篇"
        }
    }

    private var listEntries: [Entry] {
        switch scope ?? .today {
        case .today:
            return store.entries(on: Date())
        case .all:
            return store.visible
        case .onThisDay:
            return store.onThisDayEntries
        case .journal(let id):
            return store.visible.filter { $0.journalId == id }
        case .tag(let t):
            return store.visible.filter { $0.allTags.contains(t) }
        default:
            return store.visible
        }
    }

    private var emptySymbol: String {
        if case .onThisDay = scope ?? .today { return "clock.arrow.circlepath" }
        return "square.and.pencil"
    }

    private var emptyTitle: String {
        if case .onThisDay = scope ?? .today { return "往事空空" }
        return "这一天还没有日记"
    }

    private var emptySubtitle: String {
        if case .onThisDay = scope ?? .today { return "明年今天，这里会出现今天的记录" }
        return "点击「写一篇」开始记录"
    }

    // MARK: 动作

    private func initialSelect() {
        guard !didInitialSelect else { return }
        didInitialSelect = true
        if let latest = store.entries(on: Date()).last {
            selectedId = latest.id
        }
    }

    private func goToday() {
        scope = .today
        searchText = ""
        if let latest = store.entries(on: Date()).last {
            selectedId = latest.id
        } else {
            newEntry()
        }
    }

    private func newEntry() {
        var journalId: String? = nil
        // 正停在某一本上就写进那一本；但它要是锁着的（刚被重新锁上之类）
        // 就退回默认本子，别把新日记塞进一个当场看不见的地方。
        if case .journal(let id) = scope ?? .today, !store.isJournalLocked(id) { journalId = id }
        let entry = store.createEntry(journalId: journalId)
        selectedId = entry.id
        if case .journal = scope ?? .today {} else if case .today = scope ?? .today {} else {
            scope = .today
        }
        store.show("新日记已创建")
    }

    /// 九宫格填完 / 追加完成后跳到那篇日记。
    /// 只看 selectedId 是不够的 —— 如果当时停在日历页或统计页，中栏根本不显示列表。
    private func jumpTo(entryId: String) {
        selectedId = entryId
        switch scope ?? .today {
        case .calendar, .stats:
            scope = .today
        default:
            break
        }
    }
}

// MARK: - 面板拖拽条

/// 详情栏里那条可以左右拖的竖线，用来调 AI 面板的宽度。
///
/// 线只画 1pt，但热区有 10pt —— 否则细得根本抓不住。
/// 热区放在 `overlay` 里，不参与布局，所以不会把相邻的编辑区挤歪。
struct PanelResizer: View {
    @Binding var width: Double
    var minWidth: Double
    var maxWidth: Double

    /// 宽度存这儿，重启后还是你拖到的那个宽度
    static let widthKey = "rj.aiPanelWidth"
    static let defaultWidth: Double = 380
    static let minWidth: Double = 280
    /// 上限不能给太大：侧栏 226 + 中栏 286 + 编辑区 + 面板 = 窗口宽度，
    /// 面板拉过头就会把编辑区压没，进而把侧栏顶出可视区（这个坑早期踩过一次）。
    static let maxWidth: Double = 520

    @State private var dragStart: Double?
    @State private var hovering = false

    private var active: Bool { hovering || dragStart != nil }

    var body: some View {
        Rectangle()
            .fill(active ? Color.rjAccent.opacity(0.5) : Color.primary.opacity(0.09))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        // 鼠标变左右箭头，让人一眼知道这儿能拖
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let base = dragStart ?? width
                                if dragStart == nil { dragStart = width }
                                // 往左拖 = 面板变宽
                                width = min(maxWidth, max(minWidth, base - value.translation.width))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
            .onTapGesture(count: 2) { width = Self.defaultWidth }
            .help("拖动调整宽度，双击恢复默认")
            .animation(.easeOut(duration: 0.12), value: active)
    }
}

// MARK: - 中栏统一表头

struct ColumnHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rj(16, weight: .bold))
                Text(subtitle).font(.rj(12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.top, 15)
        .padding(.bottom, 11)
        .background(Color.rjBar)
    }
}

extension ColumnHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
