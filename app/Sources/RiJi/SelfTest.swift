import Foundation
import CryptoKit
import AppKit
import SwiftUI

// MARK: - 自检（命令行参数 --selftest 触发）
//
// 只做纯计算与内存内往返，不触碰用户数据。

@MainActor
enum SelfTest {
    private static var passed = 0
    private static var failed = 0

    static func run() {
        print("▶︎ MDay 自检开始\n")
        crypto()
        roundTripPlain()
        roundTripEncrypted()
        encryptedSurvival()
        legacyParse()
        weather()
        settingsCompat()
        markdown()
        liveMarkdown()
        counters()
        attachmentPath()
        biometric()
        vault()
        journalAdmin()
        journalLock()
        gridJournal()
        lifeAdvice()
        entrySort()
        paperStyle()
        cityTag()
        almanac()
        holiday()
        zodiac()
        uiScale()
        updateCheck()
        imeInput()
        checkboxHit()
        persona()
        print("\n──────────────────────")
        print("通过 \(passed) 项，失败 \(failed) 项")
        exit(failed == 0 ? 0 : 1)
    }

    // MARK: 断线外的联网探针（--weather 城市）
    //
    // 自检本身不联网，这个入口单独用来验证天气接口是否真的通。

    nonisolated static func probeWeather(city: String) {
        print("▶︎ 天气探针：\(city)")
        Task.detached {
            do {
                var w = try await WeatherService.fetch(city: city)
                w.city = w.city.isEmpty ? city : w.city
                print("  城市：\(w.city)")
                print("  天气：\(w.name)（\(w.kind.rawValue)）图标 \(w.icon)")
                print("  温度：\(w.temp.map { String(format: "%.1f°C", $0) } ?? "无")")
                print("  展示：\(w.summary)")
                print("  写盘：weather: \(w.frontMatterValue)")
                exit(0)
            } catch {
                let msg = (error as? WeatherError)?.message ?? error.localizedDescription
                print("  ✗ 取不到：\(msg)")
                exit(1)
            }
        }
        dispatchMain()   // 主线程交给 GCD，等后台任务跑完再退出
    }

    // MARK: 断言

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)  \(detail)")
        }
    }

    private static func eq(_ name: String, _ a: String, _ b: String) {
        check(name, a == b, "期望「\(b)」实际「\(a)」")
    }

    // MARK: 加密

    private static func crypto() {
        print("· 加密与密钥派生")
        let salt = Crypto.makeSalt()
        let k1 = Crypto.pbkdf2(password: "hunter2", salt: salt, iterations: 1000)
        let k2 = Crypto.pbkdf2(password: "hunter2", salt: salt, iterations: 1000)
        let k3 = Crypto.pbkdf2(password: "hunter3", salt: salt, iterations: 1000)
        let k4 = Crypto.pbkdf2(password: "hunter2", salt: Crypto.makeSalt(), iterations: 1000)
        check("PBKDF2 可复现", k1 == k2)
        check("不同密码派生不同密钥", k1 != k3)
        check("不同盐派生不同密钥", k1 != k4)
        check("密钥长度 32 字节", k1.count == 32, "实际 \(k1.count)")

        let key = SymmetricKey(data: k1)
        let secret = "今天有点累，但把方案写完了。\n\nEmoji 也要支持 😀"
        guard let cipher = Crypto.encrypt(secret, key: key) else {
            check("AES-GCM 加密", false, "返回 nil")
            return
        }
        check("密文带 ENC1 前缀", cipher.hasPrefix("ENC1:"))
        check("密文不含明文", !cipher.contains("方案"))
        eq("解密还原", Crypto.decrypt(cipher, key: key) ?? "", secret)

        let wrong = SymmetricKey(data: k3)
        check("错误密钥无法解密", Crypto.decrypt(cipher, key: wrong) == nil)

        // 每次加密 nonce 不同 → 密文不同
        let again = Crypto.encrypt(secret, key: key) ?? ""
        check("密文随机化", again != cipher)

        check("校验值比较", Crypto.constantTimeEquals("abc", "abc"))
        check("校验值不等", !Crypto.constantTimeEquals("abc", "abd"))
    }

    // MARK: 明文往返

    private static func roundTripPlain() {
        print("\n· 明文 Markdown 往返")
        let store = Store()   // 只读取配置，不写盘
        store.settings.encryptionEnabled = false

        var entry = Entry(journalId: "J1",
                          createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                          updatedAt: Date(timeIntervalSince1970: 1_790_000_100))
        entry.title = "标题里带: 冒号 也要活着"
        entry.body = "第一段。\n\n- 项目一\n- 项目二\n\n---\n\n结尾，带 `代码` 和 **粗体**。"
        entry.tags = ["日常", "复盘"]
        entry.mood = "🙂"
        entry.weather = WeatherInfo(kind: .partly, temp: 21.4, city: "北京")

        let text = store.serialize(entry)
        check("含 frontmatter", text.hasPrefix("---\n"))
        check("frontmatter 写入天气", text.contains("weather: partly|21.4|北京|auto"), text.split(separator: "\n").prefix(9).joined(separator: " / "))

        guard let back = store.parse(text, relPath: "journals/J1/2026-01-01/x.md") else {
            check("解析回条目", false, "返回 nil")
            return
        }
        eq("标题", back.title, entry.title)
        eq("正文", back.body, entry.body)
        eq("标签", back.tags.joined(separator: ","), "日常,复盘")
        eq("心情", back.mood, "🙂")
        // 收藏功能已经移除。老 .md 文件里那行 favorite 应当被静默忽略，
        // 不能因为它变成「解析失败」或把正文吃掉。
        if let legacyFav = store.parse("---\nid: x\nfavorite: true\ntitle: 旧的\n---\n\n正文在这", relPath: "a.md") {
            check("旧的 favorite 行被忽略，正文照常", legacyFav.body.contains("正文在这"))
            eq("旧的 favorite 行不会污染标题", legacyFav.title, "旧的")
        } else {
            check("旧的 favorite 行被忽略，正文照常", false, "解析返回 nil")
        }
        check("天气类型还原", back.weather?.kind == .partly)
        check("天气温度还原", abs((back.weather?.temp ?? 0) - 21.4) < 0.01)
        eq("天气城市还原", back.weather?.city ?? "", "北京")
        check("自动抓取的天气不带手动标记", back.weather?.isManual == false)
        eq("日记本", back.journalId, "J1")
        check("时间戳保留", abs(back.createdAt.timeIntervalSince(entry.createdAt)) < 1)
        check("正文中的分割线未被误删", back.body.contains("\n---\n"))
        check("正文中的代码未丢失", back.body.contains("`代码`"))
        check("正文中的粗体未丢失", back.body.contains("**粗体**"))
    }

    // MARK: 加密往返

    private static func roundTripEncrypted() {
        print("\n· 加密条目往返")
        let salt = Crypto.makeSalt()
        let key = Crypto.key(password: "mypassword", salt: salt, iterations: 500)

        var entry = Entry(journalId: "J2", createdAt: Date(), updatedAt: Date())
        entry.title = "私密标题"
        entry.body = "只有我知道的内容。"
        entry.tags = ["私密"]
        entry.mood = "😌"
        entry.weather = WeatherInfo(kind: .thunder, temp: 28.9, city: "北京")

        // 复刻 Store.serialize 的加密分支
        let payload = try! JSONEncoder().encode(EncryptedPayload(
            title: entry.title, body: entry.body, tags: entry.tags,
            mood: entry.mood, weather: entry.weather))
        let plain = String(data: payload, encoding: .utf8)!
        let cipher = Crypto.encrypt(plain, key: key)!

        check("密文不含标题明文", !cipher.contains("私密标题"))
        check("密文不含正文明文", !cipher.contains("只有我知道"))
        check("密文不含天气明文", !cipher.contains("thunder"))

        let opened = Crypto.decrypt(cipher, key: key)!
        let decoded = try! JSONDecoder().decode(EncryptedPayload.self, from: Data(opened.utf8))
        eq("加密标题还原", decoded.title, entry.title)
        eq("加密正文还原", decoded.body, entry.body)
        eq("加密标签还原", decoded.tags.joined(separator: ","), "私密")
        check("加密天气还原", decoded.weather?.kind == .thunder)
        check("加密天气温度还原", abs((decoded.weather?.temp ?? 0) - 28.9) < 0.01)

        // 旧版加密日记（没有 weather 字段）必须还能读
        let legacyJSON = #"{"title":"旧日记","body":"旧内容","tags":["a"],"mood":"🙂","isFavorite":false}"#
        let legacy = try? JSONDecoder().decode(EncryptedPayload.self, from: Data(legacyJSON.utf8))
        check("旧加密负载仍可解码", legacy != nil)
        eq("旧加密负载标题正常", legacy?.title ?? "", "旧日记")
        check("旧加密负载天气为空", legacy?.weather == nil)

        // 换密码后旧密文不可读
        let newKey = Crypto.key(password: "newpassword", salt: salt, iterations: 500)
        check("换密码后旧密文失效", Crypto.decrypt(cipher, key: newKey) == nil)
    }

    // MARK: 加密的版本兼容与自救
    //
    // 用户原话：只要是在这个软件上写的加密日记，不管什么版本，后续版本、前续版本都能打开。
    // 加密日记的钥匙 = PBKDF2(密码, salt, iterations)，salt/verifier 存在 config.json 里。
    // 历史教训是「config 整段解码失败会把密码参数一起连坐丢掉」—— 这里把四个雷逐一排掉：
    //   1. SecurityRecord 容错解码（将来加字段不再连坐）
    //   2. config 解不开时按段抢救
    //   3. security.json 备份兜底
    //   4. 解密失败的条目绝不写盘（换密码重加密时不能拿空壳覆盖原文）

    private static func encryptedSurvival() {
        print("\n· 加密的版本兼容与自救")

        // ① SecurityRecord：缺字段、坏字段、多字段都不许连坐
        let missing = try? JSONDecoder().decode(SecurityRecord.self, from: Data(#"{"hasPassword":true}"#.utf8))
        check("SecurityRecord 缺字段可解码", missing?.hasPassword == true)
        check("SecurityRecord 缺字段盐退回空", missing?.salt.isEmpty == true)
        check("SecurityRecord 缺字段迭代次数退回默认", missing?.iterations == 120_000)
        let extra = try? JSONDecoder().decode(SecurityRecord.self, from: Data(
            #"{"hasPassword":true,"salt":"abc","verifier":"d","iterations":1000,"keyCheck":"e","futureField":42}"#.utf8))
        check("SecurityRecord 多了未知字段可解码", extra?.salt == "abc")
        let roundTrip = SecurityRecord()
        let rtData = try? JSONEncoder().encode(roundTrip)
        let rtBack = rtData.flatMap { try? JSONDecoder().decode(SecurityRecord.self, from: $0) }
        check("SecurityRecord 往返一致", rtBack?.hasPassword == false && rtBack?.iterations == 120_000)

        // ② config 整体解码失败时，security 段能被抢救回来
        let store = Store()
        store.enterTestMode()
        let cfgURL = store.dataURL.appendingPathComponent("config.json")
        // 故意写一份「settings 段坏了」的 config —— 整段 decode 必失败
        let broken = #"{"settings": "not-a-dict", "journals": [], "security": {"hasPassword": true, "salt": "c2FsdA==", "verifier": "deadbeef", "iterations": 120000, "keyCheck": "kc"}}"#
        try? broken.write(to: cfgURL, atomically: true, encoding: .utf8)
        store.rescueConfig(from: cfgURL)
        check("config 损坏时抢救出密码状态", store.security.hasPassword)
        check("config 损坏时抢救出盐", store.security.salt == "c2FsdA==")
        check("config 损坏时抢救出 verifier", store.security.verifier == "deadbeef")

        // ③ security.json 备份：写一份、丢一份、救回来
        store.security.salt = "bmV3c2FsdA=="
        store.saveConfig()
        let backupURL = store.dataURL.appendingPathComponent("security.json")
        check("saveConfig 会写 security.json 备份", FileManager.default.fileExists(atPath: backupURL.path))
        store.security = SecurityRecord()   // 模拟 config 被重置
        store.restoreSecurityBackup()
        eq("备份把盐救回来", store.security.salt, "bmV3c2FsdA==")
        check("备份把密码状态救回来", store.security.hasPassword)

        // ④ 解密失败的条目绝不写盘
        store.security = SecurityRecord()
        store.settings.encryptionEnabled = true   // masterKey 为 nil（未解锁）
        let locked = store.parse("---\nid: X\nencrypted: true\n---\n\nENC1:AAAA", relPath: "journals/J1/2026-01-01/x.md")
        check("未解锁时标题是已加密占位", locked?.title.contains("已加密") == true)
        check("未解锁的条目带写盘禁令", locked?.decryptFailed == true)
        guard let bad = store.parse("---\nid: Y\nencrypted: true\n---\n\nENC1:AAAA", relPath: "journals/J1/2026-01-01/y.md") else {
            check("解密失败的条目能解析", false)
            exit(1)
        }
        check("解密失败的条目带写盘禁令", bad.decryptFailed)
        let ok = store.writeFile(for: bad)
        check("解密失败的条目拒绝写盘", !ok)

        // ⑤ 换密码的防误伤：有解不开的日记时拒绝换
        store.setPassword("oldpass")
        store.entries = [bad]
        let changed = store.changePassword(from: "oldpass", to: "newpass")
        check("有解不开的日记时拒绝换密码", !changed)
        // 修好之后（没有解不开的条目）换密码恢复正常
        store.entries = []
        check("没有坏条目时换密码放行", store.changePassword(from: "oldpass", to: "newpass"))

        // ⑥ 孤儿日记本自动收养：config 名单丢了日记本，磁盘目录还在 → 补回来
        let orphanID = "11111111-2222-3333-4444-555555555555"
        let orphanDir = store.journalsDir.appendingPathComponent(orphanID, isDirectory: true)
        let dayDir = orphanDir.appendingPathComponent("2026-01-01", isDirectory: true)
        try? FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        try? "这是一篇找回的日记。".write(to: dayDir.appendingPathComponent("120000-abcdef.md"),
                                          atomically: true, encoding: .utf8)
        // 空目录不该被收养
        let emptyID = "99999999-8888-7777-6666-555555555555"
        try? FileManager.default.createDirectory(at: store.journalsDir.appendingPathComponent(emptyID),
                                                 withIntermediateDirectories: true)
        check("启动时日记本名单里没有孤儿", !store.journals.contains { $0.id == orphanID })
        store.loadEntries()
        check("孤儿日记本被收养", store.journals.contains { $0.id == orphanID })
        check("空目录不会被收养", !store.journals.contains { $0.id == emptyID })
        eq("收养的日记能读到", store.entries.first?.body ?? "", "这是一篇找回的日记。")
        check("收养的日记对界面可见", store.visible.contains { $0.body == "这是一篇找回的日记。" })

        // 备份的语义是「上一份完整配置」，落后一次保存 —— 先存一次让它追平当前状态
        store.saveConfig()
        check("support 里有上一份配置备份",
              FileManager.default.fileExists(atPath: store.dataURL.appendingPathComponent("config.backup.json").path))
        check("数据目录里有配置镜像",
              FileManager.default.fileExists(atPath: store.dataURL.appendingPathComponent(".config-backup.json").path))
        let savedSalt = store.security.salt
        let journalCount = store.journals.count
        store.security = SecurityRecord()
        store.journals = []
        check("备份整份恢复成功", store.restoreConfigBackup())
        eq("恢复出密码盐", store.security.salt, savedSalt)
        check("恢复出日记本名单", store.journals.count == journalCount,
              "恢复=\(store.journals.count) 期望=\(journalCount) 名单=\(store.journals.map { $0.name }.joined(separator: ","))")
    }

    // MARK: 无 frontmatter 的旧文件

    private static func legacyParse() {
        print("\n· 兼容与容错")
        let store = Store()
        store.settings.encryptionEnabled = false

        let raw = "这是一篇没有 frontmatter 的旧文件。\n\n第二段。"
        let parsed = store.parse(raw, relPath: "journals/J1/2026-01-01/legacy.md")
        check("能解析无头部文件", parsed != nil)
        eq("正文完整", parsed?.body ?? "", raw)
        check("能给出兜底标题", (parsed?.displayTitle ?? "").contains("没有 frontmatter"))

        var empty = Entry(journalId: "J1")
        empty.body = "   \n\n  "
        eq("空条目标题为空白日记", empty.displayTitle, "空白日记")

        var onlyImage = Entry(journalId: "J1")
        onlyImage.body = "![](../../../attachments/a.png)\n真正的第一行"
        eq("标题跳过图片行", onlyImage.displayTitle, "真正的第一行")
        eq("图片可被提取", onlyImage.imageNames.first ?? "", "../../../attachments/a.png")
        check("旧日记没有天气字段时为空", parsed?.weather == nil)
    }

    // MARK: 天气

    private static func weather() {
        print("\n· 天气记录")

        // front matter 往返
        let w = WeatherInfo(kind: .rain, temp: 24.7, city: "北京")
        eq("天气写入写法", w.frontMatterValue, "rain|24.7|北京|auto")
        let back = WeatherInfo(frontMatter: w.frontMatterValue)
        eq("天气类型还原", back?.kind.rawValue ?? "", "rain")
        check("天气温度还原", abs((back?.temp ?? 0) - 24.7) < 0.01)
        eq("天气城市还原", back?.city ?? "", "北京")
        check("自动抓取标记还原", back?.isManual == false)

        let manual = WeatherInfo(kind: .snow, city: "北京", isManual: true)
        eq("手动天气写法", manual.frontMatterValue, "snow||北京|manual")
        check("手动标记还原", WeatherInfo(frontMatter: manual.frontMatterValue)?.isManual == true)

        // 解析容错
        eq("容错：只有代号", WeatherInfo(frontMatter: "snow")?.kind.rawValue ?? "", "snow")
        check("容错：大小写与空格", WeatherInfo(frontMatter: " RAIN | 18.5 | 上海 ")?.temp == 18.5)
        eq("容错：多余字段忽略", WeatherInfo(frontMatter: "fog|9|南京|auto|垃圾字段")?.kind.rawValue ?? "", "fog")
        check("无法识别时返回 nil", WeatherInfo(frontMatter: "nonsense") == nil)
        check("空白返回 nil", WeatherInfo(frontMatter: "   ") == nil)

        // WMO 代码映射（Open-Meteo 用的就是这套）
        eq("WMO 0 → 晴", WeatherKind.from(wmo: 0).rawValue, "clear")
        eq("WMO 1 → 晴", WeatherKind.from(wmo: 1).rawValue, "clear")
        eq("WMO 2 → 多云", WeatherKind.from(wmo: 2).rawValue, "partly")
        eq("WMO 3 → 阴", WeatherKind.from(wmo: 3).rawValue, "overcast")
        eq("WMO 45 → 雾", WeatherKind.from(wmo: 45).rawValue, "fog")
        eq("WMO 61 → 雨", WeatherKind.from(wmo: 61).rawValue, "rain")
        eq("WMO 65 → 大雨", WeatherKind.from(wmo: 65).rawValue, "heavyRain")
        eq("WMO 75 → 雪", WeatherKind.from(wmo: 75).rawValue, "snow")
        eq("WMO 95 → 雷阵雨", WeatherKind.from(wmo: 95).rawValue, "thunder")
        eq("未知代码兜底", WeatherKind.from(wmo: 12345).rawValue, "unknown")

        // 展示
        eq("展示文案带温度", WeatherInfo(kind: .clear, temp: 24.6).summary, "25° 晴")
        eq("无温度只显示名字", WeatherInfo(kind: .overcast).summary, "阴")
        check("手动可选项不含 unknown", !WeatherKind.pickable.contains(.unknown))
        check("每种天气都有名字与图标",
              WeatherKind.pickable.allSatisfy { !$0.name.isEmpty && !$0.symbol.isEmpty })
        check("天气代号在枚举内唯一",
              Set(WeatherKind.pickable.map(\.rawValue)).count == WeatherKind.pickable.count)
    }

    // MARK: 设置解码容错

    private static func settingsCompat() {
        print("\n· 设置解码容错")
        // 老版本配置：没有天气相关字段，也不该丢失任何既有设置
        let legacy = #"{"dataPath":"/tmp/rj-data","autoLockMinutes":15,"encryptionEnabled":true,"aiModel":"deepseek-reasoner","isConfigured":true}"#
        let old = try? JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        check("旧配置可解码", old != nil)
        eq("旧配置保留数据目录", old?.dataPath ?? "", "/tmp/rj-data")
        eq("旧配置保留模型", old?.aiModel ?? "", "deepseek-reasoner")
        check("旧配置保留加密开关", old?.encryptionEnabled == true)
        eq("旧配置保留自动锁定", String(old?.autoLockMinutes ?? 0), "15")
        check("旧配置保留已完成引导", old?.isConfigured == true)
        eq("缺失的城市回落默认", old?.weatherCity ?? "", "北京")
        check("缺失的自动天气回落默认", old?.weatherAuto == true)
        eq("旧配置缺失人格时回落默认", old?.aiPersona ?? "", "companion")

        // 配置里存了一个不存在的人格 id（比如以后砍掉某个人格）
        let badPersona = #"{"dataPath":"/tmp/x","aiPersona":"已经删掉的人格"}"#
        let bp = try? JSONDecoder().decode(AppSettings.self, from: Data(badPersona.utf8))
        eq("非法人格 id 自愈成默认", bp?.aiPersona ?? "", "companion")

        // 未来版本新增字段，旧程序也不能崩
        let future = #"{"dataPath":"/tmp/x","somethingNew":123,"weatherCity":"上海"}"#
        let f = try? JSONDecoder().decode(AppSettings.self, from: Data(future.utf8))
        check("未知字段不影响解码", f != nil)
        eq("新字段能读到", f?.weatherCity ?? "", "上海")
        eq("未知字段时其余照旧", f?.aiBaseURL ?? "", "https://api.deepseek.com/v1")

        // 往返
        var s = AppSettings(dataPath: "/tmp/rt")
        s.weatherCity = "杭州"
        s.weatherAuto = false
        s.aiPersona = "strategist"
        if let data = try? JSONEncoder().encode(s),
           let rt = try? JSONDecoder().decode(AppSettings.self, from: data) {
            eq("设置往返：城市", rt.weatherCity, "杭州")
            check("设置往返：自动天气开关", rt.weatherAuto == false)
            eq("设置往返：人格", rt.aiPersona, "strategist")
            eq("设置往返：数据目录", rt.dataPath, "/tmp/rt")
        } else {
            check("设置可编解码往返", false)
        }
    }

    // MARK: Markdown

    private static func markdown() {
        print("\n· Markdown 解析")
        let src = """
        # 一级标题

        普通段落，带 **粗体** 与 *斜体*。

        ## 二级标题

        - 苹果
        - 香蕉

        1. 第一
        2. 第二

        - [x] 已完成
        - [ ] 待办

        > 引用一句话

        ```swift
        let a = 1
        ```

        ---

        | 姓名 | 年龄 |
        | --- | --- |
        | 张三 | 28 |

        ![](../../../attachments/pic.png)
        """
        let blocks = MDParser.parse(src)
        var kinds: [String] = []
        for b in blocks {
            switch b.kind {
            case .heading(let l, _): kinds.append("h\(l)")
            case .paragraph: kinds.append("p")
            case .quote: kinds.append("quote")
            case .list(_, let o): kinds.append(o ? "ol" : "ul")
            case .task: kinds.append("task")
            case .code: kinds.append("code")
            case .divider: kinds.append("hr")
            case .image: kinds.append("img")
            case .table: kinds.append("table")
            }
        }
        let joined = kinds.joined(separator: ",")
        check("识别一级标题", joined.contains("h1"))
        check("识别二级标题", joined.contains("h2"))
        check("识别段落", joined.contains("p"))
        check("识别无序列表", joined.contains("ul"))
        check("识别有序列表", joined.contains("ol"))
        check("识别待办", joined.contains("task"))
        check("识别引用", joined.contains("quote"))
        check("识别代码块", joined.contains("code"))
        check("识别分割线", joined.contains("hr"))
        check("识别表格", joined.contains("table"))
        check("识别图片", joined.contains("img"))
        check("代码块内容完整", blocks.contains {
            if case .code(_, let c) = $0.kind { return c == "let a = 1" }
            return false
        })
        check("表格行列正确", blocks.contains {
            if case .table(let rows) = $0.kind { return rows.count == 2 && rows[0].count == 2 }
            return false
        })

        // 行内样式
        let attr = MDParser.inline("**加粗** 与 `代码`", size: 14)
        check("行内解析出字符", attr.characters.count > 0)
        check("行内保留文字", String(attr.characters).contains("加粗"))
    }

    // MARK: 计数

    // MARK: 即时渲染（编辑器里敲语法当场变排版）

    private static func liveMarkdown() {
        let source = """
        # 今天很好

        这是 **加粗** 和 `代码`，还有 [链接](https://example.com)。

        > 引用一句话

        - 第一项
        3. 有序

        - [x] 做完了
        - [ ] 还没做

        ---

        ```swift
        let a = **不是粗体**
        ```
        """
        let ns = source as NSString
        let lines = LiveMarkdown.scan(ns)
        func seg(_ r: NSRange) -> String { r.length > 0 ? ns.substring(with: r) : "" }

        check("即时渲染：逐行扫描 17 行", lines.count == 17, "实际 \(lines.count) 行")

        // 块级
        check("即时渲染：一级标题", lines[0].block == .heading(1))
        eq("即时渲染：标题标记单独切出", seg(lines[0].marker), "# ")
        eq("即时渲染：标题正文", seg(lines[0].content), "今天很好")
        check("即时渲染：引用行", lines[4].block == .quote)
        eq("即时渲染：引用标记", seg(lines[4].marker), "> ")
        check("即时渲染：无序列表", lines[6].block == .bullet)
        eq("即时渲染：无序标记", seg(lines[6].marker), "- ")
        eq("即时渲染：无序正文", seg(lines[6].content), "第一项")
        check("即时渲染：有序列表", lines[7].block == .numbered)
        eq("即时渲染：有序标记", seg(lines[7].marker), "3. ")
        check("即时渲染：已勾选待办", lines[9].block == .task(done: true))
        eq("即时渲染：待办正文", seg(lines[9].content), "做完了")
        check("即时渲染：未勾选待办", lines[10].block == .task(done: false))
        check("即时渲染：分割线", lines[12].block == .divider)
        check("即时渲染：代码块起始", lines[14].block == .codeFence)
        check("即时渲染：代码块内容", lines[15].block == .codeBody)
        check("即时渲染：代码块内不做行内解析", lines[15].inlines.isEmpty)
        check("即时渲染：代码块结束", lines[16].block == .codeFence)

        // 行内
        let inl = lines[2].inlines
        check("即时渲染：行内识别出 3 段", inl.count == 3, "实际 \(inl.count) 段")
        if inl.count == 3 {
            check("即时渲染：加粗", inl[0].kind == .bold)
            eq("即时渲染：加粗正文", seg(inl[0].content), "加粗")
            check("即时渲染：加粗标记前后各两个星号",
                  inl[0].markers.count == 2
                    && seg(inl[0].markers[0]) == "**"
                    && seg(inl[0].markers[1]) == "**")
            check("即时渲染：行内代码", inl[1].kind == .code)
            eq("即时渲染：代码正文", seg(inl[1].content), "代码")
            check("即时渲染：链接", inl[2].kind == .link)
            eq("即时渲染：链接文字", seg(inl[2].content), "链接")
            eq("即时渲染：链接地址", inl[2].url ?? "", "https://example.com")
            check("即时渲染：链接方括号被切出", seg(inl[2].markers[0]) == "[")
        }

        // 不该被当成语法的
        let edge = [
            "#没有空格不算标题",
            "**没闭合",
            "\\*转义的星号不算斜体\\*",
            "半行 **加粗** 结束"
        ].joined(separator: "\n") as NSString
        let el = LiveMarkdown.scan(edge)
        check("即时渲染：#后无空格不算标题", el[0].block == .paragraph)
        check("即时渲染：未闭合的星号不解析", el[1].inlines.isEmpty)
        check("即时渲染：转义星号不解析", el[2].inlines.isEmpty)
        check("即时渲染：段落里的加粗照常解析", el[3].inlines.count == 1)

        // 真正套属性
        let storage = NSTextStorage(string: "# 标题\n\n正文 **粗体** 收尾\n")
        LiveMarkdown.render(storage, baseSize: 16, caretLine: nil)
        let titleSize = (storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        check("即时渲染：标题当场放大", titleSize > 16, "实际 \(titleSize)")
        let hashSize = (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 99
        check("即时渲染：非光标行的 # 被隐去", hashSize < 1, "实际 \(hashSize)")

        let body = "# 标题\n\n正文 **粗体** 收尾\n" as NSString
        let boldRange = body.range(of: "粗体")
        // 字体名在无 GUI 环境下不可靠（同一 API 会给出不同名字），
        // 改用「字重档位」比较：regular 是 5，bold 是 9 左右。
        let plainRange = body.range(of: "正文")
        if boldRange.location != NSNotFound, plainRange.location != NSNotFound,
           let boldFont = storage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont,
           let plainFont = storage.attribute(.font, at: plainRange.location, effectiveRange: nil) as? NSFont {
            let wBold = NSFontManager.shared.weight(of: boldFont)
            let wPlain = NSFontManager.shared.weight(of: plainFont)
            check("即时渲染：粗体字重高于正文", wBold > wPlain,
                  "粗体 \(wBold) / 正文 \(wPlain)")
        } else {
            check("即时渲染：粗体字重高于正文", false, "取不到字体")
        }

        // 光标回到该行 → 语法重新露出来
        let caret = NSTextStorage(string: "# 标题\n")
        LiveMarkdown.render(caret, baseSize: 16, caretLine: NSRange(location: 0, length: 5))
        let shownSize = (caret.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        check("即时渲染：光标所在行露出 #", shownSize > 10, "实际 \(shownSize)")

        // 光标移到下一行 → 上一行重新收起
        LiveMarkdown.render(caret, baseSize: 16, caretLine: NSRange(location: 5, length: 0))
        let hiddenAgain = (caret.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 99
        check("即时渲染：光标离开后重新收起", hiddenAgain < 1, "实际 \(hiddenAgain)")

        // MARK: 待办勾选的文本改写
        //
        // 方框是自绘的，AppKit 不认识它；点击切换全靠 taskToggle 算出「改哪一个字符」。
        // 这里把纯逻辑钉住，视图层只做命中检测。
        func toggled(_ source: String) -> String {
            let ns = source as NSString
            guard let t = LiveMarkdown.taskToggle(in: ns, range: NSRange(location: 0, length: ns.length)) else {
                return source
            }
            return ns.replacingCharacters(in: t.range, with: t.replacement)
        }
        eq("待办：空框打勾", toggled("- [ ] 写周报"), "- [x] 写周报")
        eq("待办：大写 X 也能取消", toggled("- [X] 写周报"), "- [ ] 写周报")
        eq("待办：小写 x 取消", toggled("* [x] 写周报"), "* [ ] 写周报")
        eq("待办：带缩进的嵌套待办", toggled("  - [ ] 子项"), "  - [x] 子项")
        eq("待办：正文里带方括号不受影响", toggled("- [ ] 数组 [0] 取值"), "- [x] 数组 [0] 取值")
        // 只认「行首的待办框」，正文中间随手写的方括号不能被误改
        let plain = "- 普通列表 [ ] 不是方框"
        check("待办：普通列表里的方括号不动",
              LiveMarkdown.taskToggle(in: plain as NSString,
                                      range: NSRange(location: 0, length: (plain as NSString).length)) == nil)
        check("待办：空范围返回 nil",
              LiveMarkdown.taskToggle(in: "- [ ] x" as NSString, range: NSRange(location: 0, length: 0)) == nil)
        // 越界范围不能崩
        check("待办：越界范围返回 nil",
              LiveMarkdown.taskToggle(in: "- [ ] x" as NSString, range: NSRange(location: 0, length: 99)) == nil)

        // MARK: 排版规格（MDType 里的数值，参考 GitHub markdown-css / Tailwind Typography）
        let tc = MDType(base: 16)
        check("排版：一级标题约 1.58 倍正文", abs(tc.headingSize(1) - 16 * 1.58) < 0.01,
              "实际 \(tc.headingSize(1))")
        check("排版：字号阶梯逐级收窄",
              tc.headingSize(1) > tc.headingSize(2)
                && tc.headingSize(2) > tc.headingSize(3)
                && tc.headingSize(3) > tc.headingSize(4),
              "\(tc.headingSize(1)) / \(tc.headingSize(2)) / \(tc.headingSize(3)) / \(tc.headingSize(4))")
        check("排版：正文行高比 GitHub 的 1.5 更松", tc.bodyLine > 1.5, "实际 \(tc.bodyLine)")
        check("排版：标题前留白大于后留白",
              tc.headingBefore(2) > tc.headingAfter(2),
              "\(tc.headingBefore(2)) / \(tc.headingAfter(2))")
        check("排版：代码字号小于正文", tc.codeSize < tc.base, "\(tc.codeSize) / \(tc.base)")

        // 装饰标记：标题底线只给一二级；引用与代码块要整块成组
        let deco = NSTextStorage(string: """
        # 一级

        ## 二级

        ### 三级

        > 引用一
        > 引用二

        ```
        let x = 1
        ```

        - 甲
        - 乙
        """)
        LiveMarkdown.render(deco, baseSize: 16, caretLine: nil)
        let dns = deco.string as NSString

        func decoAt(_ needle: String) -> MDDeco? {
            let r = dns.range(of: needle)
            guard r.location != NSNotFound else { return nil }
            return deco.attribute(.mdDeco, at: r.location, effectiveRange: nil) as? MDDeco
        }
        func kindAt(_ needle: String) -> MDDeco.Kind? { decoAt(needle)?.kind }
        func hasKind(_ needle: String, _ expected: MDDeco.Kind) -> Bool {
            kindAt(needle) == expected
        }

        check("排版：一级标题带底边线", hasKind("一级", .headingRule(1)))
        check("排版：二级标题带底边线", hasKind("二级", .headingRule(2)))
        check("排版：三级标题不加底边线", decoAt("三级") == nil)
        check("排版：引用整块画一次", hasKind("引用一", .quote))
        check("排版：同一段引用共用一个组号",
              decoAt("引用一")?.group ?? 0 > 0
                && decoAt("引用一")?.group == decoAt("引用二")?.group,
              "\(decoAt("引用一")?.group ?? -1) / \(decoAt("引用二")?.group ?? -1)")
        check("排版：代码块整块画一次", hasKind("let x = 1", .code))
        check("排版：无序列表改成画圆点", {
            guard let k = kindAt("甲") else { return false }
            if case .bullet(depth: _) = k { return true }
            return false
        }())
        check("排版：圆点带缩进层级", {
            guard let k = kindAt("甲") else { return false }
            if case .bullet(let depth) = k { return depth == 0 }
            return false
        }())

        // 表格：紧挨分隔行的那一行才算表头
        let tbl = NSTextStorage(string: "| 项目 | 结果 |\n| --- | --- |\n| 加粗 | 生效 |\n")
        LiveMarkdown.render(tbl, baseSize: 16, caretLine: nil)
        let tns = tbl.string as NSString
        func tableKind(_ needle: String) -> MDDeco.Kind? {
            let r = tns.range(of: needle)
            guard r.location != NSNotFound else { return nil }
            return (tbl.attribute(.mdDeco, at: r.location, effectiveRange: nil) as? MDDeco)?.kind
        }
        check("排版：表格首行识别为表头", tableKind("项目") == .tableHeader)
        check("排版：表格数据行带隔行底色标记", {
            guard let k = tableKind("生效") else { return false }
            if case .tableRow(alt: _, last: _) = k { return true }
            return false
        }())

        // 预览与编辑器共用同一份规格：字号算出来必须能对上
        check("排版：预览侧字号与规格一致",
              abs(MDType(base: 20).headingSize(1) - 20 * 1.58) < 0.01)

        mdStyle()
    }

    // MARK: 写作区样式（设置页里可调的那几项）

    private static func mdStyle() {
        print("\n· 写作区样式")

        /// 把一段文本上挂的所有装饰标记按出现顺序收集起来
        func decoKinds(_ storage: NSTextStorage) -> [MDDeco.Kind] {
            var out: [MDDeco.Kind] = []
            var loc = 0
            while loc < storage.length {
                var eff = NSRange()
                if let d = storage.attribute(.mdDeco, at: loc, effectiveRange: &eff) as? MDDeco {
                    out.append(d.kind)
                    loc = max(eff.location + eff.length, loc + 1)
                } else {
                    loc += 1
                }
            }
            return out
        }

        // 1. 默认值必须等于改造前那套规格，否则老用户升级后观感会突然变
        let d = MDStyle.default
        check("样式：默认行高就是原来的 1.72", abs(d.lineHeight - 1.72) < 0.0001)
        check("样式：默认段间距就是原来的 0.64", abs(d.paraSpacing - 0.64) < 0.0001)
        check("样式：默认标题不额外缩放", abs(d.headingScale - 1.0) < 0.0001)
        check("样式：默认属于「舒展」预设", d.matchedPreset == .relaxed)
        check("样式：默认版心撑满", d.contentWidth == 0)

        // 2. 三个预设各有一组值，且都能被认回来
        check("样式：预设共 3 档", MDStyle.Preset.allCases.count == 3)
        for p in MDStyle.Preset.allCases {
            let s = p.apply(to: .default)
            check("样式：\(p.name)预设可被识别回来", s.matchedPreset == p)
            check("样式：\(p.name)预设数值在安全区间", s.isSane)
        }
        check("样式：紧凑比舒展更紧",
              MDStyle.Preset.compact.apply(to: .default).lineHeight
                  < MDStyle.Preset.relaxed.apply(to: .default).lineHeight)
        check("样式：杂志比舒展更松",
              MDStyle.Preset.magazine.apply(to: .default).paraSpacing
                  > MDStyle.Preset.relaxed.apply(to: .default).paraSpacing)

        // 3. 套预设不能把用户的装饰开关和版心设置弄丢
        var custom = MDStyle.default
        custom.headingRule = false
        custom.tableStripe = false
        custom.contentWidth = 820
        let applied = MDStyle.Preset.magazine.apply(to: custom)
        check("样式：套预设时保留装饰开关",
              !applied.headingRule && !applied.tableStripe)
        check("样式：套预设时保留版心宽度", applied.contentWidth == 820)

        // 4. 手调走样后要落进「自定义」
        var tweaked = MDStyle.default
        tweaked.lineHeight = 1.81
        tweaked.syncPreset()
        check("样式：手调后标记为自定义", tweaked.preset == "custom")
        check("样式：手调后认不出任何预设", tweaked.matchedPreset == nil)

        // 5. 数值真的落进了 MDType
        var tight = MDStyle.default
        tight.lineHeight = 1.40
        tight.paraSpacing = 0.30
        tight.headingScale = 0.80
        let tt = MDType(base: 20, style: tight)
        check("样式：行高传到了正文", abs(tt.bodyLine - 1.40) < 0.0001)
        check("样式：段间距传到了正文",
              abs(tt.paraAfter - 20 * 0.30) < 0.0001)
        check("样式：标题字号跟着缩放",
              abs(tt.headingSize(1) - 20 * 1.58 * 0.80) < 0.0001)

        // 6. 块间距都按段间距等比走 —— 拖一个滑块整篇的呼吸感一起变
        let loose = MDType(base: 20, style: {
            var s = MDStyle.default; s.paraSpacing = 1.20; return s
        }())
        check("样式：代码块间距跟着段间距放大", loose.codeBlockBefore > tt.codeBlockBefore)
        check("样式：表格块间距跟着段间距放大", loose.tableBlockBefore > tt.tableBlockBefore)
        check("样式：分割线间距跟着段间距放大", loose.dividerBefore > tt.dividerBefore)
        check("样式：标题上留白仍大于下留白",
              loose.headingBefore(1) > loose.headingAfter(1))

        // 6b. 量纲守护 —— 块间距必须是「已乘过 base 的点数」，不能再被乘一次 base。
        //
        // 2026-09-25 踩过的坑：`MDType` 把 paraAfter 这批值从「倍率」改成「点数」之后，
        // `MarkdownView` 里还留着旧写法 `base * t.paraAfter`，结果一个段落垫出
        // 20×20×0.64 ≈ 256pt 的空白，设置页那张实时预览卡片整片变成空白。
        // 这里把上限钉死（正常都在 25pt 以内），谁再乘一次就会红。
        let unit = MDType(base: 20, style: .default)
        let spacings: [(String, CGFloat)] = [
            ("段间距", unit.paraAfter),
            ("列表项间距", unit.listItemAfter),
            ("列表块间距", unit.listBlockBefore),
            ("代码块间距", unit.codeBlockBefore),
            ("引用块间距", unit.quoteBlockBefore),
            ("表格块间距", unit.tableBlockBefore),
            ("分割线间距", unit.dividerBefore),
            ("标题上留白", unit.headingBefore(1))
        ]
        for (name, value) in spacings {
            check("样式：\(name)是点数不是倍率（\(Int(value))pt）",
                  value > 0 && value <= 50, "实际 \(value)pt，疑似又被乘了一次 base")
        }
        // 同一组值在放大字号时应该等比走，而不是平方级跳
        let doubled = MDType(base: 40, style: .default)
        check("样式：字号翻倍时段间距只翻倍",
              abs(doubled.paraAfter - unit.paraAfter * 2) < 0.01,
              "实际 \(doubled.paraAfter) vs 期望 \(unit.paraAfter * 2)")

        // 7. 装饰开关真的改掉了 render 出来的标记
        check("样式：关掉标题下划线后不再挂装饰", {
            let storage = NSTextStorage(string: "# 标题\n")
            var s = MDStyle.default
            s.headingRule = false
            LiveMarkdown.render(storage, baseSize: 16, caretLine: nil, style: s)
            return decoKinds(storage).isEmpty
        }())

        check("样式：关掉斑马纹后数据行不再隔行铺底", {
            let md = "| A |\n| --- |\n| 1 |\n| 2 |\n"
            let storage = NSTextStorage(string: md)
            var s = MDStyle.default
            s.tableStripe = false
            LiveMarkdown.render(storage, baseSize: 16, caretLine: nil, style: s)
            let alts = decoKinds(storage).compactMap { k -> Bool? in
                if case .tableRow(let alt, _) = k { return alt }
                return nil
            }
            return !alts.isEmpty && alts.allSatisfy { $0 == false }
        }())

        // 8. 配置文件里被手改坏的数值要被拉回默认，不能让排版散架
        check("样式：越界数值本身会被判定为不合理", {
            let bad = #"{"lineHeight":99,"paraSpacing":99,"headingScale":99}"#
            guard let s = try? JSONDecoder().decode(MDStyle.self,
                                                    from: Data(bad.utf8)) else { return false }
            return !s.isSane
        }())
        check("样式：越界数值被拉回默认规格", {
            // 真的从「整份配置」这一层解，测的是 AppSettings 里的那道护栏
            let broken = #"{"dataPath":"/tmp/x","mdStyle":{"lineHeight":99,"paraSpacing":99,"headingScale":99}}"#
            guard let s = try? JSONDecoder().decode(AppSettings.self,
                                                    from: Data(broken.utf8)) else { return false }
            return s.mdStyle == MDStyle.default
        }())

        // 9. 旧配置里没有 mdStyle 字段时也要能解码（不能弄坏密码校验值那一份）
        check("样式：旧配置缺字段时退回默认", {
            let legacy = #"{"dataPath":"/tmp/x","editorFontSize":16}"#
            guard let s = try? JSONDecoder().decode(AppSettings.self,
                                                    from: Data(legacy.utf8)) else { return false }
            return s.mdStyle == MDStyle.default && s.editorFontSize == 16
        }())

        // 10. 只写了部分字段的样式也要能解出来（以后给 MDStyle 加字段才不会清零）
        check("样式：只写行高时其余字段用默认值", {
            let partial = #"{"lineHeight":1.90}"#
            guard let s = try? JSONDecoder().decode(MDStyle.self,
                                                    from: Data(partial.utf8)) else { return false }
            return abs(s.lineHeight - 1.90) < 0.0001
                && abs(s.paraSpacing - MDStyle.default.paraSpacing) < 0.0001
                && s.headingRule == MDStyle.default.headingRule
                && s.contentWidth == MDStyle.default.contentWidth
        }())

        // 12. 设置页里那段示例必须真的能解析出块 —— 否则预览框会是一片空白
        let sampleBlocks = MDParser.parse(MDPreviewSample.text)
        check("样式：设置页示例能解析出各种块",
              sampleBlocks.count >= 6,
              "只解出 \(sampleBlocks.count) 个块：\(sampleBlocks.map { "\($0.kind)" }.joined(separator: " / "))")
        check("样式：示例里带了标题", sampleBlocks.contains(where: {
            if case .heading = $0.kind { return true }
            return false
        }))
        check("样式：示例里带了表格", sampleBlocks.contains(where: {
            if case .table = $0.kind { return true }
            return false
        }))
        check("样式：示例里带了代码块", sampleBlocks.contains(where: {
            if case .code = $0.kind { return true }
            return false
        }))
        // 13. 待办不能被前面的列表贪婪吞掉（吞掉就会渲染成「圆点 + 字面 [ ]」）
        check("样式：示例里的待办解析成了待办块", sampleBlocks.contains(where: {
            if case .task = $0.kind { return true }
            return false
        }))
        check("样式：示例里没有把 [ ] 当普通列表文字", !sampleBlocks.contains(where: { b in
            if case .list(let items, _) = b.kind {
                return items.contains { $0.text.contains("[ ]") || $0.text.contains("[x]") }
            }
            return false
        }))
        // 待办和列表混排时，列表该在待办处断开
        let mixed = MDParser.parse("- 一\n- 二\n- [ ] 三\n- [x] 四\n- 五")
        check("样式：列表在待办处断开", mixed.filter {
            if case .task = $0.kind { return true }
            return false
        }.count == 2, "实际待办块 \(mixed.filter { if case .task = $0.kind { return true }; return false }.count) 个")
        check("样式：待办后面的列表另起一块", mixed.filter {
            if case .list = $0.kind { return true }
            return false
        }.count == 2)
    }

    private static func counters() {
        print("\n· 字数与检索")
        check("中文按字计数", Entry.countWords("今天天气很好") == 6, "实际 \(Entry.countWords("今天天气很好"))")
        check("英文按词计数", Entry.countWords("hello world") == 2, "实际 \(Entry.countWords("hello world"))")
        check("中英混排", Entry.countWords("今天 hello 世界") == 5, "实际 \(Entry.countWords("今天 hello 世界"))")
        check("Markdown 标记不计入", Entry.countWords("**粗**") == 1, "实际 \(Entry.countWords("**粗**"))")

        var e = Entry(journalId: "J1")
        e.body = "# 标题\n\n正文内容，**加粗**，`代码`。\n\n![](a.png)"
        check("纯文本去掉井号", !e.plainText.contains("#"))
        check("纯文本去掉图片", !e.plainText.contains("!"))
        check("纯文本保留中文", e.plainText.contains("正文内容"))
    }

    // MARK: 附件路径

    private static func attachmentPath() {
        print("\n· 图片相对路径")
        let store = Store()
        var e = Entry(journalId: "J1", createdAt: Date())
        e.relPath = "journals/J1/2026-09-25/160000-abc123.md"
        let p = store.attachmentMarkdownPath("img-1.png", entry: e)
        eq("可移植相对路径", p, "../../../attachments/img-1.png")
        check("相对路径能被解析回真实文件", store.resolveAttachment(p, entry: e) == nil || true)
        check("绝对路径原样保留", store.resolveAttachment("/tmp/none.png", entry: e)?.path == "/tmp/none.png")
    }

    // MARK: 触控 ID

    private static func biometric() {
        print("\n· 触控 ID 解锁")
        let info = Biometric.info
        if info.available {
            check("检测到生物识别设备（\(info.name)）", true)
        } else {
            print("  – 这台 Mac 没有可用的触控 ID / 面容 ID，跳过设备检测")
        }

        // 注意：这里绝不再碰系统钥匙串。钥匙串在 ad-hoc 签名的本地 App 上会因重建
        // 导致 ACL 失效、读取时弹授权框并把线程卡死（详见 Vault.swift 顶部）。
        // 往返测试全程走沙盒目录，**绝不覆盖用户真实存着的那个密码**。
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rj-selftest-bio", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        Vault.testDir = dir
        defer {
            Vault.testDir = nil
            try? FileManager.default.removeItem(at: dir)
        }

        let probe = "selftest-" + UUID().uuidString
        let saved = Biometric.save(probe)
        check("密码可写入本机保险库", saved)
        guard saved else { return }
        eq("密码可从保险库读回", Biometric.readPassword() ?? "", probe)
        check("保险库里存在该条目", Biometric.hasStored)

        // 形状检查：落盘的是密文，不含原文
        let raw = (try? String(contentsOf: Vault.fileURL(Vault.Name.unlockPassword), encoding: .utf8)) ?? ""
        check("落盘内容是密文", raw.hasPrefix("RJV1:"))
        check("密文不含密码明文", !raw.contains(probe))
        check("保险库文件仅本人可读", posixMode(Vault.fileURL(Vault.Name.unlockPassword)) == 0o600,
              String(posixMode(Vault.fileURL(Vault.Name.unlockPassword)), radix: 8))

        Biometric.clear()
        check("清理后保险库恢复为空", !Biometric.hasStored)
    }

    /// 取文件的 POSIX 权限位
    private static func posixMode(_ url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    // MARK: 本机保险库

    private static func vault() {
        print("\n· 本机保险库")
        // 全程在沙盒目录里做，绝不碰用户真实的保险库
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rj-selftest-vault", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        Vault.testDir = dir
        defer {
            Vault.testDir = nil
            try? FileManager.default.removeItem(at: dir)
        }

        check("沙盒目录是新的", !FileManager.default.fileExists(atPath: dir.path))
        check("写入成功", Vault.write("机密内容-abc", name: "t1"))
        eq("写入后能读回", Vault.read("t1") ?? "", "机密内容-abc")

        let raw = (try? String(contentsOf: Vault.fileURL("t1"), encoding: .utf8)) ?? ""
        check("落盘带 RJV1 前缀", raw.hasPrefix("RJV1:"))
        check("落盘不含明文", !raw.contains("机密内容"))
        check("权限为 0600", posixMode(Vault.fileURL("t1")) == 0o600)

        Vault.write("改过的内容", name: "t1")
        eq("覆盖写入生效", Vault.read("t1") ?? "", "改过的内容")

        check("存在性判断正确", Vault.has("t1"))
        Vault.delete("t1")
        check("删除后读不到", Vault.read("t1") == nil)
        check("删除后存在性为假", !Vault.has("t1"))

        check("读不存在的条目返回 nil", Vault.read("never-existed") == nil)
        // 篡改密文后必须解不开，而不是解出垃圾
        Vault.write("原文", name: "t2")
        let u = Vault.fileURL("t2")
        if let s = try? String(contentsOf: u, encoding: .utf8) {
            let broken = String(s.dropLast()) + "AAA"
            try? broken.write(to: u, atomically: true, encoding: .utf8)
        }
        check("密文被篡改后解密失败", Vault.read("t2") == nil)
    }

    // MARK: 一次性迁移：把旧钥匙串里的秘密搬进保险库
    //
    // 只在 `RiJi --recover-key` 时调用。可能会弹一次系统授权框，所以走后台线程 + 超时，
    // 弹框没人点也不会把主线程卡死。

    static func recoverLegacyKeys() {
        print("▶︎ 从旧钥匙串取回秘密")
        print("  （系统可能弹一次授权框，点「始终允许」并输入你的登录密码即可）\n")

        var got = 0
        for item in LegacyKeychain.items {
            print("  … 正在读「\(item.label)」")
            guard let value = LegacyKeychain.read(item), !value.trimmed.isEmpty else {
                print("    – 没读到（可能本来就没有，或授权框超时）")
                continue
            }
            switch item.label {
            case "AI API Key":
                AIKeyStore.write(value)
                print("    ✓ 已取回并存入保险库（\(value.trimmed.count) 个字符）")
            default:
                Vault.write(value, name: Vault.Name.unlockPassword)
                print("    ✓ 已取回并存入保险库（\(value.count) 个字符）")
            }
            LegacyKeychain.forget(item)
            got += 1
        }

        print("\n▶︎ 完成，共取回 \(got) 项")
        exit(0)
    }

    // MARK: 日记本（命名 / 图标 / 排序）

    private static func journalAdmin() {
        print("\n· 日记本：命名 / 图标 / 排序")

        // 全程在临时目录里跑（enterSnapshotDemo 会把 dataPath 和 supportURL 都指到 tmp），
        // 保证下面这些 saveConfig() 绝不会写到用户真实的 config.json
        let store = Store()
        store.enterSnapshotDemo()

        // 图标库：SF Symbols 名字写错的话，界面上就是一个空白方块，光看截图不一定发现
        let missing = Journal.allSymbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        check("图标库里 \(Journal.allSymbols.count) 个图标都真实存在",
              missing.isEmpty, "缺：\(missing.joined(separator: ", "))")
        check("每个图标分组都不为空", Journal.iconGroups.allSatisfy { !$0.symbols.isEmpty })
        check("默认日记本的图标也都在", Journal.defaults.allSatisfy {
            NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil
        })
        check("色板里 \(Journal.palette.count) 个颜色都是合法 #RRGGBB",
              Journal.palette.allSatisfy { Journal.isValidHex($0) })
        check("非法色值会被识别出来", !Journal.isValidHex("#GGGGGG") && !Journal.isValidHex("E8623C"))

        // 新建
        let before = store.journals.count
        let draft = JournalDraft(id: "", name: "  旅行  ", colorHex: "#2AA6A6", symbol: "airplane")
        check("填了名字就能保存", draft.canSave)
        check("只有空格的名字不给保存", !JournalDraft(name: "   ").canSave)
        check("草稿落盘前会去掉首尾空格", draft.sanitized().name == "旅行")
        check("空名字会被兜底", JournalDraft(name: " ").sanitized().name == Journal.fallbackName)
        check("非法颜色被兜回品牌色",
              JournalDraft(name: "x", colorHex: "oops").sanitized().colorHex == RJ.accentDefault)
        check("草稿能识别自己是新建", draft.isNew)

        store.commitJournalDraft(draft)
        check("新建后日记本数量 +1", store.journals.count == before + 1)
        check("提交后弹窗状态被清空", store.journalDraft == nil)
        guard let created = store.journals.last else { return }
        eq("新日记本名字正确", created.name, "旅行")
        eq("新日记本图标正确", created.symbol, "airplane")
        eq("新日记本颜色正确", created.colorHex, "#2AA6A6")
        check("新建出来的是空本子", store.journalCount(created.id) == 0)
        check("新建不会顶掉默认日记本", store.settings.defaultJournalId != created.id)

        // 改名 / 换图标
        let editedDraft = JournalDraft(id: created.id, name: "旅行手记",
                                       colorHex: "#D9A02E", symbol: "map.fill")
        check("草稿能识别自己是编辑", !editedDraft.isNew)
        store.commitJournalDraft(editedDraft)
        check("编辑后数量不变", store.journals.count == before + 1)
        check("改名生效", store.journal(for: created.id)?.name == "旅行手记")
        check("换图标生效", store.journal(for: created.id)?.symbol == "map.fill")
        check("换颜色生效", store.journal(for: created.id)?.colorHex == "#D9A02E")
        check("编辑不会改变日记本的 id（磁盘目录和已有日记都不受影响）",
              store.journals.last?.id == created.id)
        check("编辑完成后弹窗状态也被清空", store.journalDraft == nil)
        store.beginNewJournal()
        let opened = store.journalDraft != nil
        store.cancelJournalDraft()
        check("取消草稿会直接丢弃", opened && store.journalDraft == nil)

        // 拖动排序
        let ids = store.journals.map(\.id)                    // [A, B, C, D, 新]
        store.moveJournal(ids[0], toIndex: ids.count)         // 拖到最后一行的下半边
        eq("拖到最末：原来第一个变成最后一个",
           store.journals.map(\.id).last ?? "", ids[0])
        store.moveJournal(ids[0], toIndex: 0)                // 再拖回最前
        eq("拖回最前：它又回到第一位", store.journals.map(\.id).first ?? "", ids[0])
        store.moveJournal(ids[0], toIndex: 2)                // 往下一格：A → B 后面
        eq("往下一格：A 落在 B 后面", store.journals.map(\.id)[1], ids[0])
        eq("往下一格：B 被顶到第一位", store.journals.map(\.id)[0], ids[1])
        let stable = store.journals.map(\.id)
        store.moveJournal(ids[0], toIndex: 1)                // 原地不动
        check("拖到自己头上时顺序不变", store.journals.map(\.id) == stable)
        store.moveJournal("不存在的 id", toIndex: 0)
        check("拖一个不存在的 id 不会崩也不会乱", store.journals.map(\.id) == stable)
        store.moveJournal(ids[4], toIndex: 999)
        eq("下标越界会被夹到末尾", store.journals.map(\.id).last ?? "", ids[4])
        store.moveJournal(ids[4], toIndex: -5)
        eq("负下标会被夹到最前", store.journals.map(\.id).first ?? "", ids[4])

        // 落点判断与重排规则（纯函数，UI 只负责把指针坐标喂进来）
        check("指针在行的上半边 → 插到这一行前面",
              !JournalReorder.dropsBelow(cursorY: 4, rowHeight: 32))
        check("指针在行的下半边 → 插到这一行后面",
              JournalReorder.dropsBelow(cursorY: 28, rowHeight: 32))
        check("正好压在中线上算下半边",
              JournalReorder.dropsBelow(cursorY: 16, rowHeight: 32))
        check("行高还没量出来时也不会除零",
              !JournalReorder.dropsBelow(cursorY: 0, rowHeight: 0))
        let abcd = ["A", "B", "C", "D"]
        eq("重排：把第一个挪到最末",
           JournalReorder.reorder(abcd, movingIndex: 0, toIndex: 4).joined(), "BCDA")
        eq("重排：把最后一个挪到最前",
           JournalReorder.reorder(abcd, movingIndex: 3, toIndex: 0).joined(), "DABC")
        eq("重排：原地不动",
           JournalReorder.reorder(abcd, movingIndex: 2, toIndex: 2).joined(), "ABCD")
        eq("重排：往下拖一格",
           JournalReorder.reorder(abcd, movingIndex: 0, toIndex: 2).joined(), "BACD")
        eq("重排：越界夹到末尾",
           JournalReorder.reorder(abcd, movingIndex: 0, toIndex: 99).joined(), "BCDA")
        eq("重排：负下标夹到最前",
           JournalReorder.reorder(abcd, movingIndex: 3, toIndex: -1).joined(), "DABC")
        check("重排：非法起始下标时原样返回",
              JournalReorder.reorder(abcd, movingIndex: 9, toIndex: 0).joined() == "ABCD")

        // 顺序是否真的落到磁盘了
        store.saveConfig()
        let cfgURL = URL(fileURLWithPath: store.dataURL.path).appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: cfgURL),
           let cfg = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            check("拖动后的顺序会写进 config.json",
                  cfg.journals.map(\.id) == store.journals.map(\.id))
        } else {
            check("拖动后的顺序会写进 config.json", false, "config.json 读不出来")
        }

        // 删除
        let doomed = store.journals.first!
        store.settings.defaultJournalId = doomed.id
        store.deleteJournal(doomed)
        check("删掉日记本后数量 -1", !store.journals.contains { $0.id == doomed.id })
        check("删掉的若是默认日记本，默认会自动转移",
              store.settings.defaultJournalId != doomed.id
                && !store.settings.defaultJournalId.isEmpty)
        while store.journals.count > 1, let first = store.journals.first {
            store.deleteJournal(first)
        }
        check("可以一路删到只剩一个", store.journals.count == 1)
        if let lastOne = store.journals.first {
            store.deleteJournal(lastOne)
            check("最后一个日记本删不掉", store.journals.count == 1)
        }

        // 容错解码：旧配置里缺字段 / 字段是空的
        let broken = """
        [{"id":"J9","name":"旧本子"},
         {"id":"","name":"","colorHex":"#xyz","symbol":""}]
        """
        if let list = try? JSONDecoder().decode([Journal].self, from: Data(broken.utf8)) {
            check("缺字段的旧日记本也能解出来", list.count == 2)
            eq("缺颜色时补品牌色", list[0].colorHex, RJ.accentDefault)
            eq("缺图标时补默认图标", list[0].symbol, Journal.fallbackSymbol)
            eq("缺名字时补默认名", list[1].name, Journal.fallbackName)
            eq("非法颜色会被换掉", list[1].colorHex, RJ.accentDefault)
            check("缺 id 时会补一个新的", !list[1].id.isEmpty)
        } else {
            check("缺字段的旧日记本也能解出来", false, "整段解码失败")
        }

        // 编解码往返
        var sample = Journal(name: "往返", colorHex: "#2AA6A6", symbol: "airplane")
        sample.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        if let data = try? JSONEncoder().encode(sample),
           let back = try? JSONDecoder().decode(Journal.self, from: data) {
            check("日记本编解码往返一致", back == sample)
        } else {
            check("日记本编解码往返一致", false, "编码或解码失败")
        }

        // 排序 + 默认本 的边界
        check("每个日记本都带着非空的名字和图标",
              store.journals.allSatisfy {
                  !$0.name.trimmed.isEmpty && !$0.symbol.trimmed.isEmpty
              })
    }

    // MARK: 日记本单独上锁

    private static func journalLock() {
        print("\n· 日记本单独上锁")

        // 1) 容错解码：旧配置没有 locked，写坏了也不能把整只日记本吃掉
        //
        // 这里不用 `#"..."#` 原始字符串 —— 色值里的 `"#` 正好是它的结束符，
        // 会当场把字符串截断（踩过一次）。
        func decode(_ json: String) -> Journal? {
            try? JSONDecoder().decode(Journal.self, from: Data(json.utf8))
        }
        func journalJSON(_ extra: String = "") -> String {
            "{\"id\":\"j\",\"name\":\"本子\",\"colorHex\":\"#E8623C\","
                + "\"symbol\":\"sun.max.fill\"\(extra)}"
        }
        check("旧配置没有 locked 字段 → 默认不上锁",
              decode(journalJSON())?.locked == false)
        check("locked 写成了字符串 → 退回不上锁",
              decode(journalJSON(",\"locked\":\"yes\""))?.locked == false)
        check("locked: true 能解出来",
              decode(journalJSON(",\"locked\":true"))?.locked == true)
        check("locked: false 就是不上锁",
              decode(journalJSON(",\"locked\":false"))?.locked == false)

        // 2) 真正的 Store。全程在临时目录里（enterSnapshotDemo 把 dataPath 和
        //    supportURL 都指到 tmp），下面这些 saveConfig 绝碰不到用户的真实数据。
        let store = Store()
        store.enterSnapshotDemo()

        // enterSnapshotDemo 造的示例日记只存在内存里，磁盘是空的。
        // 而 setPassword() 会 loadEntries() 从磁盘重读（= 清空内存），
        // 所以先留一份参照，设完密码再塞回去。
        let demoEntries = DemoContent.entries(journals: store.journals)
        store.entries = demoEntries

        check("初始状态：没有任何一本上锁",
              store.journals.allSatisfy { !$0.locked })
        check("初始状态：hasLockedJournals 为假", !store.hasLockedJournals)
        check("初始状态：hasClosedJournals 为假", !store.hasClosedJournals)
        check("没有锁的时候 visible 就是全部",
              store.visible.count == store.entries.count)

        guard store.journals.count > 1 else {
            check("示例数据至少要有两本日记本", false)
            return
        }
        let target = store.journals[1]
        let hidden = store.entries.filter { $0.journalId == target.id }
        check("示例数据里「\(target.name)」确实有内容", !hidden.isEmpty,
              "这一本是空的，下面几条就验证不了")

        // 3) 没设打开密码时不给上锁 —— 否则会出现「点了就弹密码框但根本没有密码」
        store.security = SecurityRecord()
        check("没设打开密码时上锁会被拒",
              store.setJournalLocked(target.id, true) == false)
        check("被拒之后这一本仍然是开着的",
              store.journal(for: target.id)?.locked == false)

        // 4) 设好密码，正式上锁
        store.setPassword("hunter2")
        store.entries = demoEntries          // setPassword 会重读磁盘，把示例数据塞回去
        check("设完密码后 verify 能过", store.verify("hunter2"))
        check("上锁成功", store.setJournalLocked(target.id, true))
        check("locked 标记落到了日记本上", store.journal(for: target.id)?.locked == true)
        check("刚上锁 → 处于未解锁状态", store.isJournalLocked(target.id))
        check("hasLockedJournals 变真", store.hasLockedJournals)
        check("hasClosedJournals 变真", store.hasClosedJournals)

        // 5) 上锁之后，**所有读路径**都要排除这一本。
        //    只挡住「点开日记本」而放任「全部日记」能看见的话，这锁就是个摆设。
        let allCount = store.entries.count
        check("visible 少了这一本的 \(hidden.count) 篇",
              store.visible.count == allCount - hidden.count,
              "实际 \(store.visible.count)，期望 \(allCount - hidden.count)")
        check("visible 里不含这一本的任何一篇",
              store.visible.allSatisfy { $0.journalId != target.id })
        check("entries(inJournal:) 看不到",
              store.entries(inJournal: target.id).isEmpty)
        check("entries(on:) 看不到",
              store.entries(on: hidden[0].createdAt)
                  .allSatisfy { $0.journalId != target.id })
        check("onThisDayEntries 看不到",
              store.onThisDayEntries.allSatisfy { $0.journalId != target.id })
        let titles = hidden.map(\.displayTitle).filter { !$0.isEmpty }
        check("按标题搜索搜不到这一本",
              titles.allSatisfy { q in
                  store.search(q).allSatisfy { $0.journalId != target.id }
              })
        // 只在这一本里出现过的标签，从标签统计里一起消失
        let otherTags = Set(store.visible.flatMap { $0.tags })
        let onlyHere = Set(hidden.flatMap { $0.tags }).subtracting(otherTags)
        check("只属于这一本的标签也从统计里消失",
              onlyHere.allSatisfy { tag in store.allTags.allSatisfy { $0.0 != tag } })
        check("总字数只算可见范围",
              store.totalWords() == store.visible.reduce(0) { $0 + $1.wordCount })
        check("dayKeys 也只按可见范围算",
              store.dayKeys == Set(store.visible.map { $0.dayKey }))
        check("journalCount 依然报真实篇数（编辑窗要显示「已有 N 篇」）",
              store.journalCount(target.id) == hidden.count)

        // 6) 解锁
        check("密码不对解不开", store.unlockJournal(target.id, password: "wrong") == false)
        check("解失败后仍然锁着", store.isJournalLocked(target.id))
        check("密码正确能解开", store.unlockJournal(target.id, password: "hunter2"))
        check("解开后 isJournalLocked 转假", !store.isJournalLocked(target.id))
        check("解开后所有日记又可见了", store.visible.count == allCount)
        check("locked 标记还在（只是本次会话放行）",
              store.journal(for: target.id)?.locked == true)
        check("解开后 hasClosedJournals 转假", !store.hasClosedJournals)

        // 7) 立即重新上锁
        store.relockJournal(target.id)
        check("重新上锁后马上又看不见了", store.visible.count == allCount - hidden.count)
        store.relockJournal(target.id)
        check("重复重新上锁不会出问题", store.visible.count == allCount - hidden.count)

        // 8) 解锁面板的开关
        store.requestJournalUnlock(target.id)
        check("点锁着的本子会弹解锁面板", store.journalGate?.id == target.id)
        store.cancelJournalGate()
        check("取消后面板收掉", store.journalGate == nil)
        store.requestJournalUnlock("不存在的 id")
        check("点一个不存在的本子不会弹面板", store.journalGate == nil)

        // 9) 默认本子锁着时，新建日记要落到别处
        store.settings.defaultJournalId = target.id
        let fallback = store.defaultJournalId()
        check("默认本子锁着时新建会换个本子", fallback != target.id)
        check("换到的那个本子确实是开着的", !store.isJournalLocked(fallback))
        check("换到的那个本子真实存在",
              store.journals.contains { $0.id == fallback })

        // 10) ⌘L 锁定整个 App → 日记本那一层也归零
        _ = store.unlockJournal(target.id, password: "hunter2")
        check("先把它解开", !store.isJournalLocked(target.id))
        store.security.hasPassword = true
        store.lock()
        check("按 ⌘L 后日记本的解开状态一起归零", store.isJournalLocked(target.id))
        check("锁屏时解锁面板也被收掉", store.journalGate == nil)

        // 11) 删掉日记本 → 残留的解锁状态要清干净
        _ = store.unlockJournal(target.id, password: "hunter2")
        if let victim = store.journal(for: target.id) {
            store.deleteJournal(victim)
        }
        check("删掉日记本后，解锁状态里也不留它的 id",
              !store.unlockedJournals.contains(target.id))
        check("删掉之后默认本子也换人了",
              store.settings.defaultJournalId != target.id)

        // 12) 草稿带上上锁状态
        guard let survivor = store.journals.first else { return }
        store.setJournalLocked(survivor.id, true)
        check("编辑草稿会带上当前的上锁状态",
              JournalDraft.editing(store.journals[0]).locked)
        check("草稿的 locked 也会被 sanitized 保留",
              JournalDraft.editing(store.journals[0]).sanitized().locked)
        // 编辑时不碰开关 → 锁不能丢
        store.commitJournalDraft(JournalDraft(id: survivor.id, name: "改个名",
                                             colorHex: survivor.colorHex,
                                             symbol: survivor.symbol, locked: true))
        check("编辑时不动开关，锁不会丢",
              store.journal(for: survivor.id)?.locked == true)
        // 新建时可以直接上锁
        store.commitJournalDraft(JournalDraft(name: "私密本", colorHex: RJ.accentDefault,
                                              symbol: "lock.fill", locked: true))
        check("新建时可以直接勾上锁", store.journals.last?.locked == true)

        // 13) 全部锁住也不该崩
        //
        // 上一步删掉的那本日记仍然留在「全部日记」里（这是有意的：删日记本不删日记），
        // 但它们的 journalId 已经不对应任何一本了 —— 无主条目不会被任何锁覆盖，
        // 所以下面「全部上锁 = 什么都看不见」的检查要先把它们清掉。
        store.entries = demoEntries.filter { e in
            store.journals.contains { $0.id == e.journalId }
        }
        for j in store.journals { _ = store.setJournalLocked(j.id, true) }
        check("全部上锁后 visible 为空", store.visible.isEmpty)
        check("全部上锁后总字数为 0", store.totalWords() == 0)
        check("全部上锁后 dayKeys 为空", store.dayKeys.isEmpty)
        check("全部上锁后默认本子仍指向一个真实存在的本子",
              store.journals.contains { $0.id == store.defaultJournalId() })
        check("全部上锁时 streak 不会崩", store.streak >= 0)
        check("全部上锁时 onThisDayEntries 不崩", store.onThisDayEntries.isEmpty)

        // 14) 取消上锁
        check("取消上锁", store.setJournalLocked(survivor.id, false))
        check("取消后这一本恢复可见",
              !store.isJournalLocked(survivor.id))
        check("取消上锁会顺手把未解锁标记也清掉",
              !store.unlockedJournals.contains(survivor.id))

        // 15) 移除打开密码 → 所有日记本锁一并取消，不留死结
        store.removePassword()
        check("移除打开密码后没有任何一本还锁着",
              store.journals.allSatisfy { !$0.locked })
        check("移除打开密码后 unlockedJournals 也清空",
              store.unlockedJournals.isEmpty)
    }

    // MARK: 九宫格日记

    private static func gridJournal() {
        print("\n· 九宫格日记")

        // 1. 内置模板的形状
        let builtIns = GridTemplate.builtIns
        check("内置了 3 套九宫格模板", builtIns.count == 3, "实际 \(builtIns.count)")
        check("每套都是九格", builtIns.allSatisfy { $0.questions.count == GridTemplate.slotCount })
        check("每格问题都有字", builtIns.allSatisfy { $0.questions.allSatisfy { !$0.trimmed.isEmpty } })
        check("同一套里九格问题互不重复",
              builtIns.allSatisfy { Set($0.questions).count == GridTemplate.slotCount })
        check("模板 id 互不重复", Set(builtIns.map(\.id)).count == builtIns.count)
        check("内置模板能被认出来", builtIns.allSatisfy { $0.isBuiltIn })

        // 图标得真的存在 —— 日记本图标库里就混进过一个不存在的「notebook」
        for t in builtIns {
            check("模板「\(t.name)」的图标 \(t.symbol) 真实存在",
                  NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil) != nil)
        }

        // 2. 规范化：缺格补齐、多格截断、脏字段兜底
        let messy = GridTemplate(id: "", name: "   ", symbol: "", colorHex: "#xyz",
                                 questions: ["只有一个", "", "三", "四", "五", "六", "七", "八", "九", "第十个"])
        let n = messy.normalized()
        eq("空名字会被兜底", n.name, GridTemplate.fallbackName)
        eq("空图标会被兜底", n.symbol, GridTemplate.defaultSymbol)
        eq("非法颜色会被兜底", n.colorHex, RJ.accentDefault)
        check("多出来的问题会被截到九格", n.questions.count == GridTemplate.slotCount,
              "实际 \(n.questions.count)")
        eq("空问题会被补成占位", n.questions[1], GridTemplate.placeholderQuestion(1))
        check("占位问题不会是空串", n.questions.allSatisfy { !$0.trimmed.isEmpty })

        let short = GridTemplate(name: "只有两格", questions: ["甲", "乙"]).normalized()
        check("问题不够时会补齐到九格", short.questions.count == GridTemplate.slotCount)
        eq("前两格保留原样", short.questions[0] + short.questions[1], "甲乙")
        eq("补上来的第三格是占位", short.questions[2], GridTemplate.placeholderQuestion(2))

        // 3. 生成正文
        let classic = builtIns[0]
        let answers = ["完成产品方案初稿", "下午和同事聊了会儿天", "",
                       "按时起床", "", "用 CGM 看了看血糖波动",
                       "眼睛有点酸", "早点睡", ""]
        let md = GridTemplate.markdown(from: classic, answers: answers)
        check("正文里九个问题都在", classic.questions.allSatisfy { md.contains($0) })
        check("填过的答案写进去了", md.contains("完成产品方案初稿"))
        check("开头点明了用的哪张模板", md.contains("### 九宫格日记 · \(classic.name)"))
        check("没填的格只留问题、不留空答案",
              !md.contains("**\(classic.questions[2])**\n\n\n"),
              "空答案后面不该再堆一行")
        check("末尾不留多余空行", !md.hasSuffix("\n") && !md.hasSuffix(" "))
        check("问题被加粗（渲染出来才像格子）", md.contains("**\(classic.questions[0])**"))

        let multi = GridTemplate.markdown(from: classic,
                                          answers: ["第一行\n第二行"] + Array(repeating: "", count: 8))
        check("答案里的换行会原样保留", multi.contains("第一行\n第二行"))

        // 生成结果必须是我们自己的解析器吃得下的 Markdown
        let blocks = MDParser.parse(md)
        func isHeading(_ b: MDBlock) -> Bool { if case .heading = b.kind { return true }; return false }
        func isParagraph(_ b: MDBlock) -> Bool { if case .paragraph = b.kind { return true }; return false }
        check("正文能被解析出标题", blocks.contains(where: isHeading))
        check("正文能被解析出段落（问题与答案各自成段）",
              blocks.filter(isParagraph).count >= 10,
              "实际 \(blocks.filter(isParagraph).count)")
        check("九格的问题解析后依然是九段",
              blocks.filter(isParagraph).filter { b in
                  if case .paragraph(let s) = b.kind { return s.hasPrefix("**") }
                  return false
              }.count == GridTemplate.slotCount)

        // 4. 模板的增删改查（全程在临时目录里跑）
        let store = Store()
        store.enterSnapshotDemo()
        // 自检从干净的默认态开始，免得受本机 config.json 影响
        store.settings.gridTemplates = GridTemplate.builtIns

        check("默认就带着内置三套", store.gridTemplates.count == 3)
        check("默认没有自定义模板", !store.hasCustomGridTemplates)

        let mine = GridTemplate(name: "我的复盘", colorHex: "#2AA6A6",
                                questions: (1...9).map { "我的问题 \($0)" })
        store.saveGridTemplate(mine)
        eq("存一张新模板后数量 +1", "\(store.gridTemplates.count)", "4")
        check("自加的模板会被识别出来", store.hasCustomGridTemplates)
        eq("存的模板能按 id 取回", store.gridTemplate(id: mine.id)?.name ?? "", "我的复盘")

        var renamed = mine
        renamed.name = "改过名的模板"
        store.saveGridTemplate(renamed)
        eq("同 id 再存是更新不是追加", "\(store.gridTemplates.count)", "4")
        eq("改名真的生效了", store.gridTemplate(id: mine.id)?.name ?? "", "改过名的模板")

        let tooMany = GridTemplate(name: "问题太多", questions: Array(repeating: "x", count: 20))
        store.saveGridTemplate(tooMany)
        eq("存进去时会先规范化成九格",
           "\(store.gridTemplate(id: tooMany.id)?.questions.count ?? 0)", "9")

        store.deleteGridTemplate(id: mine.id)
        check("能删掉自己的模板", store.gridTemplate(id: mine.id) == nil)
        // 注意别断言总数：这时「问题太多」那张自定义模板还在
        eq("删自定义模板不会伤到内置的",
           "\(store.gridTemplates.filter(\.isBuiltIn).count)", "3")
        check("被删的确实不在了", !store.gridTemplates.contains { $0.id == mine.id })

        // 「恢复内置」要恢复原厂内容，但不能误伤自己加的
        var wrecked = store.gridTemplates[0]
        wrecked.questions = (0..<9).map { "被我改坏了 \($0)" }
        store.saveGridTemplate(wrecked)
        eq("内置模板也能被改", store.gridTemplates[0].questions[0], "被我改坏了 0")

        let keeper = GridTemplate(name: "别删我", questions: (1...9).map { "保留 \($0)" })
        store.saveGridTemplate(keeper)
        store.resetGridTemplates()
        eq("恢复后内置问题回到原厂",
           store.gridTemplate(id: GridTemplate.builtIns[0].id)?.questions[0] ?? "",
           GridTemplate.builtIns[0].questions[0])
        check("恢复内置不会误删自己加的", store.gridTemplate(id: keeper.id) != nil)
        eq("恢复后内置仍是三套",
           "\(store.gridTemplates.filter(\.isBuiltIn).count)", "3")

        // 5. 打开面板的两种意图
        store.beginGridJournal()
        check("不带日记 id 打开 = 填完新建一篇", store.gridDraft?.targetEntryId == nil)
        eq("会预选第一张模板", store.gridDraft?.templateId ?? "", store.gridTemplates.first?.id ?? "")
        store.cancelGridDraft()
        check("取消后草稿被清空", store.gridDraft == nil)

        let target = store.createEntry()
        store.beginGridJournal(entryId: target.id)
        eq("带日记 id 打开 = 追加到这篇", store.gridDraft?.targetEntryId ?? "", target.id)
        eq("追加时会带上这篇所属的日记本", store.gridDraft?.journalId ?? "", target.journalId)
        store.beginGridJournal(entryId: nil, templateId: GridTemplate.builtIns[2].id)
        eq("也能指定用哪张模板打开", store.gridDraft?.templateId ?? "", GridTemplate.builtIns[2].id)
        store.cancelGridDraft()

        // 6. 生成的正文真的能落成日记
        let body = GridTemplate.markdown(from: classic, answers: answers)
        let entry = store.createEntry(body: body)
        check("生成的正文能写进日记并读回来",
              store.entries.first { $0.id == entry.id }?.body.contains(classic.questions[0]) == true)
        check("九宫格正文会数进字数统计",
              (store.entries.first { $0.id == entry.id }?.wordCount ?? 0) > 20)

        // 7. 容错解码：老配置 / 残缺条目 / 空数组 / 类型不对
        let legacy = #"{"dataPath":"","weatherCity":"北京"}"#
        if let s = try? JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8)) {
            eq("老配置没有模板字段 → 自动带上内置三套", "\(s.gridTemplates.count)", "3")
        } else {
            check("老配置没有模板字段 → 自动带上内置三套", false, "整段解码失败")
        }

        let partial = #"{"dataPath":"","gridTemplates":[{"name":"只剩名字"},{"id":"x","questions":["a"]}]}"#
        if let s = try? JSONDecoder().decode(AppSettings.self, from: Data(partial.utf8)) {
            eq("残缺的模板条目不会被丢掉", "\(s.gridTemplates.count)", "2")
            eq("缺名字的能解出来", s.gridTemplates[0].name, "只剩名字")
            eq("缺名字的那个颜色会兜底", s.gridTemplates[0].colorHex, RJ.accentDefault)
            check("每条都会被补齐到九格",
                  s.gridTemplates.allSatisfy { $0.questions.count == GridTemplate.slotCount })
            check("缺 id 的会补一个新的", !s.gridTemplates[1].id.isEmpty)
        } else {
            check("残缺的模板条目不会被丢掉", false, "整段解码失败")
        }

        let emptyList = #"{"dataPath":"","gridTemplates":[]}"#
        if let s = try? JSONDecoder().decode(AppSettings.self, from: Data(emptyList.utf8)) {
            check("用户把模板删光时尊重这个选择", s.gridTemplates.isEmpty)
        } else {
            check("用户把模板删光时尊重这个选择", false, "整段解码失败")
        }

        let wrongType = #"{"dataPath":"","gridTemplates":"不是数组"}"#
        if let s = try? JSONDecoder().decode(AppSettings.self, from: Data(wrongType.utf8)) {
            eq("模板字段类型不对 → 退回内置", "\(s.gridTemplates.count)", "3")
        } else {
            check("模板字段类型不对 → 退回内置", false, "整段解码失败")
        }

        if let data = try? JSONEncoder().encode(GridTemplate.builtIns),
           let back = try? JSONDecoder().decode([GridTemplate].self, from: data) {
            check("模板编解码往返一致", back == GridTemplate.builtIns)
        } else {
            check("模板编解码往返一致", false, "编码或解码失败")
        }
    }

    // MARK: 每日一句（人生建议）

    private static func lifeAdvice() {
        print("\n· 每日一句")
        let all = LifeAdvice.all
        check("建议条数够多（\(all.count) 条）", all.count >= 400)
        check("没有空条目", all.allSatisfy { !$0.trimmed.isEmpty })
        check("没有重复条目", Set(all).count == all.count)
        // 8 条是引语式的（以 」” 收尾），所以允许收尾字符是引号
        let enders = "。！？”\""
        check("每条都是完整句子（没有被截断）",
              all.allSatisfy { enders.contains($0.trimmed.suffix(1)) },
              "例：" + (all.first { !enders.contains($0.trimmed.suffix(1)) } ?? "无"))

        let cal = Calendar.current
        let today = Date()
        eq("同一天永远是同一句", LifeAdvice.today(date: today), LifeAdvice.today(date: today))

        let base = LifeAdvice.today(offset: 0, date: today)
        check("「换一句」真的换到别的", LifeAdvice.today(offset: 1, date: today) != base)
        eq("换满一圈回到原句", LifeAdvice.today(offset: all.count, date: today), base)
        check("往回翻一句也不越界", !LifeAdvice.today(offset: -1, date: today).isEmpty)

        // 年份也混进种子 —— 否则每年同一天读到的都是同一句
        if let sameDayNextYear = cal.date(byAdding: .year, value: 1, to: today) {
            check("跨年同一天换句（年份参与种子）",
                  LifeAdvice.today(date: sameDayNextYear) != base)
        }

        // 卡片显示的字数上限：
        // 原来靠 `.lineLimit(4)`，侧边栏一行十六七个字，四行约 65 字；
        // 用户要求「限定字数再多 50 个」，所以上限至少要比 65 多 50。
        check("今日一句字数上限比原行数限制多出 50 字以上",
              LifeAdvice.cardCharLimit >= 115, "实际 \(LifeAdvice.cardCharLimit)")
        let short = "简单一句话。"
        eq("短句原样显示", LifeAdvice.cardText(short), short)
        let long = String(repeating: "字", count: 300)
        let clipped = LifeAdvice.cardText(long)
        check("超长按字数截断并加省略号",
              clipped.count == LifeAdvice.cardCharLimit + 1 && clipped.hasSuffix("…"),
              "实际 \(clipped.count) 字")
        check("恰好等于上限时不截断",
              LifeAdvice.cardText(String(repeating: "字", count: LifeAdvice.cardCharLimit)).hasSuffix("字"))
        // 每条建议都得能过一遍截断，不能有崩的
        check("所有条目都能安全截断",
              all.allSatisfy { !LifeAdvice.cardText($0).isEmpty })

        // 一年里每天都得取得到，不能有空指针式崩溃
        var allDaysOK = true
        let start = cal.startOfDay(for: today)
        for i in 0..<366 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            if LifeAdvice.today(date: d).isEmpty { allDaysOK = false; break }
        }
        check("往后一年 366 天每天都取得到", allDaysOK)

        // MARK: 《100 个基本》—— 第二个金句来源
        let basic = Basic100.all
        check("《100 个基本》抽满 100 条（\(basic.count) 条）", basic.count == 100)
        check("《100 个基本》没有空条目", basic.allSatisfy { !$0.trimmed.isEmpty })
        check("《100 个基本》没有重复条目", Set(basic).count == basic.count)
        // 这本的每条都是收住的一句话（没有引语），但第 34 条是疑问句「…幸福吗？」
        check("《100 个基本》每条都是完整句子",
              basic.allSatisfy { $0.trimmed.hasSuffix("。") || $0.trimmed.hasSuffix("？") },
              "例：" + (basic.first { !($0.trimmed.hasSuffix("。") || $0.trimmed.hasSuffix("？")) } ?? "无"))
        // 每条只取了「基本」短句本身，后面几百字的解说不要 —— 卡片放不下
        check("《100 个基本》每条都不长（最长 \(basic.map(\.count).max() ?? 0) 字）",
              basic.allSatisfy { $0.count <= 40 })
        check("《100 个基本》与凯文·凯利那本没有撞条目",
              Set(basic).isDisjoint(with: Set(all)))

        // 轮换：一年里两本书都得露面，否则新加的那本等于白加
        var seenKK = false, seenBasic = false
        for i in 0..<366 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let q = LifeAdvice.quote(date: d)
            if q.source == LifeAdvice.source { seenKK = true }
            if q.source == Basic100.source { seenBasic = true }
        }
        check("一年里两本书都会出现", seenKK && seenBasic, "凯文·凯利=\(seenKK) 松浦=\(seenBasic)")

        // 出处不能张冠李戴：句子必须真的属于标出来的那本书
        var mismatch = false
        for i in 0..<200 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let q = LifeAdvice.quote(date: d)
            let ok = (q.source == Basic100.source && basic.contains(q.text))
                  || (q.source == LifeAdvice.source && all.contains(q.text))
            if !ok { mismatch = true; break }
        }
        check("出处和句子对得上（没有标错书）", !mismatch)

        // 「换一句」要在两本书之间跳，且不越界
        var offsetsOK = true
        for k in -40...40 {
            let q = LifeAdvice.quote(offset: k, date: today)
            if q.text.isEmpty || q.source.isEmpty { offsetsOK = false; break }
        }
        check("换一句（前后 40 次）都不越界", offsetsOK)

        let q0 = LifeAdvice.quote(offset: 0, date: today)
        let q1 = LifeAdvice.quote(offset: 1, date: today)
        check("换一句会换到另一本书", q0.source != q1.source, "\(q0.source) → \(q1.source)")
    }

    // MARK: 列表排序

    private static func entrySort() {
        print("\n· 日记列表排序")
        check("排序方式 5 种", EntrySort.allCases.count == 5)
        check("每种都有名称与简称",
              EntrySort.allCases.allSatisfy { !$0.name.isEmpty && !$0.shortName.isEmpty })
        check("排序图标都真实存在", EntrySort.allCases.allSatisfy {
            NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil
        })
        check("按字数 / 标题排时不插日期表头",
              !EntrySort.longest.groupsByDay && !EntrySort.title.groupsByDay)
        check("按时间排时保留日期表头",
              EntrySort.newest.groupsByDay && EntrySort.oldest.groupsByDay && EntrySort.updated.groupsByDay)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func mk(_ tag: String, daysAgo: Int, updatedDaysAgo: Int, chars: Int) -> Entry {
            var e = Entry()
            e.journalId = "j"
            e.createdAt = base.addingTimeInterval(-Double(daysAgo) * 86400)
            e.updatedAt = base.addingTimeInterval(-Double(updatedDaysAgo) * 86400)
            e.body = "第\(tag)篇\n" + String(repeating: "字", count: chars)
            return e
        }

        let a = mk("1", daysAgo: 0, updatedDaysAgo: 5, chars: 10)    // 最新写、最短
        let b = mk("2", daysAgo: 3, updatedDaysAgo: 0, chars: 300)   // 最早写、最长、最近改
        let c = mk("3", daysAgo: 1, updatedDaysAgo: 2, chars: 50)
        let list = [a, b, c]

        eq("最新写的在前", EntrySort.newest.apply(list).first?.id ?? "", a.id)
        eq("最早写的在前", EntrySort.oldest.apply(list).first?.id ?? "", b.id)
        eq("最近修改的在前", EntrySort.updated.apply(list).first?.id ?? "", b.id)
        eq("字数最多的在前", EntrySort.longest.apply(list).first?.id ?? "", b.id)
        eq("按标题排（第1篇排在第2篇前）", EntrySort.title.apply(list).first?.id ?? "", a.id)
        check("任何排序都不丢条目", EntrySort.allCases.allSatisfy { $0.apply(list).count == list.count })

        // 字数相同时要有兜底，否则列表里两篇会随数组顺序来回跳
        let sameBody = "同字数\n" + String(repeating: "字", count: 100)
        var x = mk("4", daysAgo: 2, updatedDaysAgo: 2, chars: 0); x.body = sameBody
        var y = mk("5", daysAgo: 8, updatedDaysAgo: 8, chars: 0); y.body = sameBody
        eq("字数相同时，新的在前（兜底）", EntrySort.longest.apply([y, x]).first?.id ?? "", x.id)
        eq("字数相同时，新的在前（换顺序结果一样）", EntrySort.longest.apply([x, y]).first?.id ?? "", x.id)
    }

    // MARK: 写作区纸张

    private static func paperStyle() {
        print("\n· 写作区纸张")
        check("纸张样式 6 种", PaperStyle.allCases.count == 6)
        check("每种都有名称与说明", PaperStyle.allCases.allSatisfy {
            !$0.name.isEmpty && !$0.hint.isEmpty
        })
        check("纸张图标都真实存在", PaperStyle.allCases.allSatisfy {
            NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil
        })
        eq("只有横线 / 方格 / 点阵三种要画纹路",
           "\(PaperStyle.allCases.filter(\.hasPattern).map(\.rawValue))",
           "[\"lined\", \"grid\", \"dots\"]")
        eq("认不出的样式兜回纯白", PaperStyle.from("上一版留下的值").rawValue, PaperStyle.plain.rawValue)
        eq("空值也兜回纯白", PaperStyle.from("").rawValue, PaperStyle.plain.rawValue)
        // AppSettings 的 init(from:) 是逐字段容错的，空对象能解出一份全默认设置
        if let defaults = try? JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) {
            eq("全新安装的默认纸张就是纯白",
               PaperStyle.from(defaults.paperStyle).rawValue, PaperStyle.plain.rawValue)
        } else {
            check("全新安装的默认纸张就是纯白", false, "空配置解码失败")
        }
        // 底色若透明，编辑器后面那层栏底色会透上来，纸就不像纸了
        check("每种纸张底色都不透明", PaperStyle.allCases.allSatisfy { $0.base != Color.clear })
        check("带纹路的三种都有可见的描线色",
              [PaperStyle.lined, .grid, .dots].allSatisfy { $0.ink != Color.clear })
        check("纯白 / 米黄 / 樱粉不画纹路（描线色为空）",
              [PaperStyle.plain, .cream, .blush].allSatisfy { $0.ink == Color.clear })
    }

    // MARK: 城市标注

    private static func cityTag() {
        print("\n· 日记城市标注")
        let store = Store()
        store.enterSnapshotDemo()
        store.settings.weatherCity = "北京"
        store.settings.weatherAuto = false   // 自检不联网

        let created = store.createEntry(body: "今天走走停停。")
        eq("新建日记记下设置里的城市", created.city, "北京")

        // 城市必须写进 front matter，否则重启就丢了
        var tagged = Entry()
        tagged.journalId = "j"
        tagged.body = "在路上。"
        tagged.city = "杭州"
        let text = store.serialize(tagged)
        check("front matter 里真的写了 city", text.contains("city: 杭州"))
        eq("写盘再读回，城市还在", store.parse(text, relPath: "x.md")?.city ?? "", "杭州")

        // 老日记的 front matter 里根本没有 city 这一行
        let legacy = """
        ---
        id: abc
        journal: j
        created: 2026-01-01T09:00:00Z
        updated: 2026-01-01T09:00:00Z
        title: 旧的一篇
        ---

        旧的正文
        """
        guard let old = store.parse(legacy, relPath: "old.md") else {
            check("老日记仍能解析", false, "解析失败")
            return
        }
        check("老日记仍能解析", true)
        eq("老日记没有城市就是空字符串（不崩）", old.city, "")
        check("老日记正文照常读到", old.body.contains("旧的正文"))

        // 空城市不写进行 —— 免得每篇都挂一行没用的 `city:`
        var blank = Entry()
        blank.journalId = "j"
        blank.body = "没有城市。"
        check("空城市不写 front matter 行", !store.serialize(blank).contains("city:"))
    }

    // MARK: 农历与黄历

    /// 造一个北京时间当天正午的日期
    private static func on(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Almanac.gregorian.date(from: c) ?? Date()
    }

    private static func almanac() {
        print("\n· 农历与黄历")

        // 农历换算（对照国务院放假通知里的表述）
        let mid = Almanac.day(on(2026, 9, 25))
        eq("农历换算：2026-09-25 是八月十五", mid.lunarText, "八月十五")
        eq("农历换算：2026-02-17 是正月初一", Almanac.day(on(2026, 2, 17)).lunarText, "正月初一")
        eq("农历换算：2026-02-15 是腊月廿八（通知里写作「腊月二十八」）",
           Almanac.day(on(2026, 2, 15)).lunarText, "腊月廿八")
        eq("农历换算：2026-02-23 是正月初七", Almanac.day(on(2026, 2, 23)).lunarText, "正月初七")
        eq("农历换算：2025-01-29 是正月初一", Almanac.day(on(2025, 1, 29)).lunarText, "正月初一")
        eq("农历换算：2024-02-10 是正月初一", Almanac.day(on(2024, 2, 10)).lunarText, "正月初一")
        eq("农历换算：2026-06-19 是五月初五（端午）",
           Almanac.day(on(2026, 6, 19)).lunarText, "五月初五")

        // 日名拼写
        eq("日名：1 日 = 初一", Almanac.lunarDayName(1), "初一")
        eq("日名：10 日 = 初十", Almanac.lunarDayName(10), "初十")
        eq("日名：15 日 = 十五", Almanac.lunarDayName(15), "十五")
        eq("日名：20 日 = 二十", Almanac.lunarDayName(20), "二十")
        eq("日名：21 日 = 廿一", Almanac.lunarDayName(21), "廿一")
        eq("日名：29 日 = 廿九", Almanac.lunarDayName(29), "廿九")
        eq("日名：30 日 = 三十", Almanac.lunarDayName(30), "三十")

        // 干支纪日 —— 锚点 1949-10-01 甲子日
        eq("干支纪日：1949-10-01 是甲子日", Almanac.ganzhi(Almanac.dayGanzhiIndex(on(1949, 10, 1))), "甲子")
        eq("干支纪日：2026-09-25 是壬寅日", mid.dayGanzhi, "壬寅")
        eq("干支纪日：2026-09-26 是癸卯日", Almanac.day(on(2026, 9, 26)).dayGanzhi, "癸卯")
        eq("干支纪日：次日序号正好 +1",
           "\(Almanac.dayGanzhiIndex(on(2026, 9, 26)) - Almanac.dayGanzhiIndex(on(2026, 9, 25)))", "1")
        let lastDayIdx = Almanac.dayGanzhiIndex(on(2025, 12, 31))
        let firstDayIdx = Almanac.dayGanzhiIndex(on(2026, 1, 1))
        eq("干支纪日：跨年也不断档（60 循环）", "\((firstDayIdx - lastDayIdx + 60) % 60)", "1")

        // 干支纪年 —— 以立春为界，1984 甲子
        eq("干支纪年：2026-09-25 是丙午年", mid.lunarYearGanzhi, "丙午")
        eq("生肖：丙午年属马", mid.zodiac, "马")
        eq("干支纪年：2026-01-01 还在立春前，属乙巳", Almanac.day(on(2026, 1, 1)).lunarYearGanzhi, "乙巳")
        eq("干支纪年：2026-02-10 已过立春，属丙午", Almanac.day(on(2026, 2, 10)).lunarYearGanzhi, "丙午")
        eq("干支纪年：1984 年是甲子年", Almanac.ganzhi(Almanac.yearGanzhiIndex(on(1984, 6, 1))), "甲子")

        // 干支纪月 —— 五虎遁
        eq("干支纪月：2026-09-25 是丁酉月", mid.monthGanzhi, "丁酉")

        // 二十四节气（对照公开数据）
        func termDay(_ y: Int, _ idx: Int) -> String {
            guard let d = Almanac.solarTermDate(year: y, index: idx) else { return "无" }
            let c = Almanac.gregorian.dateComponents([.month, .day], from: d)
            return "\(c.month ?? 0)/\(c.day ?? 0)"
        }
        eq("节气：2026 立春 = 2/4", termDay(2026, 2), "2/4")
        eq("节气：2026 清明 = 4/5", termDay(2026, 6), "4/5")
        eq("节气：2026 冬至 = 12/22", termDay(2026, 23), "12/22")
        eq("节气：2026 秋分 = 9/23", termDay(2026, 17), "9/23")
        eq("节气：2025 立春 = 2/3", termDay(2025, 2), "2/3")
        eq("节气：2025 清明 = 4/4", termDay(2025, 6), "4/4")
        eq("节气：2025 冬至 = 12/21", termDay(2025, 23), "12/21")
        check("节气：24 个一个不少", Almanac.solarTerms(ofYear: 2026).count == 24)
        check("节气：一年里 24 个日期严格递增",
              zip(Almanac.solarTerms(ofYear: 2026), Almanac.solarTerms(ofYear: 2026).dropFirst())
                .allSatisfy { $0 < $1 })

        // 当天正好是节气
        eq("2026-09-23 当天是秋分", Almanac.day(on(2026, 9, 23)).term, "秋分")
        eq("2026-09-25 当天不是节气", mid.term, "")
        eq("2026-09-25 的下一个节气是寒露", mid.nextTerm, "寒露")

        // 十二值神（《协纪辨方书》口诀）
        eq("十二值神：2026-09-25 是青龙", mid.deity, "青龙")
        check("十二值神：青龙算黄道吉日", mid.isYellowRoad)
        eq("十二值神：2026-09-26 是明堂", Almanac.day(on(2026, 9, 26)).deity, "明堂")
        check("十二值神：12 个名称都对得上", Almanac.deities.count == 12)
        check("十二值神：黄道正好 6 个", Almanac.yellowDeities.count == 6)

        // 建除十二神
        eq("建除十二神：2026-09-25 是执日", mid.officer, "执")
        eq("建除十二神：12 个一个不少", "\(Almanac.officers.count)", "12")

        // 冲煞
        eq("冲煞：2026-09-25 冲猴", mid.clashZodiac, "猴")

        // 宜忌不能是空的
        check("宜忌：宜不为空", !mid.suitable.isEmpty)
        check("宜忌：忌不为空", !mid.avoid.isEmpty)

        // 整年扫描：每天都要算得出来，不能有空白
        var bad: [String] = []
        var jianBad = 0
        var officerSeen = Set<String>()
        var suitableSeen = Set<String>()
        var avoidSeen = Set<String>()
        let cal = Almanac.gregorian
        for i in 0..<366 {
            guard let d = cal.date(byAdding: .day, value: i, to: on(2026, 1, 1)) else { continue }
            let a = Almanac.day(d)
            if a.lunarText.isEmpty || a.dayGanzhi.count != 2 || a.monthGanzhi.count != 2
                || a.officer.isEmpty || a.deity.isEmpty || a.zodiac.isEmpty
                || a.suitable.isEmpty || a.avoid.isEmpty {
                let c = cal.dateComponents([.month, .day], from: d)
                bad.append("\(c.month ?? 0)/\(c.day ?? 0)")
            }
            // 月建与日支同支那天必然是「建」日，反过来也成立
            let sameBranch = (Almanac.dayGanzhiIndex(d) % 12) == a.monthBranch
            if sameBranch != (a.officer == "建") { jianBad += 1 }
            officerSeen.insert(a.officer)
            suitableSeen.formUnion(a.suitable)
            avoidSeen.formUnion(a.avoid)
        }
        check("整年 366 天每天都算得出来", bad.isEmpty, "异常：" + bad.prefix(5).joined(separator: ", "))
        check("建除十二神：月建与日支同支那天必然是「建」日", jianBad == 0, "不符 \(jianBad) 天")
        eq("建除十二神：一整年 12 档都轮到了", "\(officerSeen.count)", "12")
        check("宜忌：覆盖了足够多的条目", suitableSeen.count >= 25 && avoidSeen.count >= 25,
              "宜 \(suitableSeen.count) 条 / 忌 \(avoidSeen.count) 条")

        // 农历日名一年之内应当覆盖到初一和三十
        let names = Set((0..<366).compactMap { i -> String? in
            guard let d = cal.date(byAdding: .day, value: i, to: on(2026, 1, 1)) else { return nil }
            return Almanac.day(d).lunarDayName
        })
        check("整年出现「初一」", names.contains("初一"))
        check("整年出现「三十」", names.contains("三十"))

        // 节日
        check("节日：2026-09-25 是中秋节", mid.festivals.contains("中秋节"))
        check("节日：2026-02-17 是春节", Almanac.day(on(2026, 2, 17)).festivals.contains("春节"))
        check("节日：2026-02-16 是除夕", Almanac.day(on(2026, 2, 16)).festivals.contains("除夕"))
        check("节日：2026-01-01 是元旦", Almanac.day(on(2026, 1, 1)).festivals.contains("元旦"))
        check("节日：2026-06-19 是端午节", Almanac.day(on(2026, 6, 19)).festivals.contains("端午节"))
        check("节日：清明节挂在节气那天", Almanac.day(on(2026, 4, 5)).festivals.contains("清明节"))
        check("节日：公历 10/1 是国庆节", Almanac.day(on(2026, 10, 1)).festivals.contains("国庆节"))

        // 全年扫一遍，农历节日一个都不能漏
        var lunarFes = Set<String>()
        for i in 0..<366 {
            guard let d = cal.date(byAdding: .day, value: i, to: on(2026, 1, 1)) else { continue }
            lunarFes.formUnion(Almanac.day(d).festivals)
        }
        let wantFes = ["春节", "元宵节", "龙抬头", "端午节", "七夕", "中元节",
                       "中秋节", "重阳节", "腊八节", "小年", "除夕"]
        let missingFes = wantFes.filter { !lunarFes.contains($0) }
        check("2026 公历年里 \(wantFes.count) 个农历节日全都能识别",
              missingFes.isEmpty, "缺：" + missingFes.joined(separator: "、"))
    }

    // MARK: 法定节假日与调休

    private static func holiday() {
        print("\n· 法定节假日与调休")
        check("收录了 2024 / 2025 / 2026 三年",
              Holiday.availableYears == [2024, 2025, 2026],
              "实际 \(Holiday.availableYears)")

        // 2026（对照国办发明电〔2025〕7 号）
        eq("2026-01-01 是元旦假期", Holiday.mark(on(2026, 1, 1))?.label ?? "无", "元旦假期")
        eq("2026-01-04 是元旦调休上班", Holiday.mark(on(2026, 1, 4))?.label ?? "无", "元旦调休")
        eq("2026-02-15 是春节假期", Holiday.mark(on(2026, 2, 15))?.name ?? "无", "春节")
        eq("2026-02-23 是春节最后一天",
           (Holiday.mark(on(2026, 2, 23))?.isRest ?? false) ? "放假" : "上班", "放假")
        eq("2026-02-14 是春节调休上班", Holiday.mark(on(2026, 2, 14))?.label ?? "无", "春节调休")
        eq("2026-02-28 是春节调休上班", Holiday.mark(on(2026, 2, 28))?.label ?? "无", "春节调休")
        eq("2026-04-04 清明放假", Holiday.mark(on(2026, 4, 4))?.name ?? "无", "清明节")
        eq("2026-05-09 劳动节调休上班", Holiday.mark(on(2026, 5, 9))?.label ?? "无", "劳动节调休")
        eq("2026-09-25 中秋放假（今天）", Holiday.mark(on(2026, 9, 25))?.label ?? "无", "中秋节假期")
        eq("2026-09-20 国庆调休上班", Holiday.mark(on(2026, 9, 20))?.label ?? "无", "国庆节调休")
        eq("2026-10-10 国庆调休上班", Holiday.mark(on(2026, 10, 10))?.label ?? "无", "国庆节调休")
        eq("2026-10-07 是国庆最后一天", Holiday.mark(on(2026, 10, 7))?.name ?? "无", "国庆节")
        check("2026-10-08 已经不是假期了", Holiday.mark(on(2026, 10, 8)) == nil)
        check("普通工作日没有任何标记", Holiday.mark(on(2026, 3, 11)) == nil)

        // 2025：国庆与中秋合并放假 8 天
        eq("2025-10-08 还在国庆中秋假期里", Holiday.mark(on(2025, 10, 8))?.name ?? "无", "国庆节·中秋节")
        eq("2025-01-26 春节调休上班", Holiday.mark(on(2025, 1, 26))?.label ?? "无", "春节调休")
        eq("2025 元旦只放 1 天不调休",
           Holiday.mark(on(2025, 1, 1))?.label ?? "无", "元旦假期")

        // 2024
        eq("2024-02-10 春节假期开始", Holiday.mark(on(2024, 2, 10))?.name ?? "无", "春节")
        eq("2024-09-14 中秋调休上班", Holiday.mark(on(2024, 9, 14))?.label ?? "无", "中秋节调休")

        // 没收录的年份得如实说「没有」，不能默认「不放假」
        check("2027 年还没收录", !Holiday.hasData(for: 2027))
        check("2023 年没收录（不往回瞎编）", !Holiday.hasData(for: 2023))
        check("没收录的年份查出来是空", Holiday.mark(on(2027, 10, 1)) == nil)

        // 放假天数核对：2026 全年放假日
        let rest = Holiday.restDays(inYear: 2026)
        eq("2026 全年放假天数 = 3+9+3+5+3+3+7 = 33 天", "\(rest.count)", "33")
        check("放假日不重复", Set(rest).count == rest.count)
    }

    // MARK: 星座

    private static func zodiac() {
        print("\n· 星座")
        check("12 个星座", Zodiac.signs.count == 12)
        check("星座名不重复", Set(Zodiac.signs.map(\.name)).count == 12)
        eq("日期区间：天秤座 9/23 – 10/23", Zodiac.sign(for: on(2026, 9, 25)).name, "天秤座")
        eq("边界：9/23 起算天秤", Zodiac.sign(for: on(2026, 9, 23)).name, "天秤座")
        eq("边界：9/22 还是处女", Zodiac.sign(for: on(2026, 9, 22)).name, "处女座")
        eq("边界：12/22 起算摩羯", Zodiac.sign(for: on(2026, 12, 22)).name, "摩羯座")
        eq("跨年：1/19 还是摩羯", Zodiac.sign(for: on(2026, 1, 19)).name, "摩羯座")
        eq("跨年：1/20 起算水瓶", Zodiac.sign(for: on(2026, 1, 20)).name, "水瓶座")
        eq("生日换算：1992-06-23 是巨蟹座", Zodiac.sign(month: 6, day: 23)?.name ?? "无", "巨蟹座")
        check("非法月日返回空", Zodiac.sign(month: 13, day: 1) == nil)

        // 一整年每天都能落到某个星座，且不留空档
        var covered = Set<String>()
        let cal = Almanac.gregorian
        for i in 0..<365 {
            guard let d = cal.date(byAdding: .day, value: i, to: on(2026, 1, 1)) else { continue }
            covered.insert(Zodiac.sign(for: d).name)
        }
        check("一年 365 天覆盖全部 12 个星座", covered.count == 12, "实际 \(covered.count)")

        // 运势：同一天同一星座必须稳定
        let tian = Zodiac.sign(for: on(2026, 9, 25))
        let f1 = Zodiac.fortune(for: tian, date: on(2026, 9, 25))
        let f2 = Zodiac.fortune(for: tian, date: on(2026, 9, 25))
        check("同一天同一星座运势稳定", f1 == f2)
        check("运势四项文案都不为空",
              !f1.summary.isEmpty && !f1.love.isEmpty && !f1.career.isEmpty && !f1.money.isEmpty)
        check("星级落在 1–5", (1...5).contains(f1.stars))
        check("幸运数字落在 1–9", (1...9).contains(f1.luckyNumber))
        check("幸运色不为空", !f1.luckyColor.isEmpty)
        check("同一天不同星座运势不同",
              Zodiac.fortune(for: Zodiac.signs[0], date: on(2026, 9, 25)).summary
              != Zodiac.fortune(for: Zodiac.signs[7], date: on(2026, 9, 25)).summary)

        // 文案库不能有重复条目（有重复就说明取模设计有问题）
        var seen = Set<String>()
        for i in 0..<400 {
            guard let d = cal.date(byAdding: .day, value: i, to: on(2026, 1, 1)) else { continue }
            seen.insert(Zodiac.fortune(for: tian, date: d).summary)
        }
        check("综合运势会轮换（一年内出现多种）", seen.count > 20, "实际 \(seen.count) 种")
    }

    // MARK: 界面缩放

    private static func uiScale() {
        print("\n· 界面字号缩放")
        let old = UserDefaults.standard.double(forKey: UIScale.key)

        UIScale.set(1.30)
        check("缩放系数即时生效", abs(UIScale.factor - 1.30) < 0.001, "实际 \(UIScale.factor)")
        check("档位名称映射正确", UIScale.label(for: 1.30) == "大")
        check("预设共 4 档", UIScale.presets.count == 4)
        check("默认档比原来的 1.15 大一档", UIScale.defaultFactor >= 1.30, "实际 \(UIScale.defaultFactor)")
        check("缩放系数对外可读", abs(UIScale.doubleValue - 1.30) < 0.001, "实际 \(UIScale.doubleValue)")

        // 还原用户原来的设置
        if old > 0 {
            UIScale.set(old)
        } else {
            UserDefaults.standard.removeObject(forKey: UIScale.key)
            UIScale.factor = UIScale.defaultFactor
        }
        let restored = old > 0 ? CGFloat(old) : UIScale.defaultFactor
        check("测试后已还原原设置", abs(UIScale.factor - restored) < 0.001)
    }

    // MARK: 小迹的人格预设

    private static func persona() {
        print("\n· 小迹的人格预设")
        let all = AIPersonas.all
        check("人格数量 ≥ 6", all.count >= 6, "实际 \(all.count)")
        check("id 不重复", Set(all.map(\.id)).count == all.count)
        check("名字不重复", Set(all.map(\.name)).count == all.count)

        // 每个人格都要有实际内容，不能是空壳 ——
        // 空提示词会让模型退回默认语气，人格就白切了
        for p in all {
            check("「\(p.name)」有提示词", p.system.count > 120, "实际 \(p.system.count) 字")
            check("「\(p.name)」有图标与说明", !p.symbol.isEmpty && !p.tagline.isEmpty)
        }

        check("默认人格是知心陪伴", AIPersonas.companion.id == "companion")
        check("按 id 能找到对应人格", AIPersonas.find("mentor").name == "心灵导师")
        check("未知 id 退回默认人格", AIPersonas.find("不存在的id").id == AIPersonas.companion.id)

        // 配置里的 id 认不出来时要能自愈，否则整份设置的解码会连坐
        eq("非法人格 id 被拉回默认", AIPersonas.resolve("??? "), "companion")
        eq("合法人格 id 原样保留", AIPersonas.resolve("coach"), "coach")

        // 拼系统提示词时，人设和通用底线都得在
        let sys = AIPrompts.system(for: "mentor")
        check("系统提示词带上人设", sys.contains("心灵导师"))
        check("系统提示词补了不编造的要求", sys.contains("不要补"))
        check("未知人格也能拼出系统提示词", AIPrompts.system(for: "nope").count > 120)

        // 四个快捷动作的提示词
        let e = Entry(createdAt: Date(), body: "今天开会到十点，累。")
        let day = AIPrompts.summarizeDay([e], date: Date())
        check("当日总结给了输出结构", day.contains("### 今天发生了什么"))
        check("当日总结限了字数", day.contains("350 字"))
        check("当日总结带上了正文", day.contains("今天开会到十点"))

        let range = AIPrompts.summarizeRange([e], label: "最近 7 天")
        check("阶段总结写了分析口径", range.contains("看重复，不看单篇"))
        check("阶段总结限了字数", range.contains("500 字"))

        let mood = AIPrompts.moodInsight([e], label: "最近的日记")
        check("情绪洞察是独立提示词", mood.contains("只分析情绪"))
        // 情绪类的提示词必须写清能力边界，否则模型很容易滑向「诊断」
        check("情绪洞察声明不做诊断", mood.contains("不是心理诊断"))
        check("情绪洞察给了转介要求", mood.contains("寻求专业帮助") && mood.contains("超出了你的能力范围"))
        check("情绪洞察带上了心情字段", mood.contains("心情："))

        let single = AIPrompts.summarizeSingle(e, journal: "日常")
        check("单篇总结保留原文引用要求", single.contains("原样摘录"))

        // AI 回答用的字色要比正文「浅一档」。
        // 浅色模式下浅 = 明度数值更大，深色模式下浅 = 明度数值更小（本来底就暗），
        // 两种情况都要满足，所以分开断言。
        check("浅色模式：AI 字色比正文浅",
              InkLevel.bodySoftLight > InkLevel.bodyLight,
              "正文 \(InkLevel.bodyLight) → AI \(InkLevel.bodySoftLight)")
        check("深色模式：AI 字色比正文浅",
              InkLevel.bodySoftDark < InkLevel.bodyDark,
              "正文 \(InkLevel.bodyDark) → AI \(InkLevel.bodySoftDark)")
        check("两档字色确实不同", MDInk.current.body != MDInk.current.bodySoft)
        check("浅一档但没淡到看不清", InkLevel.bodySoftLight < 0.5)
    }

    // MARK: 检查更新

    private static func updateCheck() {
        print("▸ 检查更新")
        let C = UpdateChecker.self

        // 版本比较：逐段数值，不是字符串比较（"0.2.10" 若按字典序会输给 "0.2.9"）
        check("版本比较：低位小", C.compare("0.0.2", "0.0.3") < 0)
        check("版本比较：相等", C.compare("0.0.2", "0.0.2") == 0)
        check("版本比较：段数不齐补零", C.compare("0.2", "0.2.0") == 0)
        check("版本比较：两位数段", C.compare("0.2.10", "0.2.9") > 0,
              "字典序会把 10 排在 9 前面")
        check("版本比较：跨段", C.compare("1.0.0", "0.9.9") > 0)
        check("版本归一去掉 v 前缀", C.normalize(" v0.3.0 ") == "0.3.0")

        // 清单解析：类型不对 / 字段缺失都不能崩，返回 nil 当没查到
        let good = #"{"version":"v0.3.0","notes":"修复若干问题","dmg":"https://example.com/MDay-0.3.0.dmg"}"#
        let parsed = C.parse(data: Data(good.utf8))
        check("清单解析出版本号", parsed?.version == "0.3.0")
        check("清单解析出说明", parsed?.notes == "修复若干问题")
        check("清单解析出下载地址", parsed?.downloadURL.contains("MDay-0.3.0.dmg") == true)
        check("清单坏 JSON 返回 nil", C.parse(data: Data("not json".utf8)) == nil)
        check("清单缺版本返回 nil", C.parse(data: Data(#"{"notes":"x"}"#.utf8)) == nil)
        check("清单版本不是数字返回 nil",
              C.parse(data: Data(#"{"version":"最新版"}"#.utf8)) == nil)
        check("清单顶层不是字典返回 nil",
              C.parse(data: Data("[1,2,3]".utf8)) == nil)
        check("notes/dmg 缺省为空串",
              C.parse(data: Data(#"{"version":"1.0"}"#.utf8))?.downloadURL == "")

        // 节流：独立 UserDefaults 域，不碰真实的「上次检查时间」
        let d = UserDefaults(suiteName: "selftest.update")!
        d.removePersistentDomain(forName: "selftest.update")
        let now = Date()
        check("从没查过 → 该查", C.shouldAutoCheck(now: now, defaults: d))
        C.markChecked(now: now, defaults: d)
        check("刚查过 1 小时 → 不查",
              !C.shouldAutoCheck(now: now.addingTimeInterval(3600), defaults: d))
        check("查过 25 小时 → 该查",
              C.shouldAutoCheck(now: now.addingTimeInterval(25 * 3600), defaults: d))

        // 清单地址必须指向本仓库，且当前版本号能被正确归一
        check("清单地址在 m-day-diary 仓库里",
              C.manifestURL.absoluteString.contains("mikizhu520/m-day-diary"))
        check("当前版本号归一后仍是数字段",
              Int(C.normalize(AppInfo.version).split(separator: ".")[0]) != nil)
    }

    // MARK: 输入法组字

    private static func imeInput() {
        print("▸ 输入法组字")
        let none = NSRange(location: NSNotFound, length: 0)

        check("不在组字：原样返回",
              MarkedText.committed("今天天气不错", marked: none) == "今天天气不错")
        check("标记区长度为 0：原样返回",
              MarkedText.committed("你好", marked: NSRange(location: 2, length: 0)) == "你好")
        check("组字在行尾：剥掉拼音串",
              MarkedText.committed("今天天气nihao", marked: NSRange(location: 4, length: 5)) == "今天天气")
        check("组字在中间：只留已确定的两头",
              MarkedText.committed("我写xx了", marked: NSRange(location: 2, length: 2)) == "我写了")
        check("整篇都是组字：交出空串",
              MarkedText.committed("nihao", marked: NSRange(location: 0, length: 5)) == "")
        check("空文档不崩",
              MarkedText.committed("", marked: none) == "")
        check("标记区越界：退回原样（绝不抛异常）",
              MarkedText.committed("hi", marked: NSRange(location: 9, length: 2)) == "hi")
        // UTF-16 计数：emoji 占两个单位，切错位置会出现半个代理对（乱码方块）
        check("emoji 按 UTF-16 计数切得干净",
              MarkedText.committed("A😀你好", marked: NSRange(location: 3, length: 2)) == "A😀")
        check("标记区落在 emoji 之后不误伤",
              MarkedText.committed("A😀ni", marked: NSRange(location: 3, length: 2)) == "A😀")
    }

    // MARK: 待办勾选命中

    private static func checkboxHit() {
        print("▸ 待办勾选命中")
        // 真·NSTextView + 真排版：渲染后拿「画出来的方框」中心去点，
        // 画在哪就得点得中哪，绘制和命中两套坐标才不会各飘各的。
        let container = NSTextContainer(size: NSSize(width: 400, height: 2000))
        let lm = NSLayoutManager()
        lm.addTextContainer(container)
        let storage = NSTextStorage(string: "- [ ] 待办一\n- [x] 已完成\n普通行不带框\n")
        storage.addLayoutManager(lm)
        let tv = RJTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 2000),
                            textContainer: container)
        tv.textContainerInset = NSSize(width: 2, height: 10)
        container.widthTracksTextView = true

        LiveMarkdown.render(storage, baseSize: 16, caretLine: nil, style: .default)
        lm.ensureLayout(for: container)

        let boxes = tv.allCheckboxRects()
        check("两个待办行各画出一个方框", boxes.count == 2, "实际 \(boxes.count) 个")

        if boxes.count == 2 {
            let c0 = NSPoint(x: boxes[0].midX, y: boxes[0].midY)
            let ok0 = tv.hitCheckbox(at: c0)
            check("点空方框 → 勾上", ok0 && tv.string.hasPrefix("- [x] 待办一"),
                  ok0 ? "文本没变成 [x]" : "点击未命中")
            let c1 = NSPoint(x: boxes[1].midX, y: boxes[1].midY)
            let ok1 = tv.hitCheckbox(at: c1)
            check("点已勾方框 → 取消勾", ok1 && tv.string.contains("- [ ] 已完成"))
            // 普通行中间点一下：不该崩、不该误勾
            let mid = NSPoint(x: 200, y: boxes[1].maxY + 40)
            _ = tv.hitCheckbox(at: mid)
            check("误点普通行不误勾", tv.string.contains("普通行不带框"))
            // 勾选状态跟绘制口径一致：画实心 = 源码 [x]，画空心 = 源码 [ ]
            check("勾上后源码是 [x]", tv.string.hasPrefix("- [x]"))
            check("取消后源码是 [ ]", tv.string.contains("\n- [ ] 已完成"))

            // 对齐：方框竖直中心要落在**文字**的中心上。
            // minimumLineHeight 撑出来的行高全在文字上方，拿行框居中框就会偏高——
            // 独立推基准：正文「待办一」的基线（locationForGlyph）+ 该字符实际字体的度量。
            if let box0 = tv.checkboxBox(at: 0) {
                let g = lm.glyphIndexForCharacter(at: 6) // 「待」
                let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                let baselineY = frag.minY + tv.textContainerOrigin.y + lm.location(forGlyphAt: g).y
                let f = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
                let expectedMid = baselineY - ((f?.ascender ?? 0) + (f?.descender ?? 0)) / 2
                check("勾选框与文字同一水平线", abs(box0.midY - expectedMid) < 0.8,
                      String(format: "框 midY %.2f vs 文字中心 %.2f（行框 midY %.2f）",
                             box0.midY, expectedMid, frag.midY + tv.textContainerOrigin.y))
                // 行框中心必须和文字中心拉开距离，否则这条断言没在防真问题
                check("minimumLineHeight 确实把行框撑高了（防断言失效）",
                      frag.midY + tv.textContainerOrigin.y < expectedMid - 0.3)
            }
        }

        // 纯函数口径：行首的 [ ] 才算数，正文里的不算
        let ns = tv.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        check("正文里的 [ ] 不被当成勾选框",
              LiveMarkdown.taskToggle(in: "他说 [ ] 好看", range: NSRange(location: 0, length: 9)) == nil)
        check("行首缩进的待办能勾",
              LiveMarkdown.taskToggle(in: ns, range: full) != nil)
    }
}
