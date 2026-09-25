import Foundation
import SwiftUI

// MARK: - 记忆
//
// 小迹为什么会「懂」使用者：日记里散着大量关于本人的事实 ——
// 住哪儿、几点下班、对什么过敏、在攒什么劲。这些不是某一天的流水账，
// 而是跨天都成立的东西。每次对话都临时去翻全部日记既慢又贵，
// 所以把它们抽出来沉淀成一份本地记忆文件，回答时作为背景带上。
//
// 文件落在 Application Support/日迹/memory.json：
//   · 不混进日记目录（那儿是给人看的 .md，会被同步、会被导出）
//   · 不上传，纯本机；清掉就等于让小迹「忘掉」这个人
//
// 数据来源只有一处：日记正文。抽什么由模型判断，去重、入库、裁剪由这里决定。

// MARK: 分类

enum MemoryCategory: String, CaseIterable, Codable, Identifiable {
    case profile     // 个人信息：年龄、职业、常住城市、身体数据
    case preference  // 偏好：喜欢/讨厌、口味、审美、消费取向
    case habit       // 日常习惯：作息、通勤、饮食、运动、固定流程
    case relation    // 人际关系：家人、伴侣、同事、朋友、宠物（含称呼）
    case health      // 健康：慢性病、过敏、禁忌、用药、作息问题
    case work        // 工作与项目：岗位、项目进展、组织关系
    case goal        // 目标与计划：想做成的事、截止点、正在攒的东西
    case emotion     // 情绪规律：什么会让你低落、什么能把你拉回来
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .profile: return "个人信息"
        case .preference: return "偏好"
        case .habit: return "日常习惯"
        case .relation: return "人际关系"
        case .health: return "健康"
        case .work: return "工作"
        case .goal: return "目标"
        case .emotion: return "情绪规律"
        case .other: return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .profile: return "person.fill"
        case .preference: return "heart.fill"
        case .habit: return "repeat"
        case .relation: return "person.2.fill"
        case .health: return "cross.case.fill"
        case .work: return "briefcase.fill"
        case .goal: return "flag.fill"
        case .emotion: return "waveform.path.ecg"
        case .other: return "tag.fill"
        }
    }

    /// 认不出来的分类名退回「其他」，绝不因为一个新词把整份文件判死
    static func from(_ raw: String) -> MemoryCategory {
        let key = raw.trimmed.lowercased()
        if let hit = allCases.first(where: { $0.rawValue == key }) { return hit }
        // 模型偶尔会用中文或近义词，这里兜一下常见的几种写法
        for c in allCases where key.contains(c.label) || c.label.contains(key) { return c }
        return .other
    }
}

// MARK: 单条事实

struct MemoryFact: Codable, Identifiable, Hashable {
    /// 稳定 id = 分类 + 归一化文本。同一件事被多天的日记反复提到时，
    /// 靠它认出「还是同一条」，只更新来源和时间，不堆重复条目。
    var id: String
    var category: String
    var text: String
    /// 第一次是从哪一天的日记里读到的（yyyy-MM-dd）
    var source: String
    /// 模型给的把握程度 0...1。低分的在提示词里排在后面。
    var confidence: Double
    var createdAt: Date
    var updatedAt: Date

    init(category: MemoryCategory, text: String, source: String, confidence: Double) {
        self.category = category.rawValue
        self.text = text
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.id = MemoryFact.makeId(category: category, text: text)
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    var kind: MemoryCategory { MemoryCategory.from(category) }

    static func makeId(category: MemoryCategory, text: String) -> String {
        "\(category.rawValue)|\(normalize(text))"
    }

    /// 归一化的目的是让「住在北京」和「住在北京。」算同一条：
    /// 去掉空白和标点，只留内容本身。
    static func normalize(_ s: String) -> String {
        let kept = s.lowercased().filter { !$0.isWhitespace && !$0.isNewline && !$0.isPunctuation }
        return kept.isEmpty ? s.trimmed.lowercased() : kept
    }
}

// MARK: 文件

struct MemoryFile: Codable {
    var version: Int = 1
    var facts: [MemoryFact] = []
    /// entryId → 提取时那篇日记的 updatedAt（秒）。
    /// 日记改过之后再抽一遍，没改过就跳过 —— 省掉大部分无谓的调用。
    var processed: [String: Double] = [:]
    var lastRunAt: Date?

    /// 自定义解码器一定义，Swift 就不再合成无参 init，这里补回来
    init() {}

    /// 逐字段解码：记忆是「锦上添花」的数据，文件坏了最多是让小迹失忆，
    /// 绝不能因此把整个 App 拖垮 —— 所以坏数据一律退回空文件。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        facts = (try? c.decode([MemoryFact].self, forKey: .facts)) ?? []
        processed = (try? c.decode([String: Double].self, forKey: .processed)) ?? [:]
        lastRunAt = try? c.decode(Date.self, forKey: .lastRunAt)
    }
}

// MARK: 解析模型返回的 JSON

enum MemoryParser {
    /// 模型有时会裹一层 ```json 围栏，有时会先说一句「好的，以下是」再给数组。
    /// 这里一律按「第一个 [ 到最后一个 ]」切，再交给 JSONSerialization。
    static func extractJSON(_ raw: String) -> String? {
        var s = raw.trimmed
        if let head = s.range(of: "```") {
            s = String(s[head.upperBound...])
            if let tail = s.range(of: "```") { s = String(s[..<tail.lowerBound]) }
        }
        s = s.trimmed
        guard let a = s.firstIndex(of: "["), let b = s.lastIndex(of: "]"), a < b else { return nil }
        return String(s[a...b])
    }

    static func parse(_ raw: String, sourceDay: String = "") -> [MemoryFact] {
        guard let json = extractJSON(raw),
              let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        var out: [MemoryFact] = []
        for item in array {
            let text = ((item["text"] as? String) ?? (item["fact"] as? String) ?? "").trimmed
            // 太短的（「北京」）和太长的（整段复述）都不算「事实」
            guard text.count >= 3, text.count <= 60 else { continue }
            let cat = MemoryCategory.from((item["category"] as? String) ?? "")
            var conf = (item["confidence"] as? Double) ?? 0.7
            if conf < 0 { conf = 0 }
            if conf > 1 { conf = 1 }
            out.append(MemoryFact(category: cat, text: text, source: sourceDay, confidence: conf))
        }
        return out
    }
}

// MARK: 提示词

enum MemoryPrompts {
    /// 抽取提示词。要求输出纯 JSON，规则写得死一点，否则模型会给你一堆流水账。
    static func extract(_ entries: [Entry]) -> String {
        let body = entries.map { e in
            "【\(Fmt.day.string(from: e.createdAt))】\n\(e.plainText)"
        }.joined(separator: "\n\n")
        return """
        你会读到同一个人的几篇日记。请从中提炼出「关于这个人本身」的事实，
        用来让以后的对话更贴合他/她。

        只抽这些类别（category 只能是这几个英文词之一）：
        · profile 个人信息：年龄、职业、常住/老家、身份类事实
        · preference 偏好：喜欢什么、讨厌什么、口味、审美、花钱的取向
        · habit 日常习惯：作息、通勤、饮食、运动、固定会做的事
        · relation 人际关系：家人、伴侣、同事、朋友、宠物（带称呼更好）
        · health 健康：慢性病、过敏、忌口、用药、睡眠问题
        · work 工作与项目：岗位、在推进的事、跟谁共事
        · goal 目标与计划：想做成的事、时间点、正在攒的东西
        · emotion 情绪规律：什么会让 ta 低落、什么能把 ta 拉回来

        怎么写每一条
        · 一条只说一件事，20 字以内，写成陈述句（「住在北京」「每天 23 点才到家」）。
        · 只写**跨天成立**的。当天的一次性事件（「今天吃了火锅」「开了一下午会」）不要抽，
          除非它能推出一条稳定事实（「连续三天吃火锅」→「喜欢吃火锅」）。
        · 不推测、不评价、不给建议。日记没写的别补。
        · 明确带「好像」「可能」的，confidence 给 0.4–0.6；反复出现或写得很肯定的给 0.8–1.0。

        输出
        · 只输出一个 JSON 数组，不要任何解释文字、不要 Markdown 围栏。
        · 格式：[{"category":"habit","text":"每天 23 点才到家","confidence":0.8}]
        · 最多 \(maxFactsPerRun) 条。实在抽不出就输出 []。

        ——— 日记正文 ———
        \(body)
        """
    }

    /// 一次最多抽多少条。限制是为了别让文件无限膨胀。
    static let maxFactsPerRun = 12

    /// 拼给系统提示词的那一段。按分类归拢，控制总长度，别把上下文吃光。
    static func block(_ facts: [MemoryFact], limit: Int = Self.contextLimit) -> String {
        guard !facts.isEmpty else { return "" }
        let sorted = facts.sorted { a, b in
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.updatedAt > b.updatedAt
        }
        var lines: [String] = []
        var used = 0
        for f in sorted {
            let line = "- [\(f.kind.label)] \(f.text)"
            used += line.count + 1
            if used > limit { break }
            lines.append(line)
        }
        guard !lines.isEmpty else { return "" }
        return """
        以下是从使用者过往日记里沉淀下来的已知信息，用来让回答更贴合他/她。
        自然地运用它们，不要逐条复述、不要说「根据我的记忆」。
        只在这些信息跟当前话题有关时才参考；和日记内容冲突时以日记为准。

        \(lines.joined(separator: "\n"))
        """
    }

    /// 注入上下文的字符上限。1200 字 ≈ 400 token，够放 30 来条，又不至于把对话挤没了。
    static let contextLimit = 1200
}

// MARK: 用户档案
//
// 生日、星座、MBTI 这类东西在日记里不会天天出现，但它们决定了小迹看这个人的底色。
// 放在设置里让人自己填一次，比让模型从日记里猜准得多。

enum UserProfile {

    /// 16 个类型。只认这 16 个写法的全大写形式 —— 认不出来的留空，别硬凑。
    static let mbtiTypes = [
        "INTJ", "INTP", "ENTJ", "ENTP",
        "INFJ", "INFP", "ENFJ", "ENFP",
        "ISTJ", "ISFJ", "ESTJ", "ESFJ",
        "ISTP", "ISFP", "ESTP", "ESFP"
    ]

    static func normalizeMBTI(_ raw: String) -> String {
        let s = raw.trimmed.uppercased()
        return mbtiTypes.contains(s) ? s : ""
    }

    /// 生日支持 1992-06-23 / 06-23 / 1992/6/23 三种写法。年份可省（省了就算不出年龄）。
    static func parseBirthday(_ text: String) -> (year: Int?, month: Int, day: Int)? {
        let s = text.trimmed
        guard !s.isEmpty else { return nil }
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." || $0 == "月" })
            .map { $0.trimmingCharacters(in: .init(charactersIn: "日 ")) }
        let nums = parts.compactMap { Int($0) }
        if nums.count >= 3, nums[0] > 1900, (1...12).contains(nums[1]), (1...31).contains(nums[2]) {
            return (nums[0], nums[1], nums[2])
        }
        if nums.count == 2, (1...12).contains(nums[0]), (1...31).contains(nums[1]) {
            return (nil, nums[0], nums[1])
        }
        return nil
    }

    static func age(from birthday: String, now: Date = Date()) -> Int? {
        guard let b = parseBirthday(birthday), let y = b.year else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: now)
        var age = year - y
        // 今年生日还没到就先不算这一岁
        var comps = DateComponents()
        comps.month = b.month
        comps.day = b.day
        comps.year = year
        if let thisYear = cal.date(from: comps), thisYear > now { age -= 1 }
        return (0...120).contains(age) ? age : nil
    }

    static func zodiacName(from birthday: String) -> String? {
        Zodiac.sign(fromBirthday: birthday)?.name
    }

    /// 给系统提示词用的一句话档案。没有任何一项就返回空，别硬塞一句「无」。
    static func summary(birthday: String, mbti: String, now: Date = Date()) -> String {
        var bits: [String] = []
        if let b = parseBirthday(birthday) {
            if let a = age(from: birthday, now: now) {
                bits.append("生日 \(b.month) 月 \(b.day) 日（\(a) 岁）")
            } else {
                bits.append("生日 \(b.month) 月 \(b.day) 日")
            }
        }
        if let z = zodiacName(from: birthday) { bits.append("\(z)座") }
        let m = normalizeMBTI(mbti)
        if !m.isEmpty { bits.append("MBTI 是 \(m)") }
        return bits.joined(separator: "，")
    }

    /// 档案里能沉淀成「记忆事实」的那几条。生日和星座各一条，
    /// 这样即便哪天没有注入系统提示词，记忆里也还在。
    static func facts(birthday: String, mbti: String, now: Date = Date()) -> [MemoryFact] {
        var out: [MemoryFact] = []
        if let b = parseBirthday(birthday) {
            out.append(MemoryFact(category: .profile,
                                  text: "生日是 \(b.month) 月 \(b.day) 日",
                                  source: "设置", confidence: 1.0))
            if let a = age(from: birthday, now: now) {
                out.append(MemoryFact(category: .profile, text: "\(a) 岁", source: "设置", confidence: 1.0))
            }
            if let z = zodiacName(from: birthday) {
                out.append(MemoryFact(category: .profile, text: "\(z)座", source: "设置", confidence: 1.0))
            }
        }
        let m = normalizeMBTI(mbti)
        if !m.isEmpty {
            out.append(MemoryFact(category: .profile, text: "MBTI 是 \(m)", source: "设置", confidence: 1.0))
        }
        return out
    }
}

// MARK: 仓库

@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var facts: [MemoryFact] = []
    @Published private(set) var lastRunAt: Date?
    @Published var isBusy = false
    @Published var lastMessage: String?

    /// 记忆文件条数上限。超了先丢「最久没被印证」的那些 ——
    /// 一条事实很久没再出现，通常说明它已经不成立了。
    static let capacity = 300
    /// 一次最多喂给模型多少篇日记（多了既慢又贵，还容易被截断）
    static let batchSize = 10

    private var fileURL: URL
    private var file: MemoryFile

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.file = MemoryFile()
        reload(from: fileURL)
    }

    /// 换一个文件（截图模式切到临时目录时用，绝不碰用户真正的记忆文件）
    func retarget(_ url: URL) {
        fileURL = url
        reload(from: url)
    }

    private func reload(from url: URL) {
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(MemoryFile.self, from: data) {
            file = loaded
        } else {
            file = MemoryFile()
        }
        facts = file.facts
        lastRunAt = file.lastRunAt
    }

    // MARK: 读写

    private func save() {
        file.facts = facts
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: 入库

    /// 合并一批新事实：已存在的只更新时间和来源，新的插进去，最后按容量裁剪。
    /// 返回真正新增的条数（给界面报「这次又记住了 N 条」用）。
    @discardableResult
    func merge(_ incoming: [MemoryFact], sourceDay: String = "") -> Int {
        var index: [String: Int] = [:]
        for (i, f) in facts.enumerated() { index[f.id] = i }
        var added = 0
        let now = Date()
        for f in incoming where !f.text.trimmed.isEmpty {
            if let i = index[f.id] {
                var old = facts[i]
                old.updatedAt = now
                if !sourceDay.isEmpty { old.source = sourceDay }
                // 后来抽到的把握更高，就信后来这个
                if f.confidence > old.confidence { old.confidence = f.confidence }
                facts[i] = old
            } else {
                var f = f
                if !sourceDay.isEmpty { f.source = sourceDay }
                facts.append(f)
                index[f.id] = facts.count - 1
                added += 1
            }
        }
        trim()
        file.lastRunAt = now
        lastRunAt = now
        save()
        return added
    }

    private func trim() {
        guard facts.count > Self.capacity else { return }
        let kept = facts.sorted { a, b in
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.updatedAt > b.updatedAt
        }
        facts = Array(kept.prefix(Self.capacity))
    }

    func remove(_ id: String) {
        facts.removeAll { $0.id == id }
        save()
    }

    func clear() {
        facts = []
        file.processed = [:]
        save()
    }

    /// 手动加一条。界面上和「从日记抽取」并存：模型抽不到的、
    /// 或者自己想让小迹记住的，直接写更准。
    func add(category: MemoryCategory, text: String, confidence: Double = 0.9) {
        guard !text.trimmed.isEmpty else { return }
        _ = merge([MemoryFact(category: category, text: text, source: "手动",
                              confidence: confidence)], sourceDay: "")
    }

    // MARK: 抽取

    /// 挑出「还没抽过 / 抽过之后又被改过」的日记，最多 batchSize 篇。
    func pending(_ entries: [Entry]) -> [Entry] {
        let fresh = entries.filter { e in
            let seen = file.processed[e.id] ?? -1
            return seen < e.updatedAt.timeIntervalSince1970 - 0.5
        }
        return Array(fresh.sorted { $0.createdAt > $1.createdAt }.prefix(Self.batchSize))
    }

    /// 标记这几篇已经处理过了。抽失败也照样标记 —— 否则同一批坏数据会被反复重试。
    func markProcessed(_ entries: [Entry]) {
        for e in entries { file.processed[e.id] = e.updatedAt.timeIntervalSince1970 }
        save()
    }

    func contextBlock() -> String {
        MemoryPrompts.block(facts)
    }

    /// 给 AI 的一段档案说明（生日 / 星座 / MBTI 特质），见 UserProfile + MBTIProfile。
    /// 这里从设置读，所以由 Store 调用后塞进来，记忆仓库本身不认识 AppSettings。
    func personaBlock(birthday: String, mbti: String) -> String {
        var parts: [String] = []
        let basic = UserProfile.summary(birthday: birthday, mbti: mbti)
        if !basic.isEmpty { parts.append(basic) }
        if let p = MBTIProfileBook.prompt(for: mbti) { parts.append(p) }
        return parts.joined(separator: "\n")
    }

    var countByCategory: [(MemoryCategory, Int)] {
        MemoryCategory.allCases.compactMap { c in
            let n = facts.filter { $0.kind == c }.count
            return n > 0 ? (c, n) : nil
        }
    }
}

// MARK: - 记忆明细面板
//
// 记忆是模型从日记里抽出来的，抽错、抽偏都会发生 —— 所以必须让人看得见、
// 删得掉、也能自己补一条。看不见的「AI 记住了你什么」是不放心的。

struct MemorySheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var category: MemoryCategory = .profile
    @State private var confirmClear = false

    private var grouped: [(MemoryCategory, [MemoryFact])] {
        MemoryCategory.allCases.compactMap { c in
            let list = store.memory.facts.filter { $0.kind == c }
                .sorted { $0.updatedAt > $1.updatedAt }
            return list.isEmpty ? nil : (c, list)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "brain")
                    .font(.rj(15, weight: .semibold))
                    .foregroundStyle(Color.rjAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("小迹记住了什么").font(.rj(14, weight: .bold))
                    Text("共 \(store.memory.facts.count) 条 · 都存在本机，不上传")
                        .font(.rj(11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    confirmClear = true
                } label: {
                    Label("清空", systemImage: "trash").font(.rj(12.5, weight: .semibold))
                }
                .buttonStyle(RJSubtleButtonStyle())
                .disabled(store.memory.facts.isEmpty)
                IconButton(symbol: "xmark", help: "关闭", iconSize: 12.5) { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            HairLine()

            if store.memory.facts.isEmpty {
                EmptyHint(symbol: "brain", title: "还没有记住任何事",
                          subtitle: "点设置里的「立即更新」，让小迹读一遍你的日记")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(grouped, id: \.0.rawValue) { cat, list in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.symbol).font(.rj(11))
                                    Text(cat.label).font(.rj(12, weight: .semibold))
                                    Text("\(list.count)").font(.rj(11)).foregroundStyle(.tertiary)
                                }
                                .foregroundStyle(Color.rjAccent)
                                VStack(spacing: 4) {
                                    ForEach(list) { f in row(f) }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            HairLine()

            // 手动补一条：模型抽不到的，自己写最准
            HStack(spacing: 8) {
                Picker("", selection: $category) {
                    ForEach(MemoryCategory.allCases) { c in Text(c.label).tag(c) }
                }
                .labelsHidden()
                .frame(width: 110)
                TextField("自己补一条，例如「对芒果过敏」", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.rj(12.5))
                    .onSubmit(add)
                Button {
                    add()
                } label: {
                    Label("添加", systemImage: "plus").font(.rj(12.5, weight: .semibold))
                }
                .buttonStyle(RJSubtleButtonStyle())
                .disabled(draft.trimmed.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 560, height: 560)
        .confirmationDialog("清空全部记忆？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { store.memory.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("小迹会忘了从日记里学到的一切，之后可以重新更新。日记本身不受影响。")
        }
    }

    private func add() {
        let text = draft.trimmed
        guard !text.isEmpty else { return }
        store.memory.add(category: category, text: text)
        draft = ""
    }

    private func row(_ f: MemoryFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(f.text)
                .font(.rj(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(f.source.isEmpty ? "—" : f.source)
                .font(.rj(10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            IconButton(symbol: "xmark", help: "忘掉这条", size: 24, iconSize: 10) {
                store.memory.remove(f.id)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rjPanel()
    }
}
