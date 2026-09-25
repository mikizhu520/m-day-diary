import Foundation
import CryptoKit
import IOKit
import Security

// MARK: - 本机保险库
//
// 这里存的是「必须有、但绝不能弹系统弹窗」的小秘密：AI API Key、指纹解锁要用的打开密码。
//
// ── 为什么不用钥匙串（2026-09-25 踩坑记录，别再改回去）────────────────────
// 这个 App 是 ad-hoc 签名的（`codesign --sign -`）。ad-hoc 没有稳定的证书身份，
// 钥匙串条目 ACL 里记的「设计需求」就退化成创建它的那个二进制的 cdhash。
// 于是每次重新构建，新二进制 cdhash 变了，去读旧条目就会被系统判定成
// 「另一个程序想读你的机密信息」，SecurityAgent 弹出授权框。而
// `SecItemCopyMatching` 是同步阻塞的 —— 弹框一出，调用它的线程永久卡死，
// 表现成「App 启动即卡死、没有任何输出」。实测（探针见 /tmp/rj-kcprobe*.swift）：
//
//   · 裸查询                                   → ★ 卡死
//   · kSecUseAuthenticationUI = UIFail         → ★ 卡死（它只管生物识别授权，管不到 ACL 框）
//   · LAContext.interactionNotAllowed（现代写法）→ ★ 卡死
//   · kSecUseDataProtectionKeychain = true     → ◎ 不卡，但写入 errSecMissingEntitlement(-34018)
//
// 结论：**在「经常重新构建的本地 App」这个场景下钥匙串不可用**，启动路径上绝不能碰。
//
// ── 保险库的取舍 ────────────────────────────────────────────────────────
// AES-GCM 加密落盘，密钥由主板 UUID + 当前 uid 派生。把文件单独拷走没用，
// 换台机器也解不开；缺点是同一台机器上、以同一个用户身份运行的代码理论上能推出来，
// 所以它是「防止随手翻到」这个量级，不是「防住拿得到你账号的攻击者」。
// 指纹解锁真正的门是 Touch ID 本身，保险库只负责「验证通过后把密码还给我」。
enum Vault {

    /// 密文前缀，用来识别是不是我们写的、以及将来迁移格式
    private static let prefix = "RJV1:"

    /// 自检时临时改写到沙盒目录，**绝不碰用户真实的保险库**
    static var testDir: URL?

    // MARK: 位置

    private static var baseDir: URL {
        if let t = testDir { return t }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("日迹", isDirectory: true)
            .appendingPathComponent("vault", isDirectory: true)
    }

    /// 保险库里各种秘密的名字（别再散落到各处字符串里）
    enum Name {
        static let aiAPIKey = "ai-api-key"
        static let unlockPassword = "unlock-password"
    }

    static func fileURL(_ name: String) -> URL {
        baseDir.appendingPathComponent(name + ".bin")
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    // MARK: 密钥

    /// 派生密钥：主板 UUID（重装系统都不变）+ 当前用户 uid
    private static let key: SymmetricKey = {
        let seed = "com.meiling.riji.vault.v1|\(machineID())|\(getuid())"
        return SymmetricKey(data: SHA256.hash(data: Data(seed.utf8)))
    }()

    /// 备用机器标识：拿不到 IOKit 时退回「主机名 + 家目录」
    private static func fallbackMachineID() -> String {
        ProcessInfo.processInfo.hostName + "|" + NSHomeDirectory()
    }

    /// 主板 UUID。这个是硬件级标识，跟「启动会话 UUID」不同，重启/升级都不会变。
    private static func machineID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return fallbackMachineID() }
        defer { IOObjectRelease(service) }

        guard let raw = IORegistryEntryCreateCFProperty(service,
                                                        "IOPlatformUUID" as CFString,
                                                        kCFAllocatorDefault, 0) else {
            return fallbackMachineID()
        }
        guard let s = raw.takeRetainedValue() as? NSString else { return fallbackMachineID() }
        return s as String
    }

    // MARK: 读写

    @discardableResult
    static func write(_ value: String, name: String) -> Bool {
        ensureDir()
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: key),
              let combined = sealed.combined else { return false }
        let text = prefix + combined.base64EncodedString()
        let url = fileURL(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            // 只有本人可读 —— 保险库的第二道（很薄的）门
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func read(_ name: String) -> String? {
        guard let text = try? String(contentsOf: fileURL(name), encoding: .utf8),
              text.hasPrefix(prefix) else { return nil }
        guard let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    static func has(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: fileURL(name))
    }
}

// MARK: - 旧钥匙串：只留给「一次性搬走」用
//
// 刻意不做任何自动调用。这里的读取可能弹系统授权框，而且已经证明没法用 API 压掉，
// 所以只在用户显式执行 `RiJi --recover-key` 时，把它丢到后台线程上跑，并加超时兜底 ——
// 万一弹框没人点，主线程也不会跟着卡死。
enum LegacyKeychain {

    struct Item {
        var label: String
        var service: String
        var account: String
    }

    /// 需要搬家的旧条目
    static let items: [Item] = [
        Item(label: "AI API Key", service: "com.meiling.riji", account: "deepseek-api-key"),
        Item(label: "指纹解锁密码", service: "com.meiling.riji.biometric", account: "unlock-password")
    ]

    /// 读一条旧钥匙串记录。返回 nil 表示「没有 / 读不到 / 超时」。
    static func read(_ item: Item, timeout: TimeInterval = 120) -> String? {
        var result: String?
        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var raw: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &raw) == errSecSuccess,
               let data = raw as? Data,
               let text = String(data: data, encoding: .utf8) {
                result = text
            }
            done.signal()
        }

        if done.wait(timeout: .now() + timeout) == .timedOut { return nil }
        return result
    }

    /// 顺手删掉旧条目，免得以后又被谁读到 —— 弹框照样可能出，所以同样丢后台。
    static func forget(_ item: Item, timeout: TimeInterval = 20) {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account
            ]
            SecItemDelete(query as CFDictionary)
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }
}
