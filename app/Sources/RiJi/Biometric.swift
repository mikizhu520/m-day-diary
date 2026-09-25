import Foundation
import LocalAuthentication

/// 触控 ID / 面容 ID 解锁支持。
///
/// 思路：解锁时先用生物识别确认「你就是本人」，再从本机保险库取出之前存好的打开密码，
/// 交给正常的 `unlock(password:)` 流程。这样即使开了全库加密也能用指纹解锁。
///
/// 密码原先存在系统钥匙串里，2026-09-25 改成 `Vault` —— 原因见 `Vault.swift` 顶部：
/// ad-hoc 签名的 App 每次重建都会让旧钥匙串条目变成「别的程序」，读取时弹授权框，
/// 而那个调用是同步阻塞的，会直接把 App 卡死在启动阶段。
@MainActor
enum Biometric {

    /// 保险库里存密码用的名字
    private static var vaultName: String { Vault.Name.unlockPassword }

    struct Info {
        var available: Bool = false
        var name: String = "触控 ID"
        var symbol: String = "touchid"
    }

    /// 本机可用的生物识别方式（Touch ID / Face ID / Optic ID）
    static var info: Info {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return Info()
        }
        var i = Info()
        switch ctx.biometryType {
        case .touchID:
            i.available = true; i.name = "触控 ID"; i.symbol = "touchid"
        case .faceID:
            i.available = true; i.name = "面容 ID"; i.symbol = "faceid"
        case .opticID:
            i.available = true; i.name = "光学 ID"; i.symbol = "opticid"
        default:
            i.available = false
        }
        return i
    }

    static var isAvailable: Bool { info.available }

    /// 弹出系统生物识别提示，返回是否通过
    static func verify(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "输入密码"
        ctx.localizedFallbackTitle = ""
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return false
        }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                localizedReason: reason)
        } catch {
            return false
        }
    }

    // MARK: - 本机保险库

    /// 把打开密码存进保险库（仅本机、仅本人可读）
    @discardableResult
    static func save(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        return Vault.write(password, name: vaultName)
    }

    static func readPassword() -> String? {
        Vault.read(vaultName)
    }

    static var hasStored: Bool { Vault.has(vaultName) }

    static func clear() {
        Vault.delete(vaultName)
    }
}
