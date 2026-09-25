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
    @State private var busy = false
    @State private var summaryBusy = false
    @FocusState private var inputFocused: Bool

    private var currentEntry: Entry? {
        guard let currentEntryId else { return nil }
        return store.entries.first { $0.id == currentEntryId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairLine()
            quickActions
            HairLine()
            messageList
            HairLine()
            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { scope = store.settings.aiContextScope }
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
            VStack(alignment: .leading, spacing: 0) {
                Text("小迹").font(.rj(14, weight: .bold))
                Text(store.settings.aiModel)
                    .font(.rj(11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            MenuIcon(symbol: "slider.horizontal.3", help: "上下文范围与清空对话", iconSize: 12.5) {
                Picker("上下文范围", selection: $scope) {
                    Text("当前这一篇").tag("current")
                    Text("今天全部").tag("today")
                    Text("最近 7 天").tag("week")
                    Text("本月").tag("month")
                    Text("全部日记").tag("all")
                }
                Divider()
                Button("清空对话") { messages.removeAll() }
            }

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
            Text("我可以读你的日记，帮你总结、找规律、聊聊最近的状态。\n在下面输入框说话，或者点上面的快捷按钮。")
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
                                    fontSize: 12.5, style: store.settings.mdStyle)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser && !msg.content.isEmpty {
                HStack(spacing: 6) {
                    miniButton("复制", "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.content, forType: .string)
                        store.show("已复制")
                    }
                    if currentEntry != nil {
                        miniButton("插入日记", "arrow.down.to.line") {
                            guard var e = store.entries.first(where: { $0.id == currentEntryId }) else { return }
                            e.body += "\n\n---\n\n" + msg.content + "\n"
                            store.update(e, immediate: true)
                            store.show("已插入日记末尾")
                        }
                    }
                    miniButton("存为新日记", "square.and.pencil") {
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

    private func miniButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        MiniActionButton(title: title, symbol: symbol, action: action)
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

            HStack {
                Text("上下文：\(scopeLabel)")
                    .font(.rj(10.5))
                    .foregroundStyle(.quaternary)
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
        switch scope {
        case "current":
            if let e = currentEntry { return [e] }
            return store.entries(on: Date())
        case "today":
            return store.entries(on: Date())
        case "week":
            let from = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
            return store.entries.filter { $0.createdAt >= from }
        case "month":
            return store.entries.filter { cal.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
        default:
            return Array(store.entries.prefix(60))
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
        var system = AIPrompts.chatSystem
        if store.settings.customPrompt.nilIfEmpty != nil {
            system += "\n\n用户自定义偏好：\(store.settings.customPrompt)"
        }
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
            entries = store.entries.filter { $0.createdAt >= from }
            label = "最近 7 天"
            guard !entries.isEmpty else { store.show("最近 7 天还没有日记"); return }
            prompt = AIPrompts.summarizeRange(entries, label: label)
        case "month":
            entries = store.entries.filter { cal.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
            label = "本月"
            guard !entries.isEmpty else { store.show("本月还没有日记"); return }
            prompt = AIPrompts.summarizeRange(entries, label: label)
        default:
            entries = Array(store.entries.prefix(30))
            guard !entries.isEmpty else { store.show("还没有日记"); return }
            label = "最近的日记"
            prompt = AIPrompts.summarizeRange(entries, label: label) + "\n\n另外：请重点分析情绪变化规律，指出反复出现的压力源和恢复方式。"
        }

        summaryBusy = true
        let key = AIKeyStore.read() ?? ""
        messages.append(ChatMessage(role: "user", content: "帮我总结\(label)（\(entries.count) 篇）"))
        let index = messages.count
        messages.append(ChatMessage(role: "assistant", content: ""))
        _ = index

        Task {
            do {
                let text = try await ai.complete(baseURL: store.settings.aiBaseURL,
                                                 apiKey: key,
                                                 model: store.settings.aiModel,
                                                 temperature: 0.6,
                                                 messages: [
                                                    ChatMessage(role: "system", content: AIPrompts.systemBase),
                                                    ChatMessage(role: "user", content: prompt)
                                                 ])
                messages[messages.count - 1].content = text
            } catch let e as AIError {
                messages[messages.count - 1].content = "⚠️ \(e.message)"
            } catch {
                messages[messages.count - 1].content = "⚠️ \(error.localizedDescription)"
            }
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

struct MiniActionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.rj(9.5, weight: .semibold))
                Text(title).font(.rj(11.5, weight: .medium))
            }
            .foregroundStyle(hovering ? Color.rjAccent : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.rjAccent.opacity(0.10) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.93))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
