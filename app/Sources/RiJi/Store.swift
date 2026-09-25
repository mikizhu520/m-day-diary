import Foundation
import SwiftUI
import CryptoKit
import Security

// MARK: - 配置文件结构

struct ConfigFile: Codable {
    var settings: AppSettings
    var security: SecurityRecord
    var journals: [Journal]
}

/// 加密开启时，正文里保存的完整负载
/// 注意：新增字段一律用可选类型，否则旧日记会解码失败
struct EncryptedPayload: Codable {
    var title: String
    var body: String
    var tags: [String]
    var mood: String
    var weather: WeatherInfo?
    /// 写作城市。声明成 Optional 是为了让**旧日记**仍能解开 ——
    /// 字段缺失时 Codable 会给出 nil，而不是整段解码失败。
    var city: String?
}

// MARK: - 数据仓库

@MainActor
final class Store: ObservableObject {

    // MARK: 发布状态

    @Published var entries: [Entry] = []
    @Published var journals: [Journal] = []
    /// 正在编辑的日记本草稿（新建或改名 / 换图标）。非 nil 就弹编辑窗口。
    @Published var journalDraft: JournalDraft?
    /// 正在填的九宫格。非 nil 就弹九宫格面板。
    @Published var gridDraft: GridDraft?
    @Published var settings: AppSettings
    @Published var security: SecurityRecord = SecurityRecord()
    @Published var isLocked: Bool = true
    @Published var hasLoaded: Bool = false
    @Published var toast: String?
    @Published var aiKeyPresent: Bool = false
    /// 正在向天气服务取数据
    @Published var weatherBusy: Bool = false
    /// 取天气失败时的提示
    @Published var weatherError: String?
    @Published var biometricEnabled: Bool = UserDefaults.standard.bool(forKey: "rj.biometricEnabled")
    /// 指纹解锁失败时的说明文案（由锁屏读取展示）
    @Published var biometricIssue: String?
    /// 是否弹出「要不要开启指纹解锁」的询问
    @Published var showBiometricOffer = false
    /// 询问期间暂存刚输入的密码（仅内存，用于一键开启）
    private var biometricOfferPassword: String?

    // MARK: 运行时状态

    private(set) var masterKey: SymmetricKey?
    private(set) var rootURL: URL
    private var supportURL: URL
    private var lockTimer: Timer?
    private var lastActivity = Date()
    private var saveWorkItem: DispatchWorkItem?
    private var cachedWeather: WeatherInfo?
    private var cachedWeatherDay = ""

    var dataURL: URL { rootURL }
    var journalsDir: URL { rootURL.appendingPathComponent("journals", isDirectory: true) }
    var attachmentsDir: URL { rootURL.appendingPathComponent("attachments", isDirectory: true) }

    // MARK: 初始化

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("日迹", isDirectory: true)
        supportURL = support
        let defaultData = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("日迹日记", isDirectory: true)
        rootURL = defaultData

        if let data = try? Data(contentsOf: support.appendingPathComponent("config.json")),
           let cfg = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            settings = cfg.settings
            security = cfg.security
            journals = cfg.journals
            rootURL = URL(fileURLWithPath: cfg.settings.dataPath)
        } else {
            settings = AppSettings(dataPath: defaultData.path)
            journals = Journal.defaults
            settings.defaultJournalId = journals.first?.id ?? ""
        }
        aiKeyPresent = (AIKeyStore.read()?.nilIfEmpty != nil)
        isLocked = security.hasPassword
    }

    // MARK: - 启动加载

    /// 仅用于界面截图 / 预览：切到临时目录 + 示例数据，绝不触碰用户的真实数据
    func enterSnapshotDemo() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rj-snapshot-demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        rootURL = tmp
        supportURL = tmp
        journals = Journal.defaults
        settings.dataPath = tmp.path
        settings.defaultJournalId = journals.first?.id ?? ""
        settings.encryptionEnabled = false
        settings.isConfigured = true
        settings.appearance = "light"
        // 造一个「已设密码」的状态，好把安全页的完整界面也截出来（不会真的能解锁）
        security.hasPassword = true
        security.salt = Data(repeating: 7, count: 16).base64EncodedString()
        security.verifier = Data(repeating: 9, count: 32).base64EncodedString()
        security.keyCheck = ""
        biometricEnabled = false
        entries = DemoContent.entries(journals: journals)
        isLocked = false
        hasLoaded = true
    }

    func bootstrap() {
        try? FileManager.default.createDirectory(at: journalsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        if journals.isEmpty { journals = Journal.defaults }
        if settings.defaultJournalId.isEmpty { settings.defaultJournalId = journals.first?.id ?? "" }
        saveConfig()

        if !security.hasPassword {
            isLocked = false
            loadEntries()
            Task { await backfillTodayWeather() }
        } else {
            isLocked = true
        }
        hasLoaded = true
        startLockTimer()
    }

    // MARK: - 密码 / 锁

    func setPassword(_ password: String) {
        let salt = Crypto.makeSalt()
        let iterations = security.iterations
        security.salt = salt.base64EncodedString()
        security.verifier = Crypto.verifier(password: password, salt: salt, iterations: iterations)
        security.hasPassword = true
        if settings.encryptionEnabled {
            masterKey = Crypto.key(password: password, salt: salt, iterations: iterations)
            security.keyCheck = Crypto.encrypt("ok", key: masterKey!) ?? ""
        }
        saveConfig()
        isLocked = false
        loadEntries()
    }

    func removePassword() {
        security = SecurityRecord()
        disableBiometric()
        saveConfig()
        isLocked = false
    }

    func changePassword(from old: String, to new: String) -> Bool {
        guard verify(old) else { return false }
        let salt = Crypto.makeSalt()
        let iterations = security.iterations
        let newKey = Crypto.key(password: new, salt: salt, iterations: iterations)
        security.salt = salt.base64EncodedString()
        security.verifier = Crypto.verifier(password: new, salt: salt, iterations: iterations)
        masterKey = newKey
        if settings.encryptionEnabled {
            security.keyCheck = Crypto.encrypt("ok", key: newKey) ?? ""
            for e in entries { writeFile(for: e) }   // 用新密钥重新写盘
        }
        if biometricEnabled { _ = Biometric.save(new) }   // 同步触控 ID 用的密码
        saveConfig()
        return true
    }

    func verify(_ password: String) -> Bool {
        guard security.hasPassword, let salt = Data(base64Encoded: security.salt) else { return false }
        let v = Crypto.verifier(password: password, salt: salt, iterations: security.iterations)
        return Crypto.constantTimeEquals(v, security.verifier)
    }

    @discardableResult
    func unlock(password: String) -> Bool {
        guard verify(password) else { return false }
        guard let salt = Data(base64Encoded: security.salt) else { return false }
        masterKey = Crypto.key(password: password, salt: salt, iterations: security.iterations)
        isLocked = false
        touch()
        rearmBiometricIfNeeded(password: password)
        loadEntries()
        Task { await backfillTodayWeather() }
        return true
    }

    /// 自愈：开启了指纹解锁、但保险库里已经没有那个密码时，用刚验证过的密码补存一次。
    ///
    /// 什么情况下会丢？早期版本把密码存在系统钥匙串里，而 ad-hoc 签名的 App 每次重建
    /// 都会让旧条目 ACL 失效（详见 Vault.swift 顶部）。这次改版把存储搬进了本机保险库，
    /// 老用户第一次用密码解锁时就会走到这里，指纹解锁随即恢复，不用手动去设置里重开一遍。
    private func rearmBiometricIfNeeded(password: String) {
        guard biometricEnabled, Biometric.isAvailable else { return }
        guard Biometric.readPassword() != password else { return }
        if Biometric.save(password) {
            biometricIssue = nil
        }
    }

    func lock() {
        guard security.hasPassword else { return }
        masterKey = nil
        isLocked = true
        toast = "已锁定"
    }

    func touch() { lastActivity = Date() }

    // MARK: - 触控 ID / 面容 ID 解锁

    var biometricAvailable: Bool { Biometric.isAvailable }
    var biometryName: String { Biometric.info.name }
    var biometrySymbol: String { Biometric.info.symbol }

    /// 开启指纹解锁：校验密码后把它存进本机保险库
    @discardableResult
    func enableBiometric(password: String) -> Bool {
        guard security.hasPassword else { toast = "请先设置打开密码"; return false }
        guard verify(password) else { return false }
        guard Biometric.save(password) else { toast = "写入本机保险库失败"; return false }
        setBiometric(true)
        return true
    }

    func disableBiometric() { setBiometric(false) }

    /// 用密码解锁成功后调用：如果本机支持指纹却还没开，问一下要不要开
    func offerBiometricIfNeeded(password: String) {
        guard security.hasPassword, Biometric.isAvailable, !biometricEnabled, !password.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: "rj.biometricOfferDecided") else { return }
        biometricOfferPassword = password
        showBiometricOffer = true
    }

    func confirmBiometricOffer() {
        defer {
            showBiometricOffer = false
            biometricOfferPassword = nil
        }
        guard let pwd = biometricOfferPassword else { return }
        UserDefaults.standard.set(true, forKey: "rj.biometricOfferDecided")
        if enableBiometric(password: pwd) {
            toast = "已开启\(biometryName)解锁，下次锁屏按一下指纹就行"
        } else {
            toast = "开启失败，可到「设置 → 安全」里手动开启"
        }
    }

    func dismissBiometricOffer() {
        showBiometricOffer = false
        biometricOfferPassword = nil
        UserDefaults.standard.set(true, forKey: "rj.biometricOfferDecided")
    }

    private func setBiometric(_ on: Bool) {
        if !on { Biometric.clear() }
        UserDefaults.standard.set(on, forKey: "rj.biometricEnabled")
        biometricEnabled = on
    }

    /// 指纹解锁：验证生物识别 → 取回密码 → 走正常解锁
    @discardableResult
    func unlockWithBiometric() async -> Bool {
        guard security.hasPassword, biometricEnabled, Biometric.isAvailable else { return false }
        biometricIssue = nil
        guard await Biometric.verify(reason: "解锁你的日记") else { return false }

        var pwd = Biometric.readPassword()

        // 迁移兜底：保险库还没存过密码（早期版本把密码存在系统钥匙串里）。
        // 趁用户刚点过指纹、由她主动触发，在后台试着取回一次 —— 不放在启动路径上，
        // 所以即使系统弹授权框也不会卡住 App（读取本身带 25 秒超时兜底）。
        if pwd == nil,
           let item = LegacyKeychain.items.first(where: { $0.label == "指纹解锁密码" }),
           let recovered = await Task.detached(priority: .userInitiated, operation: {
               LegacyKeychain.read(item, timeout: 25)
           }).value,
           !recovered.isEmpty, verify(recovered) {
            Biometric.save(recovered)
            pwd = recovered
        }

        guard let pwd, verify(pwd) else {
            biometricIssue = "\(biometryName)解锁已失效，请先输一次密码，之后就会自动恢复。"
            return false
        }
        return unlock(password: pwd)
    }

    private func startLockTimer() {
        lockTimer?.invalidate()
        lockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isLocked, self.security.hasPassword else { return }
                let minutes = self.settings.autoLockMinutes
                guard minutes > 0 else { return }
                if Date().timeIntervalSince(self.lastActivity) > Double(minutes) * 60 {
                    self.lock()
                }
            }
        }
    }

    // MARK: - 开关加密

    func setEncryption(_ enabled: Bool) -> Bool {
        guard security.hasPassword, let key = masterKey else {
            toast = "请先设置密码"
            return false
        }
        settings.encryptionEnabled = enabled
        security.keyCheck = Crypto.encrypt("ok", key: key) ?? ""
        for e in entries { writeFile(for: e) }
        saveConfig()
        toast = enabled ? "已开启全库加密" : "已关闭加密，恢复为明文 Markdown"
        return true
    }

    // MARK: - 天气

    /// 取当前天气。同一天内复用缓存，避免每篇日记都发一次请求。
    func currentWeather(force: Bool = false) async -> WeatherInfo? {
        let today = Fmt.day.string(from: Date())
        if !force, let cached = cachedWeather, cachedWeatherDay == today {
            return cached
        }
        weatherBusy = true
        defer { weatherBusy = false }
        do {
            var w = try await WeatherService.fetch(city: settings.weatherCity)
            w.city = w.city.isEmpty ? settings.weatherCity : w.city
            cachedWeather = w
            cachedWeatherDay = today
            weatherError = nil
            return w
        } catch {
            let msg = (error as? WeatherError)?.message ?? error.localizedDescription
            weatherError = msg
            return nil
        }
    }

    /// 手动指定（或清除）某篇日记的天气
    func setWeather(_ kind: WeatherKind?, on entry: Entry) {
        guard var e = entries.first(where: { $0.id == entry.id }) else { return }
        if let kind {
            e.weather = WeatherInfo(kind: kind,
                                    temp: kind == e.weather?.kind ? e.weather?.temp : nil,
                                    city: settings.weatherCity,
                                    isManual: true)
        } else {
            e.weather = nil
        }
        update(e, immediate: true)
    }

    /// 用当前真实天气填到某篇日记上（手动点「获取当前天气」）
    func fillWeatherWithCurrent(_ entry: Entry) async {
        guard let w = await currentWeather(force: true) else {
            show("天气获取失败：\(weatherError ?? "未知原因")")
            return
        }
        guard var e = entries.first(where: { $0.id == entry.id }) else { return }
        e.weather = w
        applyCity(w, to: &e)
        update(e, immediate: true)
        show("已记录天气：\(w.summary)")
    }

    /// 天气接口返回的城市名比设置里那一行更准（它会把「北京」规范化成实际城市），
    /// 所以每次抓到天气都顺手把城市补上。
    private func applyCity(_ w: WeatherInfo, to e: inout Entry) {
        let c = w.city.trimmed
        if !c.isEmpty { e.city = c }
    }

    /// 新建日记时自动补天气（失败就静静留着，不打扰写作）
    private func autoFillWeather(entryId: String) async {
        guard settings.weatherAuto else { return }
        guard let w = await currentWeather() else { return }
        guard var e = entries.first(where: { $0.id == entryId }) else { return }
        guard e.weather == nil else { return }
        e.weather = w
        applyCity(w, to: &e)
        update(e, immediate: true)
    }

    /// 给今天所有还没记天气的日记补上（启动 / 解锁时调用一次）
    func backfillTodayWeather() async {
        guard settings.weatherAuto else { return }
        let missing = entries.filter {
            Calendar.current.isDateInToday($0.createdAt) && $0.weather == nil
        }
        guard !missing.isEmpty else { return }
        guard let w = await currentWeather() else { return }
        for item in missing {
            guard var e = entries.first(where: { $0.id == item.id }), e.weather == nil else { continue }
            e.weather = w
            applyCity(w, to: &e)
            update(e, immediate: true)
        }
    }

    /// 手动挑天气时可选的列表
    var weatherChoices: [(WeatherKind, String)] {
        WeatherKind.pickable.map { ($0, $0.name) }
    }
    // MARK: - 读写文件

    private func path(for entry: Entry) -> URL {
        rootURL.appendingPathComponent(entry.relPath)
    }

    func makeRelPath(for entry: Entry) -> String {
        let day = Fmt.day.string(from: entry.createdAt)
        let t = DateFormatter()
        t.dateFormat = "HHmmss"
        let short = String(entry.id.replacingOccurrences(of: "-", with: "").prefix(6))
        return "journals/\(entry.journalId)/\(day)/\(t.string(from: entry.createdAt))-\(short).md"
    }

    // MARK: 序列化

    func serialize(_ entry: Entry) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(entry.id)")
        lines.append("journal: \(entry.journalId)")
        lines.append("created: \(Fmt.iso.string(from: entry.createdAt))")
        lines.append("updated: \(Fmt.iso.string(from: entry.updatedAt))")

        if settings.encryptionEnabled, let key = masterKey {
            if let payload = try? JSONEncoder().encode(EncryptedPayload(
                title: entry.title, body: entry.body, tags: entry.tags,
                mood: entry.mood, weather: entry.weather,
                city: entry.city)),
               let plain = String(data: payload, encoding: .utf8),
               let cipher = Crypto.encrypt(plain, key: key) {
                lines.append("encrypted: true")
                lines.append("---")
                lines.append("")
                lines.append(cipher)
                return lines.joined(separator: "\n") + "\n"
            }
        }
        lines.append("title: \(entry.title.replacingOccurrences(of: "\n", with: " "))")
        lines.append("tags: \(entry.tags.joined(separator: ", "))")
        lines.append("mood: \(entry.mood)")
        if let w = entry.weather { lines.append("weather: \(w.frontMatterValue)") }
        if !entry.city.trimmed.isEmpty { lines.append("city: \(entry.city.replacingOccurrences(of: "\n", with: " "))") }
        lines.append("---")
        lines.append("")
        lines.append(entry.body)
        return lines.joined(separator: "\n") + "\n"
    }

    func parse(_ text: String, relPath: String) -> Entry? {
        var entry = Entry()
        entry.relPath = relPath
        var body = text
        if text.hasPrefix("---") {
            let parts = text.components(separatedBy: "\n---")
            if parts.count >= 2 {
                let head = parts[0].replacingOccurrences(of: "---", with: "", options: [.anchored])
                let rest = parts.dropFirst().joined(separator: "\n---")
                body = rest.hasPrefix("\n") ? String(rest.dropFirst()) : rest
                for line in head.split(separator: "\n") {
                    let l = String(line)
                    guard let idx = l.firstIndex(of: ":") else { continue }
                    let key = String(l[l.startIndex..<idx]).trimmed
                    let value = String(l[l.index(after: idx)...]).trimmed
                    switch key {
                    case "id": entry.id = value
                    case "journal": entry.journalId = value
                    case "created": if let d = Fmt.iso.date(from: value) { entry.createdAt = d }
                    case "updated": if let d = Fmt.iso.date(from: value) { entry.updatedAt = d }
                    case "title": entry.title = value
                    case "tags":
                        entry.tags = value
                            .replacingOccurrences(of: "[", with: "")
                            .replacingOccurrences(of: "]", with: "")
                            .split(separator: ",")
                            .map { $0.trimmed }
                            .filter { !$0.isEmpty }
                    case "mood": entry.mood = value
                    // 旧版本写过 favorite 行。收藏功能已经去掉，这里不再读它 ——
                    // 未识别的键会走 default 静默忽略，老日记照常能打开。
                    case "weather": entry.weather = WeatherInfo(frontMatter: value)
                    case "city": entry.city = value
                    case "encrypted": entry.encrypted = (value == "true")
                    default: break
                    }
                }
            }
        }

        if entry.encrypted {
            let payload = body.trimmed
            guard let key = masterKey else {
                entry.title = "🔒 已加密"
                entry.body = ""
                return entry
            }
            guard let plain = Crypto.decrypt(payload, key: key),
                  let data = plain.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(EncryptedPayload.self, from: data) else {
                entry.title = "⚠️ 解密失败"
                entry.body = ""
                return entry
            }
            entry.title = decoded.title
            entry.body = decoded.body
            entry.tags = decoded.tags
            entry.mood = decoded.mood
            entry.weather = decoded.weather
            entry.city = decoded.city ?? ""
        } else {
            entry.body = body.trimmed
        }
        if entry.journalId.isEmpty { entry.journalId = journals.first?.id ?? "" }
        return entry
    }

    @discardableResult
    private func writeFile(for entry: Entry) -> Bool {
        var e = entry
        if e.relPath.isEmpty { e.relPath = makeRelPath(for: e) }
        let url = path(for: e)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try serialize(e).write(to: url, atomically: true, encoding: .utf8)
            if let idx = entries.firstIndex(where: { $0.id == e.id }) { entries[idx].relPath = e.relPath }
            return true
        } catch {
            toast = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 加载全部条目

    func loadEntries() {
        guard let enumerator = FileManager.default.enumerator(at: journalsDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            entries = []
            return
        }
        var loaded: [Entry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            if let e = parse(text, relPath: rel) { loaded.append(e) }
        }
        entries = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 条目操作

    @discardableResult
    func createEntry(journalId: String? = nil, date: Date = Date(), body: String = "") -> Entry {
        let jid = journalId ?? defaultJournalId()
        var e = Entry(journalId: jid, createdAt: date, updatedAt: date)
        e.body = body
        // 先把设置里的城市落上，天气抓回来会用真实城市覆盖它
        e.city = settings.weatherCity.trimmed
        e.relPath = makeRelPath(for: e)
        entries.insert(e, at: 0)
        writeFile(for: e)
        // 今天的日记自动记下当天天气
        if settings.weatherAuto, Calendar.current.isDateInToday(date) {
            let id = e.id
            Task { await autoFillWeather(entryId: id) }
        }
        return e
    }

    func defaultJournalId() -> String {
        if !settings.defaultJournalId.isEmpty { return settings.defaultJournalId }
        return journals.first?.id ?? "default"
    }

    func update(_ entry: Entry, immediate: Bool = false) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var e = entry
        e.updatedAt = Date()
        if e.relPath.isEmpty { e.relPath = makeRelPath(for: e) }
        entries[idx] = e
        if immediate {
            saveWorkItem?.cancel()
            writeFile(for: e)
        } else {
            scheduleWrite(e)
        }
    }

    private func scheduleWrite(_ entry: Entry) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.writeFile(for: entry) }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (entry.body.isEmpty ? 0.05 : 0.7), execute: item)
    }

    func flush() {
        saveWorkItem?.cancel()
        for e in entries { writeFile(for: e) }
    }

    func delete(_ entry: Entry) {
        let url = path(for: entry)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        entries.removeAll { $0.id == entry.id }
        toast = "已移到废纸篓"
    }

    func move(_ entry: Entry, to journalId: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let old = path(for: entries[idx])
        entries[idx].journalId = journalId
        entries[idx].relPath = makeRelPath(for: entries[idx])
        writeFile(for: entries[idx])
        try? FileManager.default.removeItem(at: old)
    }

    // MARK: - 日记本

    /// 点「＋」新建：先开草稿给用户命名 / 挑图标，确认后才真正落地
    func beginNewJournal() {
        journalDraft = JournalDraft.new()
    }

    func beginEditJournal(_ journal: Journal) {
        journalDraft = JournalDraft.editing(journal)
    }

    /// 提交草稿。新建就追加到末尾并自动跳过去；编辑就原地更新（id 不变，
    /// 所以磁盘上的目录 journals/<id>/ 和已有日记都不受影响）。
    func commitJournalDraft(_ draft: JournalDraft) {
        let d = draft.sanitized()
        if d.isNew {
            let j = Journal(name: d.name, colorHex: d.colorHex, symbol: d.symbol)
            journals.append(j)
            saveConfig()
            objectWillChange.send()
            show("日记本「\(j.name)」已创建")
            // 让侧边栏切到新建的这一本
            NotificationCenter.default.post(name: .rjSelectJournal, object: j.id)
        } else if let idx = journals.firstIndex(where: { $0.id == d.id }) {
            journals[idx].name = d.name
            journals[idx].colorHex = d.colorHex
            journals[idx].symbol = d.symbol
            saveConfig()
            objectWillChange.send()
            show("已保存")
        }
        journalDraft = nil
    }

    func cancelJournalDraft() {
        journalDraft = nil
    }

    /// 改名字 / 换图标后的快捷入口（设置页之类的地方用得上）
    @discardableResult
    func renameJournal(_ id: String, to name: String) -> Bool {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, let idx = journals.firstIndex(where: { $0.id == id }) else { return false }
        journals[idx].name = trimmed
        saveConfig()
        return true
    }

    /// 拖动排序：把 `id` 挪到「原数组里的第 index 位」。
    ///
    /// index 传的是移动**之前**的位置语义（= 目标项的下标，或目标项下标 +1 表示插到它后面）。
    /// 真正的重排规则在 `JournalReorder.reorder` 里，那份是纯函数，有自检兜着。
    func moveJournal(_ id: String, toIndex index: Int) {
        guard let from = journals.firstIndex(where: { $0.id == id }) else { return }
        let list = JournalReorder.reorder(journals, movingIndex: from, toIndex: index)
        guard list.map(\.id) != journals.map(\.id) else { return }
        journals = list
        saveConfig()
    }

    func addJournal(name: String, colorHex: String, symbol: String) {
        journals.append(Journal(name: name, colorHex: colorHex, symbol: symbol))
        saveConfig()
        objectWillChange.send()
    }

    func updateJournal(_ journal: Journal) {
        if let idx = journals.firstIndex(where: { $0.id == journal.id }) {
            journals[idx] = journal
            saveConfig()
        }
    }

    func deleteJournal(_ journal: Journal) {
        guard journals.count > 1 else { toast = "至少保留一个日记本"; return }
        journals.removeAll { $0.id == journal.id }
        if settings.defaultJournalId == journal.id {
            settings.defaultJournalId = journals.first?.id ?? ""
        }
        saveConfig()
        show("日记本「\(journal.name)」已删除")
    }

    func journal(for id: String) -> Journal? { journals.first { $0.id == id } }

    /// 某个日记本下有多少篇日记
    func journalCount(_ id: String) -> Int {
        entries.reduce(0) { $0 + ($1.journalId == id ? 1 : 0) }
    }

    // MARK: - 九宫格模板

    /// 当前可用的模板。空列表时兜底给内置的，保证「九宫格」入口永远点得开。
    var gridTemplates: [GridTemplate] {
        settings.gridTemplates.isEmpty ? GridTemplate.builtIns : settings.gridTemplates
    }

    /// 用户自己加过的模板（用于决定要不要显示「恢复内置」）
    var hasCustomGridTemplates: Bool {
        settings.gridTemplates.contains { !$0.isBuiltIn }
    }

    func gridTemplate(id: String) -> GridTemplate? {
        gridTemplates.first { $0.id == id }
    }

    /// 存一张模板：id 已存在就替换，否则追加
    func saveGridTemplate(_ template: GridTemplate) {
        let t = template.normalized()
        var list = gridTemplates
        if let idx = list.firstIndex(where: { $0.id == t.id }) {
            list[idx] = t
        } else {
            list.append(t)
        }
        settings.gridTemplates = list
        saveConfig()
        objectWillChange.send()
    }

    func deleteGridTemplate(id: String) {
        settings.gridTemplates = gridTemplates.filter { $0.id != id }
        saveConfig()
        objectWillChange.send()
    }

    /// 恢复内置的三套。**用户自己加的不动** —— 只把内置那几条换回原厂内容，
    /// 顺带把被删掉的内置补回来。
    func resetGridTemplates() {
        var list = gridTemplates.filter { !$0.isBuiltIn }
        list.append(contentsOf: GridTemplate.builtIns)
        settings.gridTemplates = list
        saveConfig()
        show("内置模板已恢复")
    }

    // MARK: - 九宫格日记

    /// 打开九宫格面板。
    ///
    /// `entryId` 传了就表示「追加到这篇」（编辑器里的入口），
    /// 不传就是「填完生成一篇新日记」（侧边栏 / ⌘⇧N 的入口）。
    func beginGridJournal(entryId: String? = nil, templateId: String? = nil) {
        let jid: String? = entryId.flatMap { id in
            entries.first { $0.id == id }?.journalId
        }
        gridDraft = GridDraft(targetEntryId: entryId,
                              journalId: jid,
                              templateId: templateId ?? gridTemplates.first?.id ?? "")
    }

    func cancelGridDraft() { gridDraft = nil }

    // MARK: - 图片

    func importImage(data: Data, ext: String) -> String? {
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "img-\(stamp)-\(Crypto.randomHex(3)).\(ext)"
        let url = attachmentsDir.appendingPathComponent(name)
        do { try data.write(to: url) } catch { toast = "图片保存失败"; return nil }
        return name
    }

    func importImage(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.nilIfEmpty ?? "png"
        return importImage(data: data, ext: ext)
    }

    /// 把附件名解析成本地文件 URL
    func resolveAttachment(_ name: String, entry: Entry?) -> URL? {
        if name.hasPrefix("http") || name.hasPrefix("data:") { return nil }
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        // 1) 相对条目文件解析
        if let entry, !entry.relPath.isEmpty {
            let base = path(for: entry).deletingLastPathComponent()
            let candidate = base.appendingPathComponent(name).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        // 2) 直接用附件目录
        let direct = attachmentsDir.appendingPathComponent((name as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        return nil
    }

    /// 生成正文里使用的可移植相对路径（相对条目文件所在目录）
    func attachmentMarkdownPath(_ name: String, entry: Entry) -> String {
        let baseComps = path(for: entry).deletingLastPathComponent().standardizedFileURL.pathComponents
        let targetComps = attachmentsDir.appendingPathComponent(name).standardizedFileURL.pathComponents
        var idx = 0
        while idx < min(baseComps.count, targetComps.count) && baseComps[idx] == targetComps[idx] { idx += 1 }
        let ups = max(baseComps.count - idx, 0)
        let tail = targetComps.dropFirst(idx).joined(separator: "/")
        let prefix = Array(repeating: "..", count: ups).joined(separator: "/")
        return prefix.isEmpty ? tail : "\(prefix)/\(tail)"
    }

    // MARK: - 检索

    func entries(inJournal journalId: String?) -> [Entry] {
        guard let journalId else { return entries }
        return entries.filter { $0.journalId == journalId }
    }

    func entries(on day: Date) -> [Entry] {
        let key = Fmt.day.string(from: day)
        return entries.filter { $0.dayKey == key }.sorted { $0.createdAt < $1.createdAt }
    }

    func search(_ query: String) -> [Entry] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return entries.filter { e in
            e.title.lowercased().contains(q)
                || e.body.lowercased().contains(q)
                || e.tags.joined(separator: " ").lowercased().contains(q)
        }
    }

    var allTags: [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in entries { for t in e.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var dayKeys: Set<String> { Set(entries.map { $0.dayKey }) }

    var streak: Int {
        let cal = Calendar.current
        var count = 0
        var day = cal.startOfDay(for: Date())
        while dayKeys.contains(Fmt.day.string(from: day)) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    var onThisDayEntries: [Entry] {
        let cal = Calendar.current
        let now = Date()
        let m = cal.component(.month, from: now)
        let d = cal.component(.day, from: now)
        let y = cal.component(.year, from: now)
        return entries.filter { e in
            cal.component(.month, from: e.createdAt) == m
                && cal.component(.day, from: e.createdAt) == d
                && cal.component(.year, from: e.createdAt) != y
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func totalWords() -> Int { entries.reduce(0) { $0 + $1.wordCount } }

    // MARK: - 配置持久化

    func saveConfig() {
        settings.dataPath = rootURL.path
        let cfg = ConfigFile(settings: settings, security: security, journals: journals)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cfg) {
            try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try? data.write(to: supportURL.appendingPathComponent("config.json"), options: .atomic)
        }
    }

    // MARK: - 迁移数据目录

    func changeDataPath(to url: URL) {
        flush()
        rootURL = url
        settings.dataPath = url.path
        try? FileManager.default.createDirectory(at: journalsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        saveConfig()
        loadEntries()
    }

    // MARK: - 提示

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run { if self.toast == message { self.toast = nil } }
        }
    }
}

// MARK: - API Key 存储（本机保险库）
//
// 2026-09-25 从钥匙串改成 `Vault` —— 钥匙串在 ad-hoc 签名的本地 App 上会因
// 重建导致 ACL 失效、读取时弹授权框并卡死启动。详见 Vault.swift 顶部。
enum AIKeyStore {

    /// 保险库里存 API Key 用的名字
    private static var vaultName: String { Vault.Name.aiAPIKey }

    /// 老版本用过的明文兜底文件，只作为一次性兼容读取
    private static var legacyPlainURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("日迹", isDirectory: true)
            .appendingPathComponent("key.txt")
    }

    static func read() -> String? {
        if let v = Vault.read(vaultName), !v.trimmed.isEmpty { return v }
        // 兼容极早期版本：曾经把 key 明文写在文件里
        if let old = try? String(contentsOf: legacyPlainURL, encoding: .utf8), !old.trimmed.isEmpty {
            write(old)   // 顺手搬进保险库
            return old.trimmed
        }
        return nil
    }

    static func write(_ value: String) {
        let trimmed = value.trimmed
        if trimmed.isEmpty {
            Vault.delete(vaultName)
            try? FileManager.default.removeItem(at: legacyPlainURL)
            return
        }
        Vault.write(trimmed, name: vaultName)
        try? FileManager.default.removeItem(at: legacyPlainURL)
    }
}
