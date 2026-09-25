import SwiftUI
import AppKit

// MARK: - AI 面板

struct AIPanel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIService

    var currentEntryId: String?
    @Binding var isPresented: Bool

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var scope: String = "current"
    /// 人格。跟设置双向绑定是为了换完人格下次打开还在 —— 用 AppStorage 之外的
    /// 写法是因为设置本身要落盘到配置文件里，不能分两处存。
    @State private var personaId: String = "companion"
    /// 「正在写总结…」的进度条状态。本来还有个 busy，一直没人用，删掉了。
    @State private var summaryBusy = false
    @State private var confirmClear = false
    @FocusState private var inputFocused: Bool

    private var currentEntry: Entry? {
        guard let currentEntryId else { return nil }
        return store.entries.first { $0.id == currentEntryId }
    }

    private var persona: AIPersona { AIPersonas.find(personaId) }

    var body: some View {
        VStack(spacing: 0) {
            // 面板在窗口右侧，红绿灯压不到 —— header 直接从窗口顶部开始
            header
            HairLine()
            quickActions
            HairLine()
            messageList
            HairLine()
            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            scope = store.settings.aiContextScope
            personaId = store.settings.aiPersona
        }
        // 人格写回设置，下次打开还是这个人
        .onChange(of: personaId) { _, new in
            store.settings.aiPersona = new
            store.saveConfig()
        }
        .confirmationDialog("清空和小迹的这段对话？",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                ai.cancel()
                messages.removeAll()
                summaryBusy = false
                inputFocused = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清掉界面上的这段对话，日记本身不受影响。")
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkles").font(.rj(12, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("小迹").font(.rj(14, weight: .bold))
                // 副标题写人格而不是模型名：人格是「谁在说话」，每天都会换；
                // 模型是哪一版跟使用者没关系，设置页里看得到。
                Text(persona.tagline)
                    .font(.rj(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()

            // 人格切换。菜单里连 tagline 一起显示 ——
            // 光看「心灵导师」四个字，不知道它跟「复盘教练」差在哪。
            MenuIcon(symbol: persona.symbol, help: "切换人格（当前：\(persona.name)）", iconSize: 12.5) {
                ForEach(AIPersonas.all) { p in
                    Button {
                        personaId = p.id
                    } label: {
                        if p.id == personaId {
                            Label("\(p.name) · \(p.tagline)", systemImage: "checkmark")
                        } else {
                            Text("\(p.name) · \(p.tagline)")
                        }
                    }
                }
            }

            MenuIcon(symbol: "slider.horizontal.3", help: "上下文范围", iconSize: 12.5) {
                Picker("上下文范围", selection: $scope) {
                    Text("当前这一篇").tag("current")
                    Text("今天全部").tag("today")
                    Text("最近 7 天").tag("week")
                    Text("本月").tag("month")
                    Text("全部日记").tag("all")
                }
            }

            // 清空会话原来埋在左边那个 ⋯ 菜单里，藏得太深。
            // 提成一个常驻按钮放在对话区上方（用户要求）。
            IconButton(symbol: "trash",
                       help: messages.isEmpty ? "还没有对话" : "清空会话",
                       active: false,
                       tint: messages.isEmpty ? nil : .red,
                       iconSize: 12.5) {
                guard !messages.isEmpty else {
                    store.show("现在还没有对话")
                    return
                }
                confirmClear = true
            }
            .disabled(messages.isEmpty)

            IconButton(symbol: "xmark", help: "收起", iconSize: 12.5) { isPresented = false }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.rjBar)
    }

    // MARK: 快捷动作

    private var quickActions: some View {
        VStack(spacing: 6) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                quick("总结今天", "sun.max") { summarize(kind: "today") }
                quick("总结本周", "calendar") { summarize(kind: "week") }
                quick("总结本月", "calendar.badge.clock") { summarize(kind: "month") }
                quick("情绪洞察", "waveform.path.ecg") { summarize(kind: "mood") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            if summaryBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在写总结…").font(.rj(11.5)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private func quick(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        QuickChip(title: title, symbol: symbol, action: action)
    }

    // MARK: 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { msg in
                        bubble(msg)
                            .id(msg.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: messages.last?.content) { _, _ in
                if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你好，我是小迹 👋")
                .font(.rj(14, weight: .semibold))
            Text("我现在是「\(persona.name)」——\(persona.scene)。\n在下面输入框说话，或者点上面的快捷按钮；顶部那个人格图标随时可以换人。")
                .font(.rj(12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("当前上下文：\(scopeLabel)")
                .font(.rj(11.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.rjAccent.opacity(0.07)))
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == "user"
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            Group {
                if isUser {
                    Text(msg.content)
                        .font(.rj(13))
                        .textSelection(.enabled)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.rjAccent.opacity(0.92)))
                        .foregroundStyle(.white)
                } else if msg.content.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("思考中…").font(.rj(12)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    MarkdownPreview(text: msg.content, store: store, entry: currentEntry,
                                    fontSize: 12.5, style: store.settings.mdStyle, soft: true)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser && !msg.content.isEmpty {
                HStack(spacing: 4) {
                    iconButton("doc.on.doc", "复制这段回答") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.content, forType: .string)
                        store.show("已复制")
                    }
                    if currentEntry != nil {
                        iconButton("arrow.down.to.line", "插入到当前日记末尾") {
                            guard var e = store.entries.first(where: { $0.id == currentEntryId }) else { return }
                            e.body += "\n\n---\n\n" + msg.content + "\n"
                            store.update(e, immediate: true)
                            store.show("已插入日记末尾")
                        }
                    }
                    iconButton("square.and.pencil", "存为一篇新日记") {
                        var e = store.createEntry(body: msg.content)
                        e.title = "小迹 · " + Fmt.friendlyDay(Date())
                        e.tags = ["AI"]
                        store.update(e, immediate: true)
                        store.show("已存为新日记")
                    }
                    Spacer()
                }
            }
        }
    }

    private func iconButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        MiniIconButton(symbol: symbol, tip: tip, action: action)
    }

    // MARK: 输入

    private var composer: some View {
        VStack(spacing: 6) {
            if let err = ai.lastError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.rj(10))
                    Text(err).font(.rj(11.5)).lineLimit(3)
                    Spacer()
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("和小迹说点什么…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.rj(13))
                    .lineLimit(1...5)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
                    .focused($inputFocused)
                    .onSubmit { send() }

                if ai.isStreaming {
                    Button {
                        ai.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.rj(12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.red.opacity(0.85)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.rj(13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(input.trimmed.isEmpty
                                                      ? AnyShapeStyle(Color.secondary.opacity(0.3))
                                                      : AnyShapeStyle(Color.rjAccent)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmed.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            // 这里原来还有一行「上下文：当前这一篇《…》」。
            // 上下文范围上面的菜单里选着、模型名字在面板顶部写着，再重复一遍只是噪音。
            HStack {
                Spacer()
                Text("AI 生成内容仅供参考")
                    .font(.rj(10.5))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.rjBar)
    }

    // MARK: 逻辑

    private var scopeLabel: String {
        switch scope {
        case "current": return currentEntry.map { "《\($0.displayTitle)》" } ?? "当前日记（未选中）"
        case "today": return "今天全部日记"
        case "week": return "最近 7 天"
        case "month": return "本月"
        default: return "全部日记"
        }
    }

    private func contextEntries() -> [Entry] {
        let cal = Calendar.current
        // 一律走 `visible`：上锁且未解锁的日记本，内容不该被塞进给模型的上下文里
        switch scope {
        case "current":
            if let e = currentEntry { return [e] }
            return store.entries(on: Date())
        case "today":
            return store.entries(on: Date())
        case "week":
            let from = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
            return store.visible.filter { $0.createdAt >= from }
        case "month":
            return store.visible.filter { cal.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
        default:
            return Array(store.visible.prefix(60))
        }
    }

    private func contextText() -> String {
        let list = contextEntries().filter { !$0.plainText.trimmed.isEmpty }
        guard !list.isEmpty else { return "（当前范围内还没有日记内容。）" }
        var text = list.sorted { $0.createdAt < $1.createdAt }.map { e in
            "【\(Fmt.day.string(from: e.createdAt)) \(e.timeText)】\(e.displayTitle)\n\(e.plainText)"
        }.joined(separator: "\n\n")
        if text.count > 24_000 { text = String(text.suffix(24_000)) }
        return text
    }

    private func buildMessages(userText: String) -> [ChatMessage] {
        var out: [ChatMessage] = []
        // 人格 + 称呼 + 档案（生日/星座/MBTI）+ 自定义背景 + 记忆（见 MemoryStore）
        var system = AIPrompts.system(for: personaId,
                                      memory: store.memory.contextBlock(),
                                      nickname: store.settings.userNickname,
                                      custom: store.settings.customPrompt,
                                      profile: store.personaContext())
        system += "\n\n—— 以下是可参考的日记内容（\(scopeLabel)）——\n" + contextText()
        out.append(ChatMessage(role: "system", content: system))
        for m in messages.suffix(12) where !m.content.isEmpty {
            out.append(ChatMessage(role: m.role, content: m.content))
        }
        out.append(ChatMessage(role: "user", content: userText))
        return out
    }

    private func send() {
        let text = input.trimmed
        guard !text.isEmpty, !ai.isStreaming else { return }
        input = ""
        messages.append(ChatMessage(role: "user", content: text))
        messages.append(ChatMessage(role: "assistant", content: ""))
        let index = messages.count - 1
        let payload = buildMessages(userText: text)
        let key = AIKeyStore.read() ?? ""

        ai.stream(baseURL: store.settings.aiBaseURL,
                  apiKey: key,
                  model: store.settings.aiModel,
                  temperature: store.settings.aiTemperature,
                  messages: payload) { delta in
            if index < messages.count {
                messages[index].content += delta
            }
        }
    }

    private func summarize(kind: String) {
        guard !summaryBusy else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var entries: [Entry] = []
        var prompt = ""
        var label = ""

        switch kind {
        case "today":
            entries = store.entries(on: Date())
            label = "今天"
            guard !entries.isEmpty else { store.show("今天还没有日记"); return }
            prompt = AIPrompts.summarizeDay(entries, date: Date())
        case "week":
            let from = cal.date(byAdding: .day, value: -6, to: today) ?? today
            entries = store.visible.filter { $0.createdAt >= from }
            label = "最近 7 天"
            guard !entries.isEmpty else { store.show("最近 7 天还没有日记"); return }
            prompt = AIPrompts.summarizeRange(entries, label: label)
        case "month":
            entries = store.visible.filter { cal.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
            label = "本月"
            guard !entries.isEmpty else { store.show("本月还没有日记"); return }
            prompt = AIPrompts.summarizeRange(entries, label: label)
        default:
            // 情绪洞察单独一套提示词。原来是在阶段总结后面追加一句「另外重点分析情绪」，
            // 模型会把两件事混在一起写，结果既不是阶段总结也不是情绪分析。
            entries = Array(store.visible.prefix(30))
            guard !entries.isEmpty else { store.show("还没有日记"); return }
            label = "最近的日记"
            prompt = AIPrompts.moodInsight(entries, label: label)
        }

        summaryBusy = true
        let key = AIKeyStore.read() ?? ""
        messages.append(ChatMessage(role: "user", content: "帮我总结\(label)（\(entries.count) 篇）"))
        messages.append(ChatMessage(role: "assistant", content: ""))
        let index = messages.count - 1

        // 总结也走流式。原来用的是 `complete`（等全部生成完才一次性塞进气泡），
        // 一篇阶段总结要等十几秒、界面全程只有一个转圈 —— 和对话那边的体验对不上。
        ai.stream(baseURL: store.settings.aiBaseURL,
                  apiKey: key,
                  model: store.settings.aiModel,
                  temperature: 0.6,
                  messages: [
                    ChatMessage(role: "system", content: AIPrompts.system(for: personaId)),
                    ChatMessage(role: "user", content: prompt)
                  ]) { delta in
            if index < messages.count { messages[index].content += delta }
        } onFinish: {
            summaryBusy = false
        }
    }
}

// MARK: - 快捷动作胶囊

struct QuickChip: View {
    var title: String
    var symbol: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.rj(10.5, weight: .semibold))
                Text(title).font(.rj(12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.rjAccent.opacity(hovering ? 0.20 : 0.11)))
            .foregroundStyle(Color.rjAccent)
            .contentShape(Capsule())
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.93))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - 气泡下的次要动作

/// 只有图标的小按钮，停在上面才出说明。
///
/// 这三个动作（复制 / 插入日记 / 存为新日记）不是主流程，写全名会跟 AI 的回答
/// 抢注意力 —— 每条回复下面都挂一行「复制 插入日记 存为新日记」，扫起来很吵。
/// 收成图标，需要的时候 hover 一下就知道是干什么的。
struct MiniIconButton: View {
    var symbol: String
    var tip: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.rj(11.5, weight: .semibold))
                .foregroundStyle(hovering ? Color.rjAccent : Color.secondary)
                // 图标本身只有十来个点，不加框的话鼠标很难点中
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.rjAccent.opacity(0.10) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.90))
        .help(tip)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
