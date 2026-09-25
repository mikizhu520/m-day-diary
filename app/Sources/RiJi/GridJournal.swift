import SwiftUI
import AppKit

// MARK: - 九宫格模板

/// 「九宫格日记」的一张模板：九条问题。
///
/// 内置三套（经典 / 晨间 / 晚间复盘）。用户可以在填写面板里直接改问题文本，
/// 改完点「存为我的模板」就落进 config.json —— 所以**模板本身也是可编辑的数据**，
/// 不是写死的常量。走的是和 `AppSettings` 一样的逐字段容错解码，
/// 以后加字段不会把用户的模板清掉。
struct GridTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var symbol: String = GridTemplate.defaultSymbol
    var colorHex: String = RJ.accentDefault
    /// 九条问题。顺序就是格子的顺序：左到右、上到下。
    var questions: [String] = []
    /// 内置模板的标记（显示小徽章 + 「恢复内置」时对照）
    var builtIn: Bool = false

    static let slotCount = 9
    static let defaultSymbol = "square.grid.3x3.fill"
    static let fallbackName = "未命名模板"
    /// 内置模板的 id 前缀，用来判断「这条是不是原厂自带」
    static let builtInPrefix = "builtin."

    var isBuiltIn: Bool { builtIn || id.hasPrefix(GridTemplate.builtInPrefix) }

    /// 缺格补齐、多格截断、空问题给占位。
    ///
    /// 之所以要「补齐」而不是丢弃：网格是 3×3 固定九格，
    /// 少一条问题就会让 `ForEach(0..<9)` 越界或错位。
    func normalized() -> GridTemplate {
        var t = self
        let trimmedName = name.trimmed
        t.name = trimmedName.isEmpty ? GridTemplate.fallbackName : trimmedName
        if t.symbol.trimmed.isEmpty { t.symbol = GridTemplate.defaultSymbol }
        if !Journal.isValidHex(t.colorHex) { t.colorHex = RJ.accentDefault }

        var qs = questions.map { $0.trimmed }
        if qs.count > GridTemplate.slotCount {
            qs = Array(qs.prefix(GridTemplate.slotCount))
        }
        while qs.count < GridTemplate.slotCount {
            qs.append("")
        }
        for i in qs.indices where qs[i].isEmpty {
            qs[i] = GridTemplate.placeholderQuestion(i)
        }
        t.questions = qs
        return t
    }

    static func placeholderQuestion(_ index: Int) -> String { "第 \(index + 1) 格" }

    // MARK: 内置模板

    static let builtIns: [GridTemplate] = [
        GridTemplate(
            id: builtInPrefix + "classic",
            name: "经典九宫格",
            symbol: "square.grid.3x3.fill",
            colorHex: "#C85A37",
            questions: [
                "🎯 今天最重要的一件事",
                "😊 最开心的一刻",
                "🙏 最想感谢的人",
                "💪 今天做得不错的一件事",
                "🧗 卡住我的一件事",
                "💡 今天学到的东西",
                "🫀 身体的感觉",
                "👣 明天的第一步",
                "✍️ 一句话总结今天"
            ],
            builtIn: true
        ),
        GridTemplate(
            id: builtInPrefix + "morning",
            name: "晨间九宫格",
            symbol: "sunrise.fill",
            colorHex: "#D9A02E",
            questions: [
                "😴 昨晚睡得怎么样",
                "🌤️ 今天的天气与心情",
                "🎯 今天最重要的一件事",
                "📋 今天必须完成的三件事",
                "🚫 今天想避免的一件事",
                "🌟 今天在期待什么",
                "🫀 现在的身体状态",
                "🗓️ 今天的时间怎么安排",
                "💬 送给自己的一句话"
            ],
            builtIn: true
        ),
        GridTemplate(
            id: builtInPrefix + "review",
            name: "晚间复盘",
            symbol: "moon.stars.fill",
            colorHex: "#5B6BE0",
            questions: [
                "✅ 今天做成了什么",
                "🧗 卡在哪里",
                "🎁 今天最大的收获",
                "📈 情绪的高点",
                "📉 情绪的低点",
                "🙏 想感谢的人",
                "🔧 明天改进一件",
                "🫀 现在的身体状态",
                "✍️ 一句话记录今天"
            ],
            builtIn: true
        )
    ]

    /// 一张全新的空白模板（九格都是占位问题）
    static func blank() -> GridTemplate {
        GridTemplate(name: "我的九宫格", colorHex: RJ.accentDefault,
                     questions: (0..<slotCount).map { placeholderQuestion($0) })
    }

    // MARK: 生成正文

    /// 把九格的答案拼成日记正文（标准 Markdown）。
    ///
    /// 为什么不用 3×3 表格：Markdown 的表格单元格**装不下换行**，
    /// 而且即时渲染模式下表格只是「逐行加底纹」，看不到真正的列对齐 ——
    /// 所以九宫格的价值放在**填写面板**里（真的 3×3 网格），
    /// 落到正文的是纵向的「加粗问题 + 答案」，在编辑器和预览里都好看。
    static func markdown(from template: GridTemplate, answers: [String]) -> String {
        let t = template.normalized()
        var lines: [String] = ["### 九宫格日记 · \(t.name)", ""]
        for (i, q) in t.questions.enumerated() {
            let a = (i < answers.count ? answers[i] : "").trimmed
            lines.append("**\(q)**")
            lines.append("")
            if !a.isEmpty {
                lines.append(contentsOf: a.components(separatedBy: "\n"))
                lines.append("")
            }
        }
        // 末尾的空行不留，免得每次追加都攒一堆空白
        while let last = lines.last, last.trimmed.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

// MARK: 模板的容错解码
//
// 模板列表和密码同在 config.json 里，整体解码失败会把密码一起丢掉，
// 所以逐字段解：缺名字 / 颜色非法 / 问题数量不对，全都有兜底。

extension GridTemplate {
    enum CodingKeys: String, CodingKey {
        case id, name, symbol, colorHex, questions, builtIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let v = try? c.decodeIfPresent(T.self, forKey: key) else { return fallback }
            return v
        }

        let rawId = value(.id, "").trimmed
        id = rawId.isEmpty ? UUID().uuidString : rawId

        let rawName = value(.name, "").trimmed
        name = rawName.isEmpty ? GridTemplate.fallbackName : rawName

        let sym = value(.symbol, GridTemplate.defaultSymbol).trimmed
        symbol = sym.isEmpty ? GridTemplate.defaultSymbol : sym

        let hex = value(.colorHex, RJ.accentDefault)
        colorHex = Journal.isValidHex(hex) ? hex : RJ.accentDefault

        questions = value(.questions, [String]())
        builtIn = value(.builtIn, false)
    }
}

// MARK: - 打开九宫格时的意图

/// 九宫格面板这一次是「为谁」而开。
struct GridDraft: Identifiable, Equatable {
    var id = UUID().uuidString
    /// nil = 填完生成一篇新日记；非 nil = 追加到这篇日记的末尾
    var targetEntryId: String?
    /// 新建时归到哪个日记本（nil = 用默认本）
    var journalId: String?
    /// 打开时预选的模板；空串 = 第一张
    var templateId: String = ""
    /// 打开时预填的答案。正常使用永远是空的，
    /// 只有截图 / 演示流程会塞进来（不然拍到的九格全是空的）。
    var prefillAnswers: [String] = []
}

// MARK: - 九宫格填写面板

/// 3×3 的问题网格：左边一列问题、格子里写答案，底部一键落成日记。
struct GridJournalSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let draft: GridDraft
    /// 生成 / 追加完成后回传日记 id，让主窗口跳过去
    var onDone: (String) -> Void = { _ in }

    @State private var templateId: String = ""
    @State private var questions: [String] = (0..<GridTemplate.slotCount).map { GridTemplate.placeholderQuestion($0) }
    @State private var answers: [String] = Array(repeating: "", count: GridTemplate.slotCount)
    /// 名字改了但还没存成模板
    @State private var nameDirty = false
    @FocusState private var focusedSlot: Int?

    private var templates: [GridTemplate] { store.gridTemplates }
    private var current: GridTemplate? { templates.first { $0.id == templateId } }
    private var accent: Color { Color(hex: current?.colorHex ?? RJ.accentDefault) }
    private var filledCount: Int { answers.filter { !$0.trimmed.isEmpty }.count }
    /// 问题被改过（和仓库里那份不一致）
    private var questionsDirty: Bool {
        guard let t = current else { return false }
        return t.normalized().questions != questions.map { $0.trimmed }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairLine()
            templateBar
            HairLine()
            ScrollView {
                grid
            }
            HairLine()
            footer
        }
        .frame(width: 880, height: 720)
        .background(Color.rjBar)
        .tint(Color.rjAccent)
        .onAppear {
            load(draft.templateId)
            // 截图 / 演示用：把预填答案灌进去（正常打开时这个数组是空的）
            for i in 0..<min(draft.prefillAnswers.count, answers.count) {
                answers[i] = draft.prefillAnswers[i]
            }
        }
    }

    // MARK: 头

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "square.grid.3x3.fill")
                    .font(.rj(15, weight: .medium))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("九宫格日记")
                    .font(.rj(16, weight: .bold, design: .rounded))
                Text(draft.targetEntryId == nil
                     ? "回答九个问题，写完直接生成一篇日记"
                     : "回答九个问题，追加到这篇日记的末尾")
                    .font(.rj(11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: "xmark", help: "关闭", size: 28, iconSize: 12) { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: 模板条

    private var templateBar: some View {
        HStack(spacing: 9) {
            Text("模板")
                .font(.rj(12, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(templates) { t in
                        chip(t)
                    }
                }
                .padding(.vertical, 1)
            }

            Spacer(minLength: 6)

            IconButton(symbol: "plus", help: "新建一张空白模板", size: 26, iconSize: 11) {
                let t = GridTemplate.blank()
                store.saveGridTemplate(t)
                load(t.id)
            }
            if store.hasCustomGridTemplates {
                IconButton(symbol: "arrow.counterclockwise", help: "恢复内置模板（自己加的会保留）",
                           size: 26, iconSize: 11) {
                    store.resetGridTemplates()
                    load(GridTemplate.builtIns.first?.id)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func chip(_ t: GridTemplate) -> some View {
        let active = t.id == templateId
        let color = Color(hex: t.colorHex)
        return Button {
            load(t.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: t.symbol).font(.rj(10.5))
                Text(t.name).font(.rj(12, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Color.white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(active ? color : color.opacity(0.13)))
        }
        .buttonStyle(PressableStyle())
        .help(t.isBuiltIn ? "内置模板（可改，改完点「存为我的模板」）" : "我的模板")
    }

    // MARK: 九宫格

    private var grid: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { col in
                        slotCell(row * 3 + col)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func slotCell(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("\(i + 1)")
                    .font(.rj(9.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(accent))
                TextField("问题 \(i + 1)", text: binding(for: i))
                    .textFieldStyle(.plain)
                    .font(.rj(12, weight: .semibold))
                    .focused($focusedSlot, equals: i)
                    .onSubmit { focusedSlot = i < 8 ? i + 1 : nil }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $answers[i])
                    .font(.rj(12.5))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                if answers[i].trimmed.isEmpty {
                    Text("写点什么…")
                        .font(.rj(12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 104)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.rjBar))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09)))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整窗现在是白的，所以格子自己铺一层极淡的灰才分得出来
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(accent.opacity(0.14)))
    }

    /// 问题的绑定。写成函数是因为数组下标直接做 Binding 在 `ForEach(0..<9)` 里
    /// 容易越界 —— 这里统一夹一下范围。
    private func binding(for i: Int) -> Binding<String> {
        Binding(
            get: { i < questions.count ? questions[i] : "" },
            set: { v in
                guard i < questions.count else { return }
                questions[i] = v
            }
        )
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Text("已填 \(filledCount) / \(GridTemplate.slotCount)")
                .font(.rj(12, weight: .medium))
                .foregroundStyle(filledCount == 0 ? Color.secondary : accent)

            Spacer()

            Button {
                saveTemplate()
            } label: {
                Label(questionsDirty ? "存为我的模板" : "模板已是最新",
                      systemImage: questionsDirty ? "square.and.arrow.down" : "checkmark")
                    .font(.rj(12.5, weight: .medium))
            }
            .buttonStyle(RJSubtleButtonStyle())
            .disabled(!questionsDirty)
            .help("把改过的九条问题存下来，下次打开还是这套")

            Button("取消") { dismiss() }
                .buttonStyle(RJSubtleButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button {
                generate()
            } label: {
                Label(draft.targetEntryId == nil ? "生成日记" : "写入这篇",
                      systemImage: "checkmark.circle.fill")
                    .font(.rj(12.5, weight: .semibold))
            }
            .buttonStyle(RJPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    // MARK: 动作

    /// 切模板 / 首次打开时装载问题。答案不动（切回来还在）。
    private func load(_ id: String?) {
        let pool = templates.isEmpty ? GridTemplate.builtIns : templates
        let t = pool.first { $0.id == id } ?? pool.first ?? GridTemplate.builtIns[0]
        let n = t.normalized()
        templateId = n.id
        questions = n.questions
        focusedSlot = nil
    }

    /// 存问题：内置模板 → 另存成「我的」副本；自定义模板 → 直接更新
    private func saveTemplate() {
        guard var t = current else { return }
        let edited = questions.map { $0.trimmed }
        if t.isBuiltIn {
            t.id = UUID().uuidString
            t.name = t.name + "（我的）"
            t.builtIn = false
        }
        t.questions = edited
        store.saveGridTemplate(t.normalized())
        load(t.id)
        store.show(t.isBuiltIn ? "已更新模板" : "已存为「\(t.name)」")
    }

    private func generate() {
        guard let base = current else { return }
        // 用面板里当前的问题文本（可能已改），确保正文和眼前看到的一致
        var t = base
        t.questions = questions.map { $0.trimmed }
        let md = GridTemplate.markdown(from: t, answers: answers)

        if let target = draft.targetEntryId,
           var e = store.entries.first(where: { $0.id == target }) {
            e.body = e.body.trimmed.isEmpty ? md : e.body.trimmed + "\n\n" + md
            store.update(e, immediate: true)
            store.show("九宫格已写入这篇日记")
            onDone(e.id)
        } else {
            let e = store.createEntry(journalId: draft.journalId, body: md)
            if let j = store.journal(for: e.journalId) {
                store.show("已在「\(j.name)」新建九宫格日记")
            } else {
                store.show("九宫格日记已创建")
            }
            onDone(e.id)
        }
        dismiss()
    }
}
