import SwiftUI
import AppKit
import UniformTypeIdentifiers

// 编辑区只有两种看法：即时渲染 / 纯源码。
//
// 原来还有第三种「纯预览」—— 内容是同一份，只是把即时渲染再画一遍。
// 用户要求去掉：即时渲染本身就已经是所见即所得，多一个按钮只是让人多犹豫一次。
enum EditorMode: String, CaseIterable {
    case live = "即时"
    case source = "源码"

    var symbol: String {
        switch self {
        case .live: return "square.and.pencil"
        case .source: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - 主编辑区

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIService

    var entryId: String
    var onDeleted: () -> Void = {}
    var onOpenAI: () -> Void = {}

    @State private var mode: EditorMode = .live

    init(entryId: String,
         onDeleted: @escaping () -> Void = {},
         onOpenAI: @escaping () -> Void = {},
         initialMode: EditorMode = .live) {
        self.entryId = entryId
        self.onDeleted = onDeleted
        self.onOpenAI = onOpenAI
        _mode = State(initialValue: initialMode)
    }
    @State private var isDropTarget = false
    @State private var newTag = ""
    @State private var showTagField = false
    @State private var showTemplates = false
    @State private var promptTarget = "summarize"
    @State private var promptResult = ""
    @State private var promptBusy = false
    @State private var showPromptSheet = false

    private var entry: Entry? { store.entries.first { $0.id == entryId } }

    /// 每次写入都从仓库里重新取最新值，避免闭包捕获到旧快照
    private func mutate(_ apply: (inout Entry) -> Void, immediate: Bool = false) {
        guard var e = store.entries.first(where: { $0.id == entryId }) else { return }
        apply(&e)
        store.update(e, immediate: immediate)
    }

    var body: some View {
        if let entry {
            content(entry)
        } else {
            EmptyHint(symbol: "text.book.closed", title: "没有选中日记", subtitle: "从左侧选一篇，或新建一篇")
        }
    }

    // MARK: 主体

    private func content(_ entry: Entry) -> some View {
        VStack(spacing: 0) {
            // 编辑区在窗口右侧，红绿灯压不到 —— 顶栏直接从窗口顶部开始，
            // 不留标题栏让位（2026-09-25 用户要求「内容也往上提」）。
            topBar(entry)
            HairLine()
            // 这里原来还有一行「大标题」输入框和一行「标签」胶囊。
            // 用户要求去掉：标题本来就是正文第一行，标签改成在正文里直接写 # ——
            // 一页纸上只有一处能写字，就不会出现「标题写什么、正文第一行又写什么」的犹豫。
            toolbarRow(entry)
            HairLine()
            bodyArea(entry)
            HairLine()
            statusBar(entry)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .center) {
            if isDropTarget {
                ZStack {
                    Rectangle().fill(Color.rjAccent.opacity(0.07))
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus").font(.rj(32, weight: .light))
                        Text("松手即可插入图片").font(.rj(13.5, weight: .medium))
                    }
                    .foregroundStyle(Color.rjAccent)
                }
                .overlay(Rectangle().strokeBorder(Color.rjAccent, lineWidth: 2))
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: $isDropTarget) { providers in
            handleDrop(providers, entry: entry)
            return true
        }
        .sheet(isPresented: $showPromptSheet) { aiResultSheet(entry) }
        // 「插入模板」原来挂在标签行上，标签行去掉之后挪到这里 ——
        // 它本来就跟标签没关系，只是当年顺手挂那儿了
        .confirmationDialog("插入模板", isPresented: $showTemplates, titleVisibility: .visible) {
            ForEach(EntryTemplate.all) { t in
                Button(t.name) { insertTemplate(t, entry: entry) }
            }
            Button("取消", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .rjEditorMode)) { note in
            if let m = note.object as? EditorMode {
                withAnimation(.easeOut(duration: 0.18)) { mode = m }
            }
        }
    }

    // MARK: 顶栏

    private func topBar(_ entry: Entry) -> some View {
        // 顶栏的元信息（日期/时间/日记本/天气）加起来比编辑区最窄时还宽，
        // 硬撑会把「今天 22:41」这类文字挤成空药丸。所以按可用宽度逐级摘掉
        // 次要信息：先摘时间，再摘日记本名，最后只留天气，右侧操作按钮始终保留。
        // 用户要求「心情、天气、时间放在同一行」—— 原来心情挂在右边那组按钮里，
        // 和左边的天气隔了大半屏，看「今天什么天、当时什么心情」得左右横跳。
        // 现在它紧挨着天气，窄下来时也和天气一起被摘掉，不会剩个孤零零的表情在天上。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                dateLabel(entry)
                timeLabel(entry)
                journalChip(entry)
                moodMenu(entry)
                weatherChip(entry)
                Spacer(minLength: 8)
                topBarActions(entry)
            }
            HStack(spacing: 7) {
                dateLabel(entry)
                moodMenu(entry)
                weatherChip(entry)
                Spacer(minLength: 8)
                topBarActions(entry)
            }
            HStack(spacing: 7) {
                moodMenu(entry)
                weatherChip(entry)
                Spacer(minLength: 8)
                topBarActions(entry)
            }
            HStack(spacing: 7) {
                Spacer(minLength: 4)
                topBarActions(entry)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .background(Color.rjBar)
    }

    private func dateLabel(_ entry: Entry) -> some View {
        Text(Fmt.friendlyDay(entry.createdAt))
            .font(.rj(13.5, weight: .semibold))
    }

    private func timeLabel(_ entry: Entry) -> some View {
        Text(entry.timeText)
            .font(.rj(12.5, design: .rounded))
            .foregroundStyle(.tertiary)
    }

    /// 顶栏那枚日记本胶囊。点一下就能换本 ——
    /// 不用再绕到右边「更多」里翻「移动到其他日记本」。
    @ViewBuilder
    private func journalChip(_ entry: Entry) -> some View {
        if let j = store.journal(for: entry.journalId) {
            let color = Color(hex: j.colorHex)
            Menu {
                ForEach(store.journals) { other in
                    Button {
                        store.move(entry, to: other.id)
                    } label: {
                        Label(other.name, systemImage: other.symbol)
                    }
                    .disabled(other.id == j.id)
                }
                Divider()
                Button("编辑这个日记本…") { store.beginEditJournal(j) }
                Button("新建日记本…") { store.beginNewJournal() }
            } label: {
                HStack(spacing: 5) {
                    // 和侧边栏用同一个图标：一眼就能认出「现在写的是哪一本」
                    JournalIconBadge(symbol: j.symbol, color: color, size: 14)
                    Text(j.name).font(.rj(12.5)).foregroundStyle(color)
                    Image(systemName: "chevron.down")
                        .font(.rj(7.5, weight: .bold))
                        .foregroundStyle(color.opacity(0.65))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.14)))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("点一下换日记本")
        }
    }

    /// 顶栏右侧：心情 / 更多 / 召唤小迹
    ///
    /// 原来最左边还有一个「移动到其他日记本」的文件夹按钮 —— 它和左边那枚日记本胶囊
    /// 是同一件事（点胶囊就能换本），两个入口并排摆着只会让人犹豫，撤掉。
    /// 位置让给「召唤小迹」：这是这一栏里唯一的高频动作，值得占一个显眼的位子。
    @ViewBuilder
    private func topBarActions(_ entry: Entry) -> some View {
        moodMenu(entry)

        MenuIcon(symbol: "ellipsis", help: "更多", iconSize: 13) {
            Button("九宫格日记…") { store.beginGridJournal(entryId: entry.id) }
            Button("插入模板…") { showTemplates = true }
            Button("插入图片…") { pickImage(entry) }
            Button("粘贴剪贴板图片") { pasteImage(entry) }
            Divider()
            Button("导出为 PDF…") { Exporter.savePDF(entry: entry, store: store) }
            Button("导出为 Markdown…") { Exporter.saveMarkdown(entry: entry, store: store) }
            Button("复制为纯文本") { Exporter.copyPlainText(entry) }
            Divider()
            Button("删除这篇", role: .destructive) {
                store.delete(entry)
                onDeleted()
            }
        }

        aiOrb
    }

    /// 召唤小迹。
    ///
    /// 整个界面里的按钮基本是「浅底 + 图标」的克制风格，只有这一枚是实心渐变 ——
    /// 它得在一排灰色小图标里被一眼看到。悬停时轻微放大，按下去有回弹。
    private var aiOrb: some View {
        Button {
            onOpenAI()
        } label: {
            Image(systemName: "sparkles")
                .font(.rj(13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color.rjAccent,
                                                      Color.rjAccent.opacity(0.70)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.rjAccent.opacity(0.30), radius: 6, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.90))
        .help("召唤小迹 · AI 助手 (⌘J)")
    }

    private func moodMenu(_ entry: Entry) -> some View {
        Menu {
            Button("不显示") { setMood(entry, "") }
            Divider()
            ForEach(Moods.all, id: \.self) { m in
                Button(m) { setMood(entry, m) }
            }
        } label: {
            Group {
                if entry.mood.isEmpty {
                    Image(systemName: "face.smiling").font(.rj(13))
                } else {
                    Text(entry.mood).font(.rj(14))
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("记录心情")
    }

    // MARK: 天气

    private func weatherChip(_ entry: Entry) -> some View {
        let current = entry.weather
        return Menu {
            if Calendar.current.isDateInToday(entry.createdAt) {
                Button {
                    Task { await store.fillWeatherWithCurrent(entry) }
                } label: {
                    Label("获取当前天气（\(store.settings.weatherCity)）", systemImage: "arrow.clockwise")
                }
                Divider()
            }
            ForEach(WeatherKind.pickable, id: \.self) { k in
                Button {
                    store.setWeather(k, on: entry)
                } label: {
                    Label(k.name, systemImage: k.symbol)
                }
            }
            Divider()
            if current != nil {
                Button("不显示天气", role: .destructive) { store.setWeather(nil, on: entry) }
            } else {
                Button("城市在「设置 → 通用 → 天气」里改") {}.disabled(true)
            }
        } label: {
            HStack(spacing: 4) {
                if store.weatherBusy && current == nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: current?.icon ?? "mappin").font(.rj(12))
                }
                // 天气胶囊顺带把「写这篇时在哪」也带上：
                // 有城市有天气就是「北京 · 多云」，没有天气就只显示城市。
                Text(weatherChipText(current, entry)).font(.rj(12, weight: .medium))
            }
            .foregroundStyle(current.map { AnyShapeStyle($0.kind.tint) } ?? AnyShapeStyle(Color.secondary))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill((current?.kind.tint ?? Color.secondary).opacity(0.13)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(current.map { "天气：\($0.summary)（点一下可改）" } ?? "记录今天的天气和所在地")
    }

    private func weatherChipText(_ w: WeatherInfo?, _ entry: Entry) -> String {
        let city = entry.city.trimmed
        if let w {
            return city.isEmpty ? w.summary : "\(city) · \(w.summary)"
        }
        return city.isEmpty ? "天气" : city
    }

    // MARK: 工具条

    private func toolbarRow(_ entry: Entry) -> some View {
        // AI 面板打开后编辑区会变窄，最窄时只有 300 出头。
        //
        // 关键点：光折成两行还不够。「标记」那一组自己有 13 个 30pt 的按钮，
        // 加起来接近 450pt —— 折行后整行依然塞不进 300pt。此时 ViewThatFits
        // 挑不出能放下的分支，就会把这一行按原宽硬撑出去，把整个详情栏顶宽，
        // 最终表现为「左侧导航栏被挤到窗外」（侧边栏左边被裁掉一截）。
        //
        // 所以这里分了四级，越窄越拆得细，最后一级用横向滚动兜底，
        // 保证任何宽度下都不会撑破外层布局：
        //   1. 一行：标记 + 尾部
        //   2. 两行：标记 / 尾部
        //   3. 三行：行内样式 / 段落与插入 / 尾部
        //   4. 横滚：一行但可左右滑
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                toolbarMarks(entry)
                Spacer(minLength: 10)
                toolbarTail(entry)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    toolbarMarks(entry)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    toolbarTail(entry)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    toolbarInline(entry)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 3) {
                    toolbarBlocks(entry)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    toolbarTail(entry)
                }
            }
            // 兜底：真到极窄宽度（用户把窗口拖到最小）时改为横向滚动，
            // 宁可要用户滑一下，也不能让工具条把整个分栏撑坏。
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    toolbarMarks(entry)
                    Spacer(minLength: 12)
                    toolbarTail(entry)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
    }

    /// 工具条左半：行内样式 + 段落与插入（宽屏时合并成一条）
    @ViewBuilder
    private func toolbarMarks(_ entry: Entry) -> some View {
        toolbarInline(entry)
        divider
        toolbarBlocks(entry)
    }

    /// 行内样式：加粗 / 斜体 / 删除线 / 行内代码
    @ViewBuilder
    private func toolbarInline(_ entry: Entry) -> some View {
        IconButton(symbol: "bold", help: "加粗", iconSize: 12.5) { EditorRegistry.shared.apply(.bold) }
        IconButton(symbol: "italic", help: "斜体", iconSize: 12.5) { EditorRegistry.shared.apply(.italic) }
        IconButton(symbol: "strikethrough", help: "删除线", iconSize: 12.5) { EditorRegistry.shared.apply(.strike) }
        IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "行内代码", iconSize: 12.5) {
            EditorRegistry.shared.apply(.inlineCode)
        }
    }

    /// 段落与插入：标题级别 / 列表 / 引用 / 链接 / 图片 / 分割线
    @ViewBuilder
    private func toolbarBlocks(_ entry: Entry) -> some View {
        MenuIcon(symbol: "textformat.size", help: "标题级别", iconSize: 12.5) {
            Button("一级标题") { EditorRegistry.shared.apply(.heading(1)) }
            Button("二级标题") { EditorRegistry.shared.apply(.heading(2)) }
            Button("三级标题") { EditorRegistry.shared.apply(.heading(3)) }
            Divider()
            Button("正文") { EditorRegistry.shared.apply(.body) }
        }
        IconButton(symbol: "list.bullet", help: "无序列表", iconSize: 12.5) { EditorRegistry.shared.apply(.bullet) }
        IconButton(symbol: "list.number", help: "有序列表", iconSize: 12.5) { EditorRegistry.shared.apply(.numbered) }
        IconButton(symbol: "checklist", help: "待办", iconSize: 12.5) { EditorRegistry.shared.apply(.task) }
        IconButton(symbol: "text.quote", help: "引用", iconSize: 12.5) { EditorRegistry.shared.apply(.quote) }
        IconButton(symbol: "link", help: "链接", iconSize: 12.5) { EditorRegistry.shared.apply(.link) }
        IconButton(symbol: "photo", help: "插入图片", iconSize: 12.5) { pickImage(entry) }
        IconButton(symbol: "minus", help: "分割线", iconSize: 12.5) { EditorRegistry.shared.apply(.divider) }
    }

    /// 工具条右半：小迹快捷 + 显示模式
    @ViewBuilder
    private func toolbarTail(_ entry: Entry) -> some View {
        MenuPill(symbol: "sparkles", title: "小迹", help: "AI 快捷操作 (⌘J)") {
            Button { runPrompt("summarize", entry: entry) } label: { Label("总结这一篇", systemImage: "text.redaction") }
            Button { runPrompt("titles", entry: entry) } label: { Label("建议标题", systemImage: "textformat") }
            Button { runPrompt("tags", entry: entry) } label: { Label("建议标签", systemImage: "number") }
            Divider()
            Button { onOpenAI() } label: { Label("和 AI 聊聊", systemImage: "bubble.left.and.bubble.right") }
        }
        IconSegmented(options: [
            SegmentOption(value: .live, symbol: EditorMode.live.symbol, label: "即时渲染"),
            SegmentOption(value: .source, symbol: EditorMode.source.symbol, label: "看源码")
        ], selection: $mode, cellWidth: 34)
    }

    private var divider: some View {
        Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.6))
            .frame(width: 1, height: 17)
            .padding(.horizontal, 4)
    }

    // MARK: 正文

    private func bodyArea(_ entry: Entry) -> some View {
        let silentBinding = Binding(
            get: { store.entries.first { $0.id == entryId }?.body ?? "" },
            set: { v in mutate { $0.body = v } }
        )
        let style = store.settings.mdStyle
        // 版心：0 = 撑满。要收窄时先给内容一个上限宽度，再用一层 maxWidth: .infinity
        // 把它居中 —— 不用 GeometryReader 就能做到，窗口拉伸时也不会抖。
        let contentCap: CGFloat = style.contentWidth > 0
            ? CGFloat(style.contentWidth) * UIScale.factor
            : 100_000

        // 单栏：即时渲染时输入语法当场变排版，不再分左右两半。
        //
        // 这里原来还有一个「纯预览」分支（把同一份内容用 MarkdownPreview 再画一遍）。
        // 去掉了：即时渲染本身就是所见即所得，留着只是多一个按钮。
        return RichTextEditor(text: silentBinding,
                              fontSize: store.settings.editorFontSize,
                              style: style,
                              live: mode == .live,
                              onActivity: { store.touch() })
            .frame(maxWidth: contentCap)
            .frame(maxWidth: .infinity)
            // 左右 18 会被编辑器自己吃掉 6（textContainerInset 2 + lineFragmentPadding 4），
            // 正好和上下的 24 对齐 —— 见下面「统一左边缘」那段注释
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PaperBackground(style: PaperStyle.from(store.settings.paperStyle)))
    }

    // MARK: 状态栏

    private func statusBar(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            if store.settings.showWordCount {
                Label("\(entry.wordCount) 字", systemImage: "character")
                    .font(.rj(11.5, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            if !entry.imageNames.isEmpty {
                Label("\(entry.imageNames.count) 张图", systemImage: "photo")
                    .font(.rj(11.5, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            // 写到这里就说明已经落盘了（每敲一下都会存），
            // 所以直接说「自动保存」而不是「保存于」，省得以为要手动点一下
            Text("自动保存 · \(Fmt.relative(entry.updatedAt))")
                .font(.rj(11.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Color.rjBar)
    }

    // MARK: 行为

    private func setMood(_ entry: Entry, _ mood: String) {
        mutate({ $0.mood = mood }, immediate: true)
    }

    private func addTag(_ entry: Entry) {
        let t = newTag.trimmed.replacingOccurrences(of: "#", with: "")
        guard !t.isEmpty else { showTagField = false; return }
        mutate({ if !$0.tags.contains(t) { $0.tags.append(t) } }, immediate: true)
        newTag = ""
        showTagField = false
    }

    private func insertTemplate(_ t: EntryTemplate, entry: Entry) {
        let text = t.body + "\n"
        if entry.body.trimmed.isEmpty {
            mutate({ $0.body = text }, immediate: true)
        } else {
            EditorRegistry.shared.apply(.insert("\n\n" + text))
        }
    }

    private func pickImage(_ entry: Entry) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "插入"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let name = store.importImage(from: url) else { continue }
            let path = store.attachmentMarkdownPath(name, entry: entry)
            EditorRegistry.shared.apply(.insert("\n![](\(path))\n"))
        }
    }

    private func pasteImage(_ entry: Entry) {
        let pb = NSPasteboard.general
        guard let image = NSImage(pasteboard: pb),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            store.show("剪贴板里没有图片")
            return
        }
        guard let name = store.importImage(data: png, ext: "png") else { return }
        let path = store.attachmentMarkdownPath(name, entry: entry)
        EditorRegistry.shared.apply(.insert("\n![](\(path))\n"))
    }

    private func handleDrop(_ providers: [NSItemProvider], entry: Entry) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        guard let name = store.importImage(from: url) else { return }
                        let path = store.attachmentMarkdownPath(name, entry: entry)
                        EditorRegistry.shared.apply(.insert("\n![](\(path))\n"))
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        guard let name = store.importImage(data: data, ext: "png") else { return }
                        let path = store.attachmentMarkdownPath(name, entry: entry)
                        EditorRegistry.shared.apply(.insert("\n![](\(path))\n"))
                    }
                }
            }
        }
    }

    // MARK: AI 结果弹窗

    private func runPrompt(_ kind: String, entry: Entry) {
        promptTarget = kind
        promptResult = ""
        promptBusy = true
        showPromptSheet = true

        let key = AIKeyStore.read() ?? ""
        var messages: [ChatMessage] = [ChatMessage(role: "system", content: AIPrompts.systemBase)]
        switch kind {
        case "summarize":
            messages.append(ChatMessage(role: "user",
                content: AIPrompts.summarizeSingle(entry, journal: store.journal(for: entry.journalId)?.name ?? "日记")))
        case "titles":
            messages.append(ChatMessage(role: "user", content: AIPrompts.suggestTitles + "\n\n" + entry.plainText))
        default:
            messages.append(ChatMessage(role: "user", content: AIPrompts.suggestTags + "\n\n" + entry.plainText))
        }

        // 也走流式：原来用 `complete` 一次性拿结果，弹窗里全程只有一个转圈，
        // 长一点的总结要干等十几秒。边生成边出字，等待感小很多。
        ai.stream(baseURL: store.settings.aiBaseURL,
                  apiKey: key,
                  model: store.settings.aiModel,
                  temperature: 0.7,
                  messages: messages) { delta in
            promptResult += delta
        } onFinish: {
            promptBusy = false
        }
    }

    private func aiResultSheet(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                    Image(systemName: "sparkles").font(.rj(11, weight: .bold)).foregroundStyle(.white)
                }
                Text(titleForPrompt())
                    .font(.rj(15, weight: .bold))
                Spacer()
                if promptBusy { ProgressView().controlSize(.small) }
                IconButton(symbol: "xmark", help: "关闭", size: 26, iconSize: 12) { showPromptSheet = false }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.rjBar)
            HairLine()

            ScrollView {
                if !promptResult.isEmpty {
                    // 流式：第一个字到了就切到渲染视图，后面的继续往里长
                    MarkdownPreview(text: promptResult, store: store, entry: entry, fontSize: 15,
                                    style: store.settings.mdStyle, soft: true)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if promptBusy {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("小迹正在读你的日记…").font(.rj(13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
                } else {
                    // 流式的错误落在 AIService.lastError 上（不再抛回来），
                    // 这里必须接住 —— 否则失败时弹窗是一片空白，看着像卡死了
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.rj(20, weight: .light))
                            .foregroundStyle(.orange)
                        Text(ai.lastError ?? "没有收到内容，稍后再试一次")
                            .font(.rj(12.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .frame(minHeight: 280, maxHeight: 440)

            HairLine()
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(promptResult, forType: .string)
                    store.show("已复制")
                } label: {
                    Label("复制", systemImage: "doc.on.doc").font(.rj(13, weight: .medium))
                }
                .buttonStyle(RJPlainButtonStyle())
                // 流式期间结果还在长，这会儿复制/存入拿到的是半截内容
                .disabled(promptResult.isEmpty || promptBusy)

                if promptTarget == "summarize" {
                    Button {
                        let title = "AI 总结 · " + Fmt.day.string(from: entry.createdAt)
                        let created = store.createEntry(journalId: entry.journalId,
                                                        date: entry.createdAt,
                                                        body: promptResult)
                        if var e = store.entries.first(where: { $0.id == created.id }) {
                            e.title = title
                            e.tags = ["AI总结"]
                            store.update(e, immediate: true)
                        }
                        showPromptSheet = false
                        store.show("已存为新日记")
                    } label: {
                        Label("存为一篇新日记", systemImage: "square.and.pencil")
                            .font(.rj(13, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())
                    .disabled(promptResult.isEmpty || promptBusy)
                }

                if promptTarget == "titles" {
                    Button {
                        if let first = promptResult.split(separator: "\n")
                            .map({ $0.trimmed })
                            .first(where: { !$0.isEmpty }) {
                            let cleaned = first.replacingOccurrences(of: "^[\\d\\.\\-\\*\\s]+", with: "", options: .regularExpression)
                            mutate({ $0.title = cleaned }, immediate: true)
                            showPromptSheet = false
                        }
                    } label: {
                        Label("用第一个当标题", systemImage: "checkmark")
                            .font(.rj(13, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())
                    .disabled(promptResult.isEmpty || promptBusy)
                }

                if promptTarget == "tags" {
                    Button {
                        let tags = promptResult
                            .replacingOccurrences(of: "\n", with: "、")
                            .components(separatedBy: CharacterSet(charactersIn: "、,，"))
                            .map { $0.trimmed.replacingOccurrences(of: "#", with: "") }
                            .filter { !$0.isEmpty && $0.count <= 6 }
                        mutate({ $0.tags = Array(Set($0.tags + tags)).sorted() }, immediate: true)
                        showPromptSheet = false
                    } label: {
                        Label("填入标签", systemImage: "number")
                            .font(.rj(13, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
    }

    private func titleForPrompt() -> String {
        switch promptTarget {
        case "summarize": return "这篇日记的总结"
        case "titles": return "标题建议"
        default: return "标签建议"
        }
    }
}

// MARK: - 标签胶囊（悬停出现删除）

struct TagChip: View {
    var text: String
    var onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.rj(12, weight: .medium))
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.rj(8.5, weight: .bold))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.85))
                .transition(.opacity)
            }
        }
        .foregroundStyle(Color.rjAccent)
        .padding(.horizontal, 9).padding(.vertical, 3.5)
        .background(Capsule().fill(Color.rjAccent.opacity(hovering ? 0.18 : 0.12)))
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }
}
