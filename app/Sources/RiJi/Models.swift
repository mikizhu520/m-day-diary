import Foundation
import SwiftUI

// MARK: - 应用身份
//
// 改的只是**给人看**的名字。下面这些内部标识保持原样，一旦改了会出事：
//   · Bundle ID `com.meiling.riji` —— 改了 UserDefaults 和保险库的归属就变了
//   · `~/Library/Application Support/日迹/` —— 配置和密钥都在这儿
//   · `~/Documents/日迹日记/` —— 你的全部日记在这儿
//
// 换句话说：换名字不会丢数据，换路径会。

enum AppInfo {
    /// 显示用的名字
    static let name = "MDay"
    static let tagline = "写给自己的日子"
    static let bundleID = "com.meiling.riji"

    /// 版本号。改这里的同时要改 build.sh 里的 Info.plist，
    /// 否则「关于」页显示的和系统看到的不一致。
    static let version = "0.0.5"

    /// 开发者
    static let author = "Miki Zhu"
    static let github = "https://github.com/mikizhu520/"
    static let email = "750856902@qq.com"
    /// 微信公众号
    static let wechat = "逍遥小斑鸠"

    /// 一句话说明这个 App 是干什么的（关于页 / 欢迎页共用）
    static let about = "本地优先的 Markdown 日记本。所有内容都以 .md 存在你自己的文件夹里，不上传任何服务器。"
}

// MARK: - 日记本（分类）

struct Journal: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String
    var symbol: String
    var createdAt: Date = Date()
    /// 单独上锁：点开这一本时要先过指纹 / 密码。
    ///
    /// 校验用的是**全局打开密码**（`SecurityRecord`），不另设一套 ——
    /// 否则「日记本密码」和「打开密码」两个熵源并存，忘一个就等于丢一半数据。
    /// 所以上锁的前提是设过打开密码；没设时界面会把开关禁掉。
    var locked: Bool = false

    static let defaults: [Journal] = [
        Journal(name: "日常", colorHex: "#E8623C", symbol: "sun.max.fill"),
        Journal(name: "工作", colorHex: "#3B7DD8", symbol: "briefcase.fill"),
        Journal(name: "健康", colorHex: "#2FA36B", symbol: "heart.fill"),
        Journal(name: "灵感", colorHex: "#9B5DE5", symbol: "lightbulb.fill")
    ]

    /// 图标缺失或为空时的兜底
    static let fallbackSymbol = "bookmark.fill"
    static let fallbackName = "未命名日记本"

    /// 新建 / 编辑日记本时可选的颜色。第一顺位是品牌暖赤陶。
    static let palette: [String] = [
        "#C85A37", "#D9526F", "#9B5DE5", "#5B6BE0", "#3B7DD8", "#2AA6A6",
        "#2FA36B", "#7FA83C", "#D9A02E", "#E07B39", "#8A6A55", "#6B7280"
    ]

    static func isValidHex(_ hex: String) -> Bool {
        let s = hex.trimmed
        guard s.hasPrefix("#"), s.count == 7 || s.count == 9 else { return false }
        return s.dropFirst().allSatisfy { $0.isHexDigit }
    }

    // MARK: 图标库

    /// 可选图标，按用途分组。全部是 SF Symbols，自检会逐个验存在性。
    struct IconGroup: Identifiable {
        var id: String { title }
        var title: String
        var symbols: [String]
    }

    static let iconGroups: [IconGroup] = [
        IconGroup(title: "记录", symbols: [
            "bookmark.fill", "book.closed.fill", "book.pages.fill", "square.and.pencil",
            "text.book.closed.fill", "highlighter", "paperclip", "tray.full.fill"
        ]),
        IconGroup(title: "工作", symbols: [
            "briefcase.fill", "building.2.fill", "chart.bar.xaxis", "checklist",
            "person.3.fill", "calendar", "doc.text.fill", "folder.fill"
        ]),
        IconGroup(title: "生活", symbols: [
            "sun.max.fill", "moon.stars.fill", "cup.and.saucer.fill", "fork.knife",
            "bed.double.fill", "cart.fill", "house.fill", "car.fill"
        ]),
        IconGroup(title: "健康", symbols: [
            "heart.fill", "figure.run", "heart.text.square.fill", "cross.case.fill",
            "leaf.fill", "dumbbell.fill", "pills.fill", "figure.walk"
        ]),
        IconGroup(title: "心情", symbols: [
            "face.smiling", "sparkles", "star.fill", "flame.fill",
            "wand.and.stars", "cloud.sun.fill", "hands.sparkles.fill", "camera.fill"
        ]),
        IconGroup(title: "学习", symbols: [
            "lightbulb.fill", "book.fill", "graduationcap.fill", "brain.head.profile",
            "pencil", "globe", "map.fill", "airplane"
        ])
    ]

    /// 拍平后的全部可选图标（自检与「随机挑一个」用）
    static var allSymbols: [String] { iconGroups.flatMap(\.symbols) }

    /// 当前是否用的是自定义图标（不在这套库里的旧图标）
    var isKnownSymbol: Bool { Journal.allSymbols.contains(symbol) }
}

// MARK: 日记本的容错解码
//
// 和 AppSettings 同一个道理：日记本列表也在 config.json 里，
// 整体解码失败会把密码一起丢掉。所以逐字段解，缺什么补什么。

extension Journal {
    enum CodingKeys: String, CodingKey {
        case id, name, colorHex, symbol, createdAt, locked
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
        name = rawName.isEmpty ? Journal.fallbackName : rawName

        let hex = value(.colorHex, RJ.accentDefault)
        colorHex = Journal.isValidHex(hex) ? hex : RJ.accentDefault

        let sym = value(.symbol, Journal.fallbackSymbol).trimmed
        symbol = sym.isEmpty ? Journal.fallbackSymbol : sym

        createdAt = value(.createdAt, Date())
        // 旧 config.json 里没有这一项 → 默认不上锁（等于保持老行为）
        locked = value(.locked, false)
    }
}

// MARK: - 日记本排序
//
// 拖拽落点的判断和数组重排都抽成纯函数：UI 那边只管接事件，
// 规则本身能被自检覆盖（拖到行的上半插前面、下半插后面）。

enum JournalReorder {

    /// 指针落在这一行的下半边 → 插到它后面。
    /// 正好压在中线上按「后面」算（一半对一半，靠后更符合直觉）。
    static func dropsBelow(cursorY: CGFloat, rowHeight: CGFloat) -> Bool {
        cursorY >= max(rowHeight, 1) / 2
    }

    /// 把第 `from` 个元素挪到 `toIndex`。
    ///
    /// `toIndex` 用的是**移动之前**的位置语义：目标项的下标，
    /// 或目标项下标 +1（表示插到它后面）。所以内部要先把自己摘掉再修正偏移。
    static func reorder<T>(_ list: [T], movingIndex from: Int, toIndex index: Int) -> [T] {
        guard list.indices.contains(from) else { return list }
        var out = list
        let item = out.remove(at: from)
        var to = index
        if from < to { to -= 1 }
        to = max(0, min(to, out.count))
        out.insert(item, at: to)
        return out
    }
}

// MARK: - 日记本编辑草稿

/// 「新建 / 编辑日记本」弹窗里的临时状态。
/// 单独拿出来是为了让弹窗可以「取消不落地」——改到一半按 Esc 不该改到真实数据。
struct JournalDraft: Identifiable, Equatable {
    /// 编辑时是被编辑日记本的 id；新建时是空串
    var id: String = ""
    var name: String = ""
    var colorHex: String = RJ.accentDefault
    var symbol: String = Journal.fallbackSymbol
    /// 是否给这一本单独上锁
    var locked: Bool = false

    var isNew: Bool { id.isEmpty }

    var title: String { isNew ? "新建日记本" : "编辑日记本" }

    /// 落盘前统一收拾一遍：名字去空格，颜色和图标都要合法
    func sanitized() -> JournalDraft {
        var d = self
        d.name = name.trimmed
        if d.name.isEmpty { d.name = Journal.fallbackName }
        if !Journal.isValidHex(d.colorHex) { d.colorHex = RJ.accentDefault }
        if d.symbol.trimmed.isEmpty { d.symbol = Journal.fallbackSymbol }
        return d
    }

    /// 名字是否可保存（空名不给存，免得侧边栏冒出一堆「未命名」）
    var canSave: Bool { !name.trimmed.isEmpty }

    static func new() -> JournalDraft {
        JournalDraft(name: "", colorHex: Journal.palette.randomElement() ?? RJ.accentDefault,
                     symbol: Journal.fallbackSymbol)
    }

    static func editing(_ j: Journal) -> JournalDraft {
        JournalDraft(id: j.id, name: j.name, colorHex: j.colorHex, symbol: j.symbol,
                     locked: j.locked)
    }
}

// MARK: - 日记本解锁请求
//
// 侧边栏点到一本锁着的日记本时，就往 `Store.journalGate` 里塞一个这个，
// 根视图看到非 nil 就弹解锁面板。做成独立结构体是为了能用 `.sheet(item:)` ——
// 直接存 String 没法让 SwiftUI 判断「内容变了要重建」。

struct JournalGate: Identifiable, Equatable {
    var id: String
}

// MARK: - 日记条目

struct Entry: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var journalId: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var title: String = ""
    var body: String = ""
    var tags: [String] = []
    var mood: String = ""
    /// 当天天气，可自动抓取也可手动指定
    var weather: WeatherInfo?
    /// 写这篇时所在的城市。新建时先按设置里的城市落一个，
    /// 天气接口拿回真实城市后再覆盖 —— 所以它既是「写作地点」也是天气的落点记录。
    var city: String = ""
    var encrypted: Bool = false
    /// 这一篇解密失败了（密文还在盘上，只是钥匙不对 / 文件坏了）。
    /// 只是内存标记，不落盘。有这个标记的条目**绝不写盘** ——
    /// 否则换密码时的重加密扫会拿空内容把原文覆盖掉，那就真找不回来了。
    var decryptFailed: Bool = false
    /// 相对于数据根目录的路径，例如 journals/<journalId>/2026-09-25/160412-a1b2.md
    var relPath: String = ""

    // MARK: 展示

    var displayTitle: String {
        let t = title.trimmed
        if !t.isEmpty { return t }
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(line).trimmed
            if s.isEmpty { continue }
            if s.hasPrefix("```") || s.hasPrefix("---") || s.hasPrefix("|") { continue }
            s = s.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
            // 去掉行首的列表/引用标记
            s = s.replacingOccurrences(of: "^[\\-\\*\\+>]\\s*", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
            s = Entry.stripInline(s)
            if s.trimmed.isEmpty { continue }
            return String(s.trimmed.prefix(48))
        }
        return body.trimmed.isEmpty ? "空白日记" : "日记"
    }

    var excerpt: String {
        let stripped = Entry.stripInline(
            body
                .replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
                .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: [.regularExpression])
                .replacingOccurrences(of: "^[\\-\\*\\+>]\\s*", with: "", options: [.regularExpression])
        )
        let joined = stripped.split(separator: "\n")
            .map { $0.trimmed }
            .filter { !$0.isEmpty && !$0.hasPrefix("---") && !$0.hasPrefix("```") && !$0.hasPrefix("|") }
            .joined(separator: " ")
        return String(joined.prefix(160))
    }

    static func stripInline(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\*\\*([^*]*)\\*\\*", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "~~([^~]*)~~", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?<![\\*\\w])\\*([^*\\n]+)\\*(?![\\*\\w])", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        return out
    }

    /// 纯文本（给搜索 / AI 用）
    var plainText: String {
        Entry.stripInline(
            body
                .replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
                .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "^[\\-\\*\\+>]\\s*", with: "", options: .regularExpression)
        )
    }

    var wordCount: Int { Entry.countWords(body) }

    /// 正文里写的 `#标签`。
    ///
    /// 用户要求「在内容里直接写 # 就自然识别为标签」—— 顶部那行手动加标签的
    /// 输入框已经去掉了，标签从此只有一个来源：正文。
    var inlineTags: [String] { Entry.tagsIn(body) }

    /// 全部标签 = 正文里的 `#标签` + 历史上存过的 tags 字段（旧日记、AI 写入的）。
    /// 展示、筛选、搜索一律用它，`tags` 只是迁移兼容。
    var allTags: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in inlineTags + tags where seen.insert(t).inserted { out.append(t) }
        return out
    }

    /// 从正文里抽 `#标签`。
    ///
    /// 几条刻意的克制：
    /// - 只在行首或空白之后才算（所以 `https://x.com/#a` 里的 # 不算）
    /// - `# 标题` 这种「井号 + 空格」不算（后面必须紧跟非空白）
    /// - 代码围栏里的不算（写代码时随手一个 # 不该变成标签）
    /// - 碰到中文标点、括号、引号就断开
    static func tagsIn(_ text: String) -> [String] {
        guard text.contains("#") else { return [] }
        let pattern = "(?:^|[\\s（(【])#([^\\s#>，。！？；：、,.!?;:）)】》”\"'’]+)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }

        var out: [String] = []
        var seen = Set<String>()
        var inFence = false

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            let lineStr = line as NSString
            re.enumerateMatches(in: line, range: NSRange(location: 0, length: lineStr.length)) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                let tag = lineStr.substring(with: m.range(at: 1)).trimmed
                // 纯数字不算（`#1` 通常是编号），太长也不像标签
                guard !tag.isEmpty, tag.count <= 20,
                      tag.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil else { return }
                if seen.insert(tag).inserted { out.append(tag) }
            }
        }
        return out
    }

    static func countWords(_ text: String) -> Int {
        var cjk = 0
        var latin = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                cjk += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { latin += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return cjk + latin
    }

    /// 正文中引用的图片文件名
    var imageNames: [String] {
        guard let re = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(([^)]+)\\)") else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return re.matches(in: body, range: range).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: body) else { return nil }
            var name = String(body[r])
            if let idx = name.firstIndex(of: " ") { name = String(name[..<idx]) }
            return name.removingPercentEncoding ?? name
        }
    }

    var dayKey: String { Fmt.day.string(from: createdAt) }
    var timeText: String { Fmt.time.string(from: createdAt) }
    var isEmpty: Bool { body.trimmed.isEmpty && title.trimmed.isEmpty }
}

extension StringProtocol {
    var trimmed: String { String(self).trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}

// MARK: - 格式化工具

enum Fmt {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func friendlyDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        if cal.isDateInTomorrow(date) { return "明天" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days > 0 && days < 7 { return "\(days) 天前" }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEEE"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        return friendlyDay(date)
    }
}

// MARK: - 设置

struct AppSettings: Codable {
    var dataPath: String
    var autoLockMinutes: Int = 5            // 0 = 不自动锁
    var encryptionEnabled: Bool = false
    var aiBaseURL: String = "https://api.deepseek.com/v1"
    var aiModel: String = "deepseek-chat"
    var aiTemperature: Double = 0.7
    var aiContextScope: String = "current"   // current / today / week / all
    /// 小迹的人格（见 AIPersona.swift）。存 id，认不出来时退回「知心陪伴」
    var aiPersona: String = "companion"
    /// 小迹该怎么称呼使用者。留空就不特别提，让小迹自己拿捏。
    /// 写了的话会直接进系统提示词，小迹每次回答都这么叫。
    var userNickname: String = ""
    /// 自动从日记里沉淀记忆（见 MemoryStore.swift）。关掉就只保留手动改的部分。
    var aiAutoMemory: Bool = true
    var editorFontSize: Double = 15
    /// 写作区样式（行高 / 段间距 / 标题字号 / 装饰开关 / 版心宽度）。
    /// 用带默认值的结构体，旧配置缺这个字段时解码会退回默认规格。
    var mdStyle: MDStyle = .default
    var appearance: String = "system"        // system / light / dark
    var accentHex: String = "#E8623C"
    var showWordCount: Bool = true
    var defaultJournalId: String = ""
    var onThisDayEnabled: Bool = true
    var customPrompt: String = ""
    var isConfigured: Bool = false
    /// 天气城市（用于自动记录当天天气）
    var weatherCity: String = "北京"
    /// 新建今天的日记时自动记下天气
    var weatherAuto: Bool = true
    /// 九宫格日记的模板。内置三套随代码走，首次读配置时灌进去；
    /// 之后用户怎么改、怎么加，都以这份为准（可一键恢复内置）。
    var gridTemplates: [GridTemplate] = GridTemplate.builtIns
    /// 写作区的纸纹（见 Paper.swift）。存 rawValue，认不出来时退回纯白。
    var paperStyle: String = PaperStyle.plain.rawValue
    /// 生日，用来算星座运势。留空时界面上显示当天的太阳星座。
    var birthday: String = ""
    /// MBTI 类型，例如 INFJ。留空就不提 —— 类型是人自己认领的，
    /// 猜错了比不说更糟，所以这里只认用户选的那 16 个。
    var mbti: String = ""
}

// MARK: - 设置的容错解码
//
// 配置文件是「密码校验值 + 日记本列表 + 全部设置」放在一起的，
// 一旦解码失败就会被整体丢弃（等于丢密码）。所以这里逐字段解码，
// 缺失或类型不对就退回默认值，保证以后新增设置项不会弄坏旧配置。

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case dataPath, autoLockMinutes, encryptionEnabled, aiBaseURL, aiModel
        case aiTemperature, aiContextScope, aiPersona, editorFontSize, appearance, accentHex
        case userNickname, aiAutoMemory
        case showWordCount, defaultJournalId, onThisDayEnabled, customPrompt
        case isConfigured, weatherCity, weatherAuto
        case mdStyle, gridTemplates, paperStyle
        case birthday, mbti
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // try? 会把 T? 展平成 T?，所以这里只需要解一层
            guard let v = try? c.decodeIfPresent(T.self, forKey: key) else { return fallback }
            return v
        }
        let fallback = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("日迹日记", isDirectory: true).path

        let path = value(.dataPath, "")
        dataPath = path.isEmpty ? fallback : path
        autoLockMinutes = value(.autoLockMinutes, 5)
        encryptionEnabled = value(.encryptionEnabled, false)
        aiBaseURL = value(.aiBaseURL, "https://api.deepseek.com/v1")
        aiModel = value(.aiModel, "deepseek-chat")
        aiTemperature = value(.aiTemperature, 0.7)
        aiContextScope = value(.aiContextScope, "current")
        // 人格只存 id。万一以后砍掉某个人格，老配置的 id 认不出来就退回默认的那个
        aiPersona = AIPersonas.resolve(value(.aiPersona, AIPersonas.companion.id))
        userNickname = value(.userNickname, "")
        aiAutoMemory = value(.aiAutoMemory, true)
        editorFontSize = value(.editorFontSize, 15)
        appearance = value(.appearance, "system")
        accentHex = value(.accentHex, "#E8623C")
        showWordCount = value(.showWordCount, true)
        defaultJournalId = value(.defaultJournalId, "")
        onThisDayEnabled = value(.onThisDayEnabled, true)
        customPrompt = value(.customPrompt, "")
        isConfigured = value(.isConfigured, false)
        weatherCity = value(.weatherCity, "北京")
        weatherAuto = value(.weatherAuto, true)
        // 旧配置没有这个字段 → 退回默认规格；被手改坏的数值也拉回安全区间
        let s = value(.mdStyle, MDStyle.default)
        mdStyle = s.isSane ? s : .default
        // 九宫格模板：
        //   · 键不存在（旧配置）或用 `try?` 解失败 → 退回内置三套
        //   · 键存在且为空数组 → 尊重用户「都删了」的选择，保留空
        //   · 每条都过一遍规范化（缺格补齐、颜色非法拉回、空名字兜底）
        let grids = value(.gridTemplates, GridTemplate.builtIns)
        gridTemplates = grids.map { $0.normalized() }
        // 纸纹：认不出来的值退回纯白，不至于铺出一片奇怪的颜色
        paperStyle = PaperStyle.from(value(.paperStyle, PaperStyle.plain.rawValue)).rawValue
        // 生日：留着原文，解析失败只影响星座卡的显示，不影响别的
        birthday = value(.birthday, "")
        mbti = UserProfile.normalizeMBTI(value(.mbti, ""))
    }
}

// MARK: - 安全记录

struct SecurityRecord: Codable {
    var hasPassword: Bool = false
    var salt: String = ""
    var verifier: String = ""
    var iterations: Int = 120_000
    var keyCheck: String = ""     // 加密开启时用于校验密码

    init() {}

    // 这里绝对不能省：salt / verifier 是所有加密日记的命根子。
    // 用合成的 Codable，将来任何版本往这个结构里加一个字段，
    // 旧 config 解码就会整段失败 → 密码参数全丢 → 老日记永远解不开。
    // 逐字段 decodeIfPresent 之后，加字段、缺字段、坏字段都只是退回默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let v = try? c.decodeIfPresent(T.self, forKey: key) else { return fallback }
            return v
        }
        hasPassword = value(.hasPassword, false)
        salt = value(.salt, "")
        verifier = value(.verifier, "")
        iterations = value(.iterations, 120_000)
        keyCheck = value(.keyCheck, "")
    }
}

// MARK: - 心情

enum Moods {
    static let all = ["😄", "🙂", "😐", "😔", "😢", "😡", "😴", "🥳", "🤔", "😍", "😌", "🤯"]
}

// MARK: - 写作灵感

enum Prompts {
    static let all: [String] = [
        "今天最让你开心的一个小瞬间是什么？",
        "如果用一句话概括今天，你会怎么说？",
        "今天学到的一件小事，未来可能很有用。",
        "现在身体的感觉如何？累、轻松，还是紧绷？",
        "今天有没有哪件事，你其实想拒绝但答应了？",
        "写下一个你正在回避的问题，然后写下第一步。",
        "今天谁帮到了你？你想对他说什么？",
        "如果今天是电影的一帧，旁白会怎么写？",
        "最近重复出现的一个念头是什么？",
        "今天你为自己做的一件好事。",
        "有什么事情正在消耗你？能减掉哪一件？",
        "描述此刻窗外的样子。",
        "今天有没有一个瞬间，你觉得时间变慢了？",
        "把今天最烦的事写下来，然后写一句反驳它的话。",
        "明天你最想完成的一件事。"
    ]

    static func today() -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return all[day % all.count]
    }
}

// MARK: - 列表排序

/// 中栏列表的排序方式。选择存在 UserDefaults 里，重启后还是你挑的那一种。
enum EntrySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case updated
    case longest
    case title

    /// UserDefaults 键。列表和菜单共用同一个，改一处两边都跟着变。
    static let storageKey = "rj.entrySort"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .newest:  return "最新写的在前"
        case .oldest:  return "最早写的在前"
        case .updated: return "最近修改的在前"
        case .longest: return "字数最多的在前"
        case .title:   return "按标题排"
        }
    }

    var shortName: String {
        switch self {
        case .newest:  return "最新"
        case .oldest:  return "最早"
        case .updated: return "最近修改"
        case .longest: return "字数"
        case .title:   return "标题"
        }
    }

    var symbol: String {
        switch self {
        case .newest:  return "arrow.down"
        case .oldest:  return "arrow.up"
        case .updated: return "clock.arrow.circlepath"
        case .longest: return "text.alignleft"
        case .title:   return "textformat"
        }
    }

    /// 要不要按「天」分组显示。
    /// 按字数或标题排的时候，同一天的文章会散开 —— 再插一堆日期表头反而更乱。
    var groupsByDay: Bool {
        switch self {
        case .newest, .oldest, .updated: return true
        case .longest, .title: return false
        }
    }

    /// 排序本身。各分支都留了「同值时按时间倒序」的兜底，
    /// 否则字数相同的两篇在列表里会来回跳。
    func apply(_ list: [Entry]) -> [Entry] {
        switch self {
        case .newest:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return list.sorted { $0.createdAt < $1.createdAt }
        case .updated:
            return list.sorted {
                $0.updatedAt == $1.updatedAt ? $0.createdAt > $1.createdAt : $0.updatedAt > $1.updatedAt
            }
        case .longest:
            return list.sorted {
                $0.wordCount == $1.wordCount ? $0.createdAt > $1.createdAt : $0.wordCount > $1.wordCount
            }
        case .title:
            return list.sorted {
                let a = $0.displayTitle, b = $1.displayTitle
                if a == b { return $0.createdAt > $1.createdAt }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
        }
    }
}

// MARK: - 模板

struct EntryTemplate: Identifiable {
    var id: String { name }
    var name: String
    var symbol: String
    var body: String

    static let all: [EntryTemplate] = [
        EntryTemplate(name: "感恩三件事", symbol: "heart.text.square", body: """
        ## 今天感恩的三件事

        1.
        2.
        3.

        > 为什么是它们？
        """),
        EntryTemplate(name: "晨间日记", symbol: "sunrise", body: """
        ## 晨间

        **睡眠**：
        **身体状态**：

        ## 今天最重要的一件事

        ## 待办

        - [ ]
        - [ ]
        """),
        EntryTemplate(name: "晚间复盘", symbol: "moon.stars", body: """
        ## 今日复盘

        **做成了什么**：

        **卡在哪里**：

        **明天改进一件**：

        ## 情绪记录

        """),
        EntryTemplate(name: "读书笔记", symbol: "book", body: """
        ## 书名

        **作者**：
        **进度**：

        ## 摘抄

        >

        ## 我的想法

        """),
        EntryTemplate(name: "旅行记录", symbol: "airplane", body: """
        ## 地点

        ## 今天走了哪里

        ## 吃到的东西

        ## 想记住的画面

        """),
        EntryTemplate(name: "会议纪要", symbol: "person.3", body: """
        ## 会议主题

        **时间**：
        **参与人**：

        ## 结论

        ## 待办

        - [ ]
        """)
    ]
}
