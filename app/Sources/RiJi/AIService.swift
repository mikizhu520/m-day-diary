import Foundation
import SwiftUI

// MARK: - 对话消息

struct ChatMessage: Identifiable, Equatable {
    var id = UUID()
    var role: String          // system / user / assistant
    var content: String
    var isError: Bool = false
}

// MARK: - AI 服务（DeepSeek / OpenAI 兼容接口，流式输出）

@MainActor
final class AIService: ObservableObject {
    @Published var isStreaming = false
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    /// 流式对话。onDelta 会在主线程被调用。
    func stream(baseURL: String,
                apiKey: String,
                model: String,
                temperature: Double,
                messages: [ChatMessage],
                onDelta: @escaping (String) -> Void) {
        cancel()
        guard !apiKey.trimmed.isEmpty else {
            lastError = "还没有填写 DeepSeek API Key，请到「设置 → AI」里填写"
            return
        }
        isStreaming = true
        lastError = nil

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let request = try Self.makeRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                                                   temperature: temperature, messages: messages, stream: true)
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    var body = ""
                    for try await line in bytes.lines { body += line }
                    throw AIError.server(http.statusCode, body.isEmpty ? "无返回内容" : body)
                }
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmed
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = obj["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any] else { continue }
                    if let piece = delta["content"] as? String, !piece.isEmpty {
                        await MainActor.run { onDelta(piece) }
                    }
                }
            } catch let e as AIError {
                await MainActor.run { self.lastError = e.message }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self.lastError = "请求失败：\(error.localizedDescription)" }
                }
            }
            await MainActor.run { self.isStreaming = false }
        }
    }

    /// 非流式，一次拿完整结果（用于「生成总结」后直接入库）
    func complete(baseURL: String, apiKey: String, model: String, temperature: Double,
                  messages: [ChatMessage]) async throws -> String {
        guard !apiKey.trimmed.isEmpty else { throw AIError.message("还没有填写 DeepSeek API Key") }
        let request = try Self.makeRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                                           temperature: temperature, messages: messages, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AIError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.message("返回格式异常")
        }
        return content
    }

    func test(baseURL: String, apiKey: String, model: String) async -> String? {
        do {
            let reply = try await complete(baseURL: baseURL, apiKey: apiKey, model: model,
                                           temperature: 0.2,
                                           messages: [ChatMessage(role: "user", content: "只回复两个字：可用")])
            return reply.trimmed.isEmpty ? nil : nil
        } catch let e as AIError {
            return e.message
        } catch {
            return error.localizedDescription
        }
    }

    /// 拉取这个接口下可用的模型名（OpenAI 兼容的 `GET /v1/models`）。
    ///
    /// 存在的理由很实在：模型名是各家自己起的，写死在代码里根本穷举不完
    /// （换了服务商就不知道要填什么）。这个接口是 OpenAI 兼容协议的一部分，
    /// 能直接问出答案，比让人去翻文档靠谱。
    func listModels(baseURL: String, apiKey: String) async throws -> [String] {
        var base = baseURL.trimmed
        if base.isEmpty { base = "https://api.deepseek.com/v1" }
        if base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/models") else {
            throw AIError.message("Base URL 格式不对：\(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.message("没有拿到服务器响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw AIError.message("钥匙不对（401），检查一下 API Key") }
            if http.statusCode == 404 { throw AIError.message("这个接口没有 /models，只能手动填模型名") }
            throw AIError.message("服务器返回 \(http.statusCode)")
        }

        struct ModelList: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw AIError.message("返回的内容不是模型列表")
        }
        let ids = list.data.map(\.id).sorted()
        guard !ids.isEmpty else { throw AIError.message("接口没返回任何模型") }
        return ids
    }

    private static func makeRequest(baseURL: String, apiKey: String, model: String,
                                    temperature: Double, messages: [ChatMessage],
                                    stream: Bool) throws -> URLRequest {
        var base = baseURL.trimmed
        if base.isEmpty { base = "https://api.deepseek.com/v1" }
        if base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIError.message("Base URL 格式不对：\(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "stream": stream,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

enum AIError: Error {
    case message(String)
    case server(Int, String)

    var message: String {
        switch self {
        case .message(let m): return m
        case .server(let code, let body):
            let snippet = body.count > 220 ? String(body.prefix(220)) + "…" : body
            if code == 401 { return "API Key 无效或已过期（401）" }
            if code == 402 { return "DeepSeek 余额不足（402）" }
            if code == 429 { return "请求太频繁，稍后再试（429）" }
            return "服务返回 \(code)：\(snippet)"
        }
    }
}

// MARK: - 预设提示词

enum AIPrompts {
    static let systemBase = """
    你是「日迹」日记应用里的私人助理，名字叫小迹。使用者是一位中文母语者。
    要求：
    1. 一律用简体中文回答，语气自然、平实、不说教。
    2. 尊重使用者的隐私与感受，不做道德评判，不强行给建议。
    3. 回答简洁，能一段话说完就不要列五条。
    4. 引用日记原文时保持原样，不要编造日记里没有的内容。
    """

    static let chatSystem = systemBase + "\n5. 你现在是在和用户聊他/她的日记内容，可以提问、共情、给出具体可执行的建议。"

    static func summarizeSingle(_ entry: Entry, journal: String) -> String {
        """
        请总结下面这一篇日记。

        输出格式（Markdown）：
        ### 一句话概括
        ### 关键要点
        - 最多 4 条
        ### 情绪基调
        用 2-3 个词描述，并说明依据
        ### 值得回看的一句
        摘录原文中最有代表性的一句（原样引用）

        ——— 日记正文（\(Fmt.day.string(from: entry.createdAt)) / \(journal)）———
        \(entry.plainText)
        """
    }

    static func summarizeDay(_ entries: [Entry], date: Date) -> String {
        let text = entries.map { e in
            "【\(e.timeText) \(e.displayTitle)】\n\(e.plainText)"
        }.joined(separator: "\n\n")
        return """
        下面是同一天（\(Fmt.day.string(from: date))）的 \(entries.count) 条日记，请合并成一份当天的总结。

        输出格式（Markdown）：
        ### 今天发生了什么
        ### 主线与进展
        ### 情绪与身体状态
        ### 明天可以留意的一件事

        ——— 当天日记 ———
        \(text)
        """
    }

    static func summarizeRange(_ entries: [Entry], label: String) -> String {
        let text = entries.sorted { $0.createdAt < $1.createdAt }.map { e in
            "【\(Fmt.day.string(from: e.createdAt)) \(e.timeText)】\(e.displayTitle)\n\(e.plainText)"
        }.joined(separator: "\n\n")
        return """
        下面是\(label)的全部日记，共 \(entries.count) 条。请写一份阶段总结。

        输出格式（Markdown）：
        ### 这段时间的关键词
        ### 反复出现的主题
        ### 情绪曲线
        用文字描述起伏，指出峰值和低谷大概出现在什么时候
        ### 值得坚持的一件事
        ### 值得放下的一件事

        ——— 日记内容 ———
        \(text)
        """
    }

    static let suggestTitles = """
    基于下面的日记正文，给出 3 个不同的标题建议（每个不超过 14 个字，不要编号，不要引号，每行一个）。只输出标题本身。
    """

    static let suggestTags = """
    基于下面的日记正文，给出 3-6 个中文标签建议（每个 2-4 个字，不带 # 号）。只输出标签，用顿号「、」分隔，不要其他文字。
    """
}
