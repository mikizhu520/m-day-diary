import Foundation

// MARK: - 更新检测
//
// 检测源是仓库根目录的 `latest.json`（不是 GitHub Releases 接口）：
// 推送新版本时只要随代码改这一个文件再 push 就行，不依赖任何网页操作或 token。
// 请求里只有一次普通的 GET，不带任何设备、身份或日记信息。
//
// 时机：
//   · 启动后延迟几秒静默查一次，同一天最多查一次（UserDefaults 节流）
//   · 设置 → 关于 里有「检查更新」按钮，手动点就立刻查、把结果说清楚
//   · 静默检查只在「有新版本」时出提示条；查不到（没网/超时）一声不吭

struct UpdateInfo: Equatable {
    var version: String
    var notes: String
    var downloadURL: String
}

@MainActor
enum UpdateChecker {

    /// 版本清单地址。走 raw.githubusercontent.com，内容随仓库 main 分支走。
    static let manifestURL = URL(string:
        "https://raw.githubusercontent.com/mikizhu520/m-day-diary/main/latest.json")!

    /// 上次自动检查的时间戳，存 UserDefaults（秒级 Unix 时间）
    static let lastCheckKey = "rj.update.lastCheck"
    /// 自动检查节流：同一天最多一次
    static let throttleInterval: TimeInterval = 24 * 3600

    // MARK: 版本比较

    /// 逐段数值比较版本号："0.2.10" > "0.2.9" > "0.2"。
    /// 非数字段（预发布标记之类）按 0 处理，够用且不会崩。
    static func compare(_ a: String, _ b: String) -> Int {
        let asa = a.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let bsb = b.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let n = max(asa.count, bsb.count)
        for i in 0..<n {
            let x = i < asa.count ? asa[i] : 0
            let y = i < bsb.count ? bsb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// tag/版本字符串归一：去掉开头的 v / V 和空白
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "v" || $0 == "V" })
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: 清单解析

    /// 解析 latest.json。容错：顶层必须是字典、字段类型不对就当没有，
    /// 绝不让一个坏清单把检查流程带崩。
    static func parse(data: Data) -> UpdateInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        let v = normalize(dict["version"] as? String ?? "")
        guard !v.isEmpty else { return nil }
        // 版本号本身也得是合法的数字段，防止把 "最新版" 之类的文案当成版本
        guard v.split(separator: ".").allSatisfy({ !$0.isEmpty && Int($0.prefix(while: \.isNumber)) != nil }) else {
            return nil
        }
        return UpdateInfo(
            version: v,
            notes: dict["notes"] as? String ?? "",
            downloadURL: dict["dmg"] as? String ?? ""
        )
    }

    // MARK: 节流

    /// 自动检查是否到点了：上次检查距今超过 24 小时（或从没查过）才查。
    /// `now` 参数留给自检注入。
    static func shouldAutoCheck(now: Date = Date(),
                                defaults: UserDefaults = .standard) -> Bool {
        let last = defaults.double(forKey: lastCheckKey)
        guard last > 0 else { return true }
        return now.timeIntervalSince1970 - last >= throttleInterval
    }

    static func markChecked(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: lastCheckKey)
    }

    // MARK: 网络检查

    enum Outcome: Equatable {
        case newer(UpdateInfo)   // 有新版本
        case upToDate            // 已是最新
        case unavailable         // 查不到（没网 / 超时 / 清单坏）
    }

    /// 拉清单并和当前版本比。5 秒超时，失败不抛错只返回 .unavailable。
    static func fetchOutcome(now: Date = Date(),
                             defaults: UserDefaults = .standard) async -> Outcome {
        markChecked(now: now, defaults: defaults)
        var req = URLRequest(url: manifestURL)
        req.timeoutInterval = 5
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let info = parse(data: data) else {
            return .unavailable
        }
        return compare(info.version, AppInfo.version) > 0 ? .newer(info) : .upToDate
    }
}
