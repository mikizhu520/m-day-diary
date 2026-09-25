import Foundation
import CryptoKit
import Security

/// 本地加密工具：PBKDF2-HMAC-SHA256 派生密钥 + AES-GCM 加密正文。
/// 全部在本机完成，密钥不会离开内存。
enum Crypto {

    // MARK: - 随机

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        if status != 0 {
            // 兜底：用系统随机源
            return Data((0..<count).map { _ in UInt8.random(in: 0...255) })
        }
        return data
    }

    static func randomHex(_ count: Int) -> String {
        randomBytes(count).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - PBKDF2

    /// PBKDF2-HMAC-SHA256（用 CryptoKit 手写，避免额外依赖）
    static func pbkdf2(password: String, salt: Data, iterations: Int, keyLength: Int = 32) -> Data {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        let hLen = 32
        let blocks = Int(ceil(Double(keyLength) / Double(hLen)))
        var derived = Data()

        for block in 1...max(blocks, 1) {
            var blockIndex = UInt32(block).bigEndian
            let indexData = withUnsafeBytes(of: &blockIndex) { Data($0) }

            var u = Data(HMAC<SHA256>.authenticationCode(for: salt + indexData, using: passwordKey))
            var result = u

            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                    for i in 0..<result.count { result[i] ^= u[i] }
                }
            }
            derived.append(result)
        }
        return derived.prefix(keyLength)
    }

    static func makeSalt() -> Data { randomBytes(16) }

    static func verifier(password: String, salt: Data, iterations: Int) -> String {
        let out = pbkdf2(password: password, salt: salt, iterations: iterations)
        return out.map { String(format: "%02x", $0) }.joined()
    }

    static func key(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let raw = pbkdf2(password: password, salt: salt, iterations: iterations)
        return SymmetricKey(data: raw)
    }

    // MARK: - AES-GCM

    static func encrypt(_ plain: String, key: SymmetricKey) -> String? {
        guard let data = plain.data(using: .utf8) else { return nil }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return nil }
            return "ENC1:" + combined.base64EncodedString()
        } catch {
            return nil
        }
    }

    static func decrypt(_ payload: String, key: SymmetricKey) -> String? {
        var raw = payload
        if raw.hasPrefix("ENC1:") { raw = String(raw.dropFirst(5)) }
        guard let data = Data(base64Encoded: raw) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let opened = try AES.GCM.open(box, using: key)
            return String(data: opened, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func isEncryptedPayload(_ text: String) -> Bool {
        text.trimmed.hasPrefix("ENC1:")
    }

    /// 校验密码时防止时序攻击的简单比较
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
