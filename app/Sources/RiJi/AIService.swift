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
    /// 第几轮请求。`cancel()` 之后旧任务还会跑完收尾代码，
    /// 靠它把「旧流的收尾」认出来丢掉 —— 否则旧流的结束时回调会提前把
    /// 新流的忙碌状态清掉（总结还在写，「正在写总结…」先消失了）。
    private var generation = 0

    func cancel() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    /// 流式对话。onDelta 会在主线程被调用。
    /// - Parameter onFinish: 无论正常结束、报错还是被打断都会调一次（主线程），
    ///   给界面收尾用（关掉进度提示之类）。
    func stream(baseURL: String,
                apiKey: String,
                model: String,
                temperature: Double,
                messages: [ChatMessage],
                onDelta: @escaping (String) -> Void,
                onFinish: (() -> Void)? = nil) {
        cancel()
        generation &+= 1
        let myGeneration = generation

        guard !apiKey.trimmed.isEmpty else {
            lastError = "还没有填写 DeepSeek API Key，请到「设置 → AI」里填写"
            onFinish?()
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
            await MainActor.run {
                guard self.generation == myGeneration else { return }
                self.isStreaming = false
                onFinish?()
            }
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
    你是「MDay」日记应用里的私人助理，名字叫小迹。使用者是一位中文母语者。
    要求：
    1. 一律用简体中文回答，语气自然、平实、不说教。
    2. 尊重使用者的隐私与感受，不做道德评判，不强行给建议。
    3. 回答简洁，能一段话说完就不要列五条。
    4. 引用日记原文时保持原样，不要编造日记里没有的内容。
    """

    static let chatSystem = systemBase + "\n5. 你现在是在和用户聊他/她的日记内容，可以提问、共情、给出具体可执行的建议。"

    /// 按人格拼系统提示词。人格自带人设和说话方式，这里只补所有人格都该守的底线
    /// （不编造、不超出日记范围），免得六份提示词里重复写六遍。
    ///
    /// - Parameters:
    ///   - memory: 从日记里沉淀下来的已知信息（MemoryStore.contextBlock()），空则不注入
    ///   - nickname: 使用者希望被怎么称呼，空就不特别提
    ///   - custom: 设置页「个性化提示词」，用户自己补的私人背景
    static func system(for personaId: String,
                       memory: String = "",
                       nickname: String = "",
                       custom: String = "",
                       profile: String = "") -> String {
        var base = AIPersonas.find(personaId).system + """

        另外两条硬规矩：
        · 日记里没有的信息不要补。不知道就说不知道，或者问一句。
        · 日记是私密的，你的回答只在应用里出现，不要假设它会被别人看到。
        """
        let name = nickname.trimmed
        if !name.isEmpty {
            base += "\n\n称呼：使用者希望你叫他/她「\(name)」。自然地用这个称呼，别每次都先报一遍。"
        }
        let info = profile.trimmed
        if !info.isEmpty {
            base += """

            关于使用者的基本档案（他/她自己在设置里填的）：\(info)。
            星座、MBTI 只当作理解脾气的参考，不要当成定论，更不要写进回答里反复提。
            """
        }
        let extra = custom.trimmed
        if !extra.isEmpty {
            base += "\n\n使用者额外交代的背景：\n\(extra)"
        }
        let mem = memory.trimmed
        if !mem.isEmpty {
            base += "\n\n" + mem
        }
        return base
    }

    // MARK: 四个快捷动作的提示词
    //
    // 写这些提示词的原则：角色、输入、分析维度、输出结构、约束五件事都得说清楚。
    // 光说「帮我总结一下」出来的东西必然是流水账 —— 模型不知道你要它挑什么、
    // 按什么口径挑、写成什么样算合格。

    static func summarizeSingle(_ entry: Entry, journal: String) -> String {
        """
        你是日记应用里的总结助手。下面是一篇日记，请读完后给出一份结构化摘要。

        输入说明
        · 正文是作者的原始记录，口语化、可能有错别字和没写完的句子，这是正常的，不要「修正」它。
        · 只依据正文里实际写了的内容，不要补充背景知识、不要猜测没写出来的动机。

        输出格式（Markdown）
        ### 一句话概括
        不超过 30 字，说清这一天（或这一篇）到底发生了什么。
        ### 关键要点
        - 最多 4 条，每条一句话，按重要性排序
        - 只写有实质内容的，不要凑数；凑不满 4 条就少写几条
        ### 情绪基调
        2-3 个词，后面跟一句依据（引用原文里的具体表述或事件）
        ### 值得回看的一句
        原样摘录正文中最有代表性的一句，用「」引起来，不要改写

        约束
        · 不评价作者的选择，不复述心灵鸡汤。
        · 正文里明确写了「不确定」「好像」的，摘要里保持同样的不确定语气。

        ——— 日记正文（\(Fmt.day.string(from: entry.createdAt)) / \(journal)）———
        \(entry.plainText)
        """
    }

    static func summarizeDay(_ entries: [Entry], date: Date) -> String {
        let text = entries.map { e in
            "【\(e.timeText) \(e.displayTitle)】\n\(e.plainText)"
        }.joined(separator: "\n\n")
        return """
        你是日记应用里的总结助手。下面是同一天写的 \(entries.count) 条日记，请合并成一份当日复盘。

        输入说明
        · 同一个时刻的几条记录可能讲同一件事的不同侧面，先合并再总结，不要按条罗列。
        · 条目按时间顺序排列，时间本身是信息（比如深夜写的和下午写的，分量通常不一样）。

        输出格式（Markdown）
        ### 今天发生了什么
        3-4 句，只写事实，不写评价。
        ### 主线与进展
        今天推进了什么、卡在哪里。如果这一天没有明显主线，直说「这一天比较散」，
        不要硬编一条主线出来。
        ### 情绪与身体状态
        结合正文里的表述和记录的天气 / 心情，说明状态如何、大概和什么有关。
        正文没提到的不要推测。
        ### 明天可以留意的一件事
        一条，具体，可执行到「明天什么时候做什么」的程度。

        约束
        · 全部依据正文，缺信息就说明缺什么，不要用常识补齐。
        · 总长度控制在 350 字以内。

        ——— 当天日记（\(Fmt.day.string(from: date))）———
        \(text)
        """
    }

    static func summarizeRange(_ entries: [Entry], label: String) -> String {
        let text = entries.sorted { $0.createdAt < $1.createdAt }.map { e in
            "【\(Fmt.day.string(from: e.createdAt)) \(e.timeText)】\(e.displayTitle)\n\(e.plainText)"
        }.joined(separator: "\n\n")
        return """
        你是日记应用里的阶段复盘助手。下面是\(label)的日记，共 \(entries.count) 条，请写一份阶段总结。

        分析口径（这是这份总结的重点，别写成流水账）
        · 看重复，不看单篇：一件事出现一次是偶然，出现三次以上是模式，模式才值得写。
        · 看变化，不看快照：这段时间相比之前，什么是新出现的，什么消失了。
        · 看投入产出：时间花在哪里，哪些有了结果，哪些一直在原地。

        输出格式（Markdown）
        ### 这段时间的关键词
        3-5 个词，每个词后面用半句话说明为什么是它。
        ### 反复出现的主题
        最多 3 条，每条注明大概出现的频次或时段，并引用一句原文作依据。
        ### 情绪曲线
        用文字描述起伏，指出峰值和低谷大致出现在什么时候、对应什么事。
        这段时间情绪平稳就直说平稳，不要为了有内容硬造波动。
        ### 值得坚持的一件事
        要有具体依据（比如「做了之后状态明显变好的那天」）。
        ### 值得放下的一件事
        同样要写依据，说明为什么判断它不值得继续。

        约束
        · 引用原文用「」，不改写。
        · 结论必须有正文支撑；支撑不住的判断标注为「推测」。
        · 总长度控制在 500 字以内。

        ——— 日记内容 ———
        \(text)
        """
    }

    /// 情绪洞察。跟阶段总结的区别：它只看情绪，看的是触发条件和应对方式，
    /// 不关心事情本身推没推进。
    static func moodInsight(_ entries: [Entry], label: String) -> String {
        let text = entries.sorted { $0.createdAt < $1.createdAt }.map { e in
            "【\(Fmt.day.string(from: e.createdAt)) \(e.timeText)】心情：\(e.mood.isEmpty ? "未记录" : e.mood)\n\(e.plainText)"
        }.joined(separator: "\n\n")
        return """
        你是日记应用里的情绪分析助手。下面是\(label)的日记，共 \(entries.count) 条。
        请只分析情绪，不要复述事件经过。

        分析框架
        1. 触发源：什么事情稳定地把情绪往上拉，什么稳定地往下压。
           要给具体的类别（比如「被临时打断」「和某类人打交道」），不要写「工作」这种笼统的词。
        2. 身体与环境的共变：情绪低落的日子，睡眠、天气、饮食、运动有什么共同点。
           正文里没写的维度，明确说「这段时间没有记录」，不要推测。
        3. 应对方式：状态不好的时候，作者自己做过什么有效的动作（哪怕很小）。
        4. 盲点：正文里反复出现、但作者似乎没意识到的关联。这一条最有价值，
           但要克制 —— 只对有三次以上证据支撑的模式下判断。

        输出格式（Markdown）
        ### 情绪基线
        一句话概括这段时间整体是什么状态。
        ### 稳定的触发源
        - 往上拉的：……
        - 往下压的：……
        ### 有效的自我调节
        具体动作 + 它出现在哪几天。
        ### 一个可以试试的小调整
        一条，成本低到今天就能做，并说明你依据什么判断它可能有用。

        约束
        · 这不是心理诊断。不用临床术语，不做病理判断，不说「你可能患有……」。
        · 如果出现持续的自伤念头、长期失眠、明显的社会功能受损，请明确建议
          寻求专业帮助，并说明这超出了你的能力范围。
        · 引用原文用「」，不改写。总长度控制在 450 字以内。

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
