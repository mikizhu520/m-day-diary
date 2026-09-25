import SwiftUI
import AppKit

// MARK: - 设置页分类

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, writing, security, ai, weather, almanac, data, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .writing: return "写作区"
        case .security: return "安全与锁"
        case .ai: return "小迹 AI"
        case .weather: return "天气"
        case .almanac: return "农历与黄历"
        case .data: return "数据与备份"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .writing: return "textformat"
        case .security: return "lock.shield"
        case .ai: return "sparkles"
        case .weather: return "cloud.sun"
        case .almanac: return "calendar.day.timeline.left"
        case .data: return "externaldrive"
        case .about: return "info.circle"
        }
    }

    var caption: String {
        switch self {
        case .general: return "外观、字号与写作偏好"
        case .writing: return "编辑区里渲染出来的排版长什么样"
        case .security: return "打开密码、触控 ID 与文件加密"
        case .ai: return "模型接口与个性化提示词"
        case .weather: return "自动记录天气"
        case .almanac: return "农历、节气、黄历与星座"
        case .data: return "存储位置、备份与恢复"
        case .about: return "版本与隐私说明"
        }
    }
}

// MARK: - 设置窗口

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var page: SettingsPage = .general
    @State private var uiScale = UIScale.doubleValue

    init(initialPage: SettingsPage? = nil) {
        _page = State(initialValue: initialPage ?? SnapshotState.settingsPage)
    }

    // 安全
    @State private var oldPwd = ""
    @State private var newPwd = ""
    @State private var confirmPwd = ""
    @State private var securityMessage: String?

    // 触控 ID
    @State private var bioPassword = ""
    @State private var bioError: String?
    @State private var showBioSheet = false

    // AI
    @State private var apiKey = ""
    @State private var testing = false
    @State private var testResult: String?
    /// 从接口拉回来的可用模型名
    @State private var modelCandidates: [String] = []
    @State private var fetchingModels = false
    @State private var modelError: String?

    // 天气
    @State private var weatherTest: String?
    @State private var weatherTesting = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 790, height: 590)
        .tint(Color.rjAccent)
        .onAppear { apiKey = AIKeyStore.read() ?? "" }
        .onReceive(NotificationCenter.default.publisher(for: .rjSettingsPage)) { note in
            if let p = note.object as? SettingsPage {
                withAnimation(.easeOut(duration: 0.15)) { page = p }
            }
        }
        .sheet(isPresented: $showBioSheet) { bioConfirmSheet }
    }

    // MARK: 左侧标题栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                    Image(systemName: "gearshape.fill")
                        .font(.rj(12, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("设置").font(.rj(15, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(SettingsPage.allCases) { p in
                    SettingsNavRow(page: p, active: page == p) {
                        withAnimation(.easeOut(duration: 0.15)) { page = p }
                    }
                }
            }
            .padding(.horizontal, 9)

            Spacer()

            Button {
                store.saveConfig()
                dismiss()
            } label: {
                Label("完成", systemImage: "checkmark")
                    .font(.rj(13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(RJSubtleButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 214)
        .background(.ultraThinMaterial)
    }

    // MARK: 右侧内容

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).font(.rj(19, weight: .bold, design: .rounded))
                Text(page.caption).font(.rj(12.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HairLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch page {
                    case .general: generalPage
                    case .writing: writingPage
                    case .security: securityPage
                    case .ai: aiPage
                    case .weather: weatherPage
                    case .almanac: almanacPage
                    case .data: dataPage
                    case .about: aboutPage
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 通用

    private var generalPage: some View {
        Group {
            SettingsSection(title: "外观") {
                SettingsRow(label: "主题", hint: "跟随系统会随 macOS 自动切换明暗") {
                    Picker("", selection: binding(\.appearance)) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }

                SettingsRow(label: "界面字号", hint: "影响整个软件的按钮、列表和正文预览") {
                    Picker("", selection: $uiScale) {
                        ForEach(UIScale.presets, id: \.value) { p in
                            Text(p.name).tag(p.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                    .onChange(of: uiScale) { _, v in UIScale.set(v) }
                }
            }

            SettingsSection(title: "写作") {
                SettingsRow(label: "状态栏显示字数") {
                    Toggle("", isOn: binding(\.showWordCount)).labelsHidden()
                }
                SettingsRow(label: "显示「那年今日」") {
                    Toggle("", isOn: binding(\.onThisDayEnabled)).labelsHidden()
                }
                SettingsRow(label: "默认日记本", hint: "新建日记时默认归到这里") {
                    Picker("", selection: binding(\.defaultJournalId)) {
                        ForEach(store.journals) { j in
                            Text(j.name).tag(j.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            SettingsSection(title: "自动锁定") {
                SettingsRow(label: "离开后自动锁定", hint: "没设密码时此项无效") {
                    Picker("", selection: binding(\.autoLockMinutes)) {
                        Text("不自动锁定").tag(0)
                        Text("1 分钟后").tag(1)
                        Text("5 分钟后").tag(5)
                        Text("15 分钟后").tag(15)
                        Text("30 分钟后").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }
        }
    }

    // MARK: 写作区

    /// 编辑区里渲染出来的排版。这里调的每一项都直接落进 MDType，
    /// 编辑器即时渲染、纯预览、AI 回复、导出 PDF 四处读的是同一份，改完立刻一起变。
    private var writingPage: some View {
        Group {
            SettingsSection(title: "纸张", caption: "写作区的底纹。编辑和预览都会跟着变，点一张试试。") {
                SettingsRow(label: "底纹") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                              spacing: 9) {
                        ForEach(PaperStyle.allCases) { p in
                            paperChip(p)
                        }
                    }
                    .frame(width: 250)
                }
            }

            SettingsSection(title: "排版风格",
                            caption: "先挑一个整体基调，下面还能继续微调。数值来自三个开源样式表的换算（github-markdown-css / @tailwindcss/typography / typora-solarized）。") {
                SettingsRow(label: "预设") {
                    Picker("", selection: presetBinding) {
                        ForEach(MDStyle.Preset.allCases) { p in
                            Text(p.name).tag(p.rawValue)
                        }
                        // 手调过参数后落进这一档，用户能一眼看出「不再是某个预设了」
                        Text("自定义").tag("custom")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }

                HStack(spacing: 7) {
                    Image(systemName: store.settings.mdStyle.matchedPreset == nil
                          ? "hand.draw" : "info.circle")
                        .font(.rj(12))
                        .foregroundStyle(Color.rjAccent)
                    Text(store.settings.mdStyle.matchedPreset?.desc
                         ?? "已按你的调整保存，不再等于任何预设。点上面的预设可一键回到基准。")
                        .font(.rj(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            SettingsSection(title: "实时预览",
                            caption: "示例内容跟着上面的设置一起变 —— 不用退出去开日记就能看到效果。再往下是细项微调。") {
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownPreview(text: MDPreviewSample.text, store: store, entry: nil,
                                    fontSize: store.settings.editorFontSize,
                                    style: store.settings.mdStyle)
                }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            }

            SettingsSection(title: "正文与间距") {
                SettingsRow(label: "编辑器正文字号", hint: "只影响写作区里的文字大小") {
                    HStack(spacing: 8) {
                        Slider(value: binding(\.editorFontSize), in: 12...24, step: 1)
                            .frame(width: 150)
                        Text("\(Int(store.settings.editorFontSize))")
                            .font(.rj(12, weight: .semibold, design: .rounded))
                            .frame(width: 26, alignment: .trailing)
                    }
                }

                SettingsRow(label: "行高", hint: "正文行与行之间的距离。长文建议 1.7 以上") {
                    sliderValue(value: binding(\.mdStyle.lineHeight),
                                range: 1.30...2.20, step: 0.02,
                                display: String(format: "%.2f", store.settings.mdStyle.lineHeight))
                }

                SettingsRow(label: "段间距", hint: "段落之间留多白。整篇的块间距都按它等比缩放") {
                    sliderValue(value: binding(\.mdStyle.paraSpacing),
                                range: 0.20...1.20, step: 0.02,
                                display: String(format: "%.2f", store.settings.mdStyle.paraSpacing))
                }

                SettingsRow(label: "标题字号", hint: "标题相对正文放大多少。中文标题笔画多，太大反而笨重") {
                    sliderValue(value: binding(\.mdStyle.headingScale),
                                range: 0.80...1.40, step: 0.02,
                                display: String(format: "%d%%", Int(store.settings.mdStyle.headingScale * 100)))
                }
            }

            SettingsSection(title: "版心宽度",
                            caption: "一行太长，眼睛回行容易串行。收窄之后正文居中，两侧留白。") {
                SettingsRow(label: "宽度") {
                    Picker("", selection: binding(\.mdStyle.contentWidth)) {
                        Text("撑满").tag(0.0)
                        Text("舒适 820").tag(820.0)
                        Text("窄 680").tag(680.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }
            }

            SettingsSection(title: "装饰",
                            caption: "这几项是纯观感，关掉不影响任何内容，也不会改动磁盘上的 Markdown。") {
                SettingsRow(label: "标题下划线", hint: "一级、二级标题压一条底边线（github-markdown-css 的做法）") {
                    Toggle("", isOn: binding(\.mdStyle.headingRule)).labelsHidden()
                }
                SettingsRow(label: "表格斑马纹", hint: "表格数据行隔一行铺一层浅底") {
                    Toggle("", isOn: binding(\.mdStyle.tableStripe)).labelsHidden()
                }
                SettingsRow(label: "引用底纹", hint: "关掉后引用只留左侧那条竖线") {
                    Toggle("", isOn: binding(\.mdStyle.quoteTint)).labelsHidden()
                }
            }

            HStack(spacing: 10) {
                Button("恢复默认排版") { resetMDStyle() }
                    .buttonStyle(RJPlainButtonStyle())
                    .font(.rj(12.5))
                Spacer()
            }
        }
    }

    /// 预设选择器：手调滑块后会落到「自定义」这一档
    // MARK: 纸张

    /// 一张缩小版的纸样，点一下就换
    private func paperChip(_ p: PaperStyle) -> some View {
        let active = store.settings.paperStyle == p.rawValue
        return Button {
            store.settings.paperStyle = p.rawValue
            store.saveConfig()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    PaperBackground(style: p)
                        .frame(width: 46, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(active ? Color.rjAccent : Color.primary.opacity(0.15),
                                      lineWidth: active ? 2 : 1)
                        .frame(width: 46, height: 30)
                }
                Text(p.name)
                    .font(.rj(10.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.rjAccent : Color.secondary)
            }
        }
        .buttonStyle(PressableStyle())
        .help(p.hint)
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { store.settings.mdStyle.matchedPreset?.rawValue ?? "custom" },
            set: { raw in
                guard let p = MDStyle.Preset(rawValue: raw) else { return }
                store.settings.mdStyle = p.apply(to: store.settings.mdStyle)
                store.saveConfig()
            }
        )
    }

    /// 滑块 + 右侧数值，统一宽度，免得每一行数字乱跑
    private func sliderValue(value: Binding<Double>,
                             range: ClosedRange<Double>,
                             step: Double,
                             display: String) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range, step: step, onEditingChanged: { editing in
                // 松手时才落盘：拖动过程中每帧写一次 config.json 太浪费
                if !editing { syncPresetAndSave() }
            })
            .frame(width: 150)
            Text(display)
                .font(.rj(12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func syncPresetAndSave() {
        store.settings.mdStyle.syncPreset()
        store.saveConfig()
    }

    private func resetMDStyle() {
        store.settings.mdStyle = .default
        store.saveConfig()
    }

    // MARK: 安全

    private var securityPage: some View {
        Group {
            SettingsSection(title: "打开密码") {
                if store.security.hasPassword {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.rj(15))
                            .foregroundStyle(Color.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("已设置密码").font(.rj(13, weight: .medium))
                            Text("打开 \(AppInfo.name) 需要输入密码").font(.rj(11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.lock(); dismiss()
                        } label: {
                            Label("立即锁定", systemImage: "lock.fill").font(.rj(12.5, weight: .semibold))
                        }
                        .buttonStyle(RJSubtleButtonStyle())
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.rj(15))
                            .foregroundStyle(Color.orange)
                        Text("还没有设置密码，任何人打开这个 App 都能看到日记。")
                            .font(.rj(12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if store.security.hasPassword {
                SettingsSection(title: "触控 ID / 面容 ID 解锁") {
                    if !store.biometricAvailable {
                        Text("这台 Mac 上没有可用的触控 ID / 面容 ID，只能用密码解锁。")
                            .font(.rj(12.5))
                            .foregroundStyle(.secondary)
                    } else {
                        SettingsRow(label: "用\(store.biometryName)解锁",
                                    hint: store.biometricEnabled
                                        ? "已开启。锁屏时会自动弹出\(store.biometryName)，随时也可以改用密码。"
                                        : "开启后，锁屏时验证一下\(store.biometryName)就能进。打开密码会加密保存在本机，只在你这台电脑上有效。") {
                            Toggle("", isOn: Binding(
                                get: { store.biometricEnabled },
                                set: { v in
                                    if v {
                                        bioPassword = ""
                                        bioError = nil
                                        showBioSheet = true
                                    } else {
                                        store.disableBiometric()
                                        securityMessage = "已关闭\(store.biometryName)解锁"
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                SettingsSection(title: "修改密码") {
                    SecureField("当前密码", text: $oldPwd)
                        .textFieldStyle(.roundedBorder)
                    SecureField("新密码", text: $newPwd)
                        .textFieldStyle(.roundedBorder)
                    SecureField("确认新密码", text: $confirmPwd)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        if let securityMessage {
                            Text(securityMessage)
                                .font(.rj(12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { changePwd() } label: {
                            Label("修改", systemImage: "checkmark").font(.rj(12.5, weight: .semibold))
                        }
                        .buttonStyle(RJSubtleButtonStyle())
                        .disabled(newPwd.isEmpty || confirmPwd.isEmpty)
                    }
                }

                SettingsSection(title: "文件加密",
                                caption: store.settings.encryptionEnabled
                                    ? "已开启。日记正文以密文写盘，忘记密码将无法恢复内容。"
                                    : "关闭时磁盘上是明文 Markdown，方便你用其他工具直接打开。") {
                    SettingsRow(label: "加密日记文件（AES-256-GCM）") {
                        Toggle("", isOn: Binding(
                            get: { store.settings.encryptionEnabled },
                            set: { v in _ = store.setEncryption(v) }
                        ))
                        .labelsHidden()
                    }
                }

                Button {
                    store.removePassword()
                    securityMessage = "已移除密码"
                } label: {
                    Label("移除密码（日记不再需要解锁）", systemImage: "trash")
                        .font(.rj(12.5, weight: .medium))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(RJPlainButtonStyle())
            }
        }
    }

    // MARK: AI

    private var aiPage: some View {
        Group {
            SettingsSection(title: "接口密钥", caption: "在 platform.deepseek.com 创建 API Key，粘贴到这里即可。Key 只加密保存在本机。") {
                SettingsRow(label: "API Key") {
                    HStack(spacing: 9) {
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: apiKey) { _, v in
                                AIKeyStore.write(v)
                                store.aiKeyPresent = !v.trimmed.isEmpty
                            }
                        if testing { ProgressView().controlSize(.small) }
                        Button { testConnection() } label: {
                            Label("测试连接", systemImage: "bolt.horizontal").font(.rj(12.5, weight: .semibold))
                        }
                        .buttonStyle(RJSubtleButtonStyle())
                        .disabled(apiKey.trimmed.isEmpty || testing)
                    }
                }
                if let testResult {
                    Text(testResult)
                        .font(.rj(12.5))
                        .foregroundStyle(testResult.contains("可用") || testResult.contains("成功") ? .green : .orange)
                }
            }

            SettingsSection(title: "模型", caption: "模型名可以直接打字。不确定叫什么就点「拉取」——从接口问出来的最准。") {
                SettingsRow(label: "模型") {
                    HStack(spacing: 6) {
                        TextField("例如 deepseek-chat", text: binding(\.aiModel))
                            .textFieldStyle(.roundedBorder)
                            .font(.rj(12.5, design: .monospaced))
                            .frame(width: 188)
                        if !modelPresets.isEmpty {
                            Menu {
                                ForEach(modelPresets, id: \.self) { m in
                                    Button(m) { setModel(m) }
                                }
                            } label: {
                                Text("常用").font(.rj(12))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("这家服务商常见的模型名")
                        }
                        Button {
                            fetchModels()
                        } label: {
                            if fetchingModels {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("拉取").font(.rj(12))
                            }
                        }
                        .buttonStyle(RJSubtleButtonStyle())
                        .disabled(fetchingModels || apiKey.trimmed.isEmpty)
                        .help(apiKey.trimmed.isEmpty ? "先在上面把 API Key 填上" : "从接口读取可用模型")
                    }
                }

                if !modelCandidates.isEmpty {
                    SettingsRow(label: "接口里有这些", hint: "点一下就用它") {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(modelCandidates, id: \.self) { m in
                                Button {
                                    setModel(m)
                                } label: {
                                    Text(m)
                                        .font(.rj(11.5, design: .monospaced))
                                        .foregroundStyle(store.settings.aiModel == m ? Color.white : Color.rjAccent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(Capsule().fill(store.settings.aiModel == m
                                                                   ? Color.rjAccent : Color.rjAccent.opacity(0.12)))
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .frame(width: 250, alignment: .leading)
                    }
                }

                if let modelError {
                    SettingsRow(label: "") {
                        Text(modelError)
                            .font(.rj(12))
                            .foregroundStyle(.orange)
                            .frame(width: 250, alignment: .leading)
                    }
                }
                SettingsRow(label: "接口地址", hint: "支持任何 OpenAI 兼容接口") {
                    TextField("", text: binding(\.aiBaseURL))
                        .textFieldStyle(.roundedBorder)
                        .font(.rj(12.5, design: .monospaced))
                        .frame(width: 250)
                        .onChange(of: store.settings.aiBaseURL) { _, _ in
                            // 换了服务商，上一家的模型列表就没意义了
                            modelCandidates = []
                            modelError = nil
                        }
                }
                SettingsRow(label: "随机性", hint: "越低越稳定，越高越有发挥") {
                    HStack(spacing: 8) {
                        Slider(value: binding(\.aiTemperature), in: 0...1.5, step: 0.1)
                            .frame(width: 150)
                        Text(String(format: "%.1f", store.settings.aiTemperature))
                            .font(.rj(12, design: .rounded))
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }

            SettingsSection(title: "个性化提示词", caption: "写在这里的话会随每次对话一起发给小迹，让它更懂你的处境。") {
                TextField("例如：我是一名产品经理，请多关注决策和情绪", text: binding(\.customPrompt), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }
        }
    }

    // MARK: 天气

    private var weatherPage: some View {
        SettingsSection(title: "自动记录",
                        caption: "天气来自 Open-Meteo 免费接口，不需要 API Key，只发送城市名，不会上传任何日记内容。每篇日记的天气都存在自己的 .md 文件里，也可以点日记顶部的天气按钮手动改。") {
            SettingsRow(label: "写今天的日记时自动记下天气") {
                Toggle("", isOn: binding(\.weatherAuto)).labelsHidden()
            }
            SettingsRow(label: "城市", hint: "填城市名即可，例如「北京」「上海」") {
                HStack(spacing: 10) {
                    TextField("北京", text: binding(\.weatherCity))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    if weatherTesting { ProgressView().controlSize(.small) }
                    Button { testWeather() } label: {
                        Label("测一下", systemImage: "arrow.clockwise")
                            .font(.rj(12.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(RJSubtleButtonStyle())
                    .disabled(store.settings.weatherCity.trimmed.isEmpty || weatherTesting)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if let weatherTest {
                Text(weatherTest)
                    .font(.rj(12.5))
                    .foregroundStyle(weatherTest.hasPrefix("当前") ? .green : .orange)
            }
        }
    }

    // MARK: 农历与黄历

    private var almanacPage: some View {
        Group {
            SettingsSection(title: "生日",
                            caption: "填了生日，日历页就会显示你自己星座的今日运势；不填则显示当天的太阳星座。") {
                SettingsRow(label: "出生日期", hint: "年份可以省，例如 1992-06-23 或 06-23") {
                    HStack(spacing: 10) {
                        TextField("可不填", text: binding(\.birthday))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        if let s = Zodiac.sign(fromBirthday: store.settings.birthday) {
                            HStack(spacing: 4) {
                                Text(s.emoji).font(.rj(14))
                                Text(s.name).font(.rj(12.5, weight: .semibold))
                            }
                            .foregroundStyle(Color.rjAccent)
                        } else if !store.settings.birthday.trimmed.isEmpty {
                            Text("认不出来，试试 06-23 这种写法")
                                .font(.rj(12)).foregroundStyle(.orange)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            SettingsSection(title: "数据从哪来",
                            caption: "农历、节气、干支、黄历宜忌、星座运势全部在本机推算，不联网。") {
                SettingsRow(label: "农历与节气") {
                    Text("系统内置农历表 + 天文算法求节气").font(.rj(12.5)).foregroundStyle(.secondary)
                }
                SettingsRow(label: "干支纪日") {
                    Text("以 1949-10-01 甲子日为锚点推算").font(.rj(12.5)).foregroundStyle(.secondary)
                }
                SettingsRow(label: "黄历宜忌") {
                    Text("建除十二神 + 黄黑道十二神，民间通行说法")
                        .font(.rj(12.5)).foregroundStyle(.secondary)
                }
                SettingsRow(label: "节假日与调休") {
                    Text("国务院办公厅公布的安排，已收录 2024–2026 年")
                        .font(.rj(12.5)).foregroundStyle(.secondary)
                }
                SettingsRow(label: "星座运势") {
                    Text("娱乐向，没有天文或统计依据").font(.rj(12.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 数据

    private var dataPage: some View {
        Group {
            SettingsSection(title: "存储位置",
                            caption: "每篇日记都是独立的 .md 文件，图片在 attachments 子目录里。换到别的电脑只要拷这个文件夹。") {
                Text(store.dataURL.path)
                    .font(.rj(12.5, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.05)))
                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.dataURL])
                    } label: {
                        Label("在访达中显示", systemImage: "folder").font(.rj(12.5, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())

                    Button { changeDataPath() } label: {
                        Label("更改位置…", systemImage: "arrow.triangle.2.circlepath").font(.rj(12.5, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())
                }
            }

            SettingsSection(title: "备份与恢复") {
                HStack(spacing: 10) {
                    Button {
                        Exporter.backupJSON(store: store)
                    } label: {
                        Label("备份为 JSON…", systemImage: "square.and.arrow.down").font(.rj(12.5, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())

                    Button {
                        store.loadEntries()
                        store.show("已重新加载 \(store.entries.count) 篇")
                    } label: {
                        Label("重新扫描磁盘", systemImage: "arrow.clockwise").font(.rj(12.5, weight: .semibold))
                    }
                    .buttonStyle(RJSubtleButtonStyle())
                }
            }
        }
    }

    // MARK: 关于

    private var aboutPage: some View {
        Group {
            SettingsSection(title: "版本") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppInfo.name).font(.rj(14, weight: .semibold))
                        Text(AppInfo.tagline).font(.rj(12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Pill(text: "v\(AppInfo.version)", symbol: "tag", color: .rjAccent)
                }
                Text(AppInfo.about)
                    .font(.rj(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection(title: "开发者", caption: "有问题、有想法，随时找我。") {
                SettingsRow(label: "作者") {
                    Text(AppInfo.author).font(.rj(12.5, weight: .medium))
                }

                SettingsRow(label: "GitHub") {
                    HStack(spacing: 9) {
                        Text(AppInfo.github)
                            .font(.rj(12.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            if let u = URL(string: AppInfo.github) { NSWorkspace.shared.open(u) }
                        } label: {
                            Label("打开", systemImage: "arrow.up.right.square")
                                .font(.rj(12, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .buttonStyle(RJSubtleButtonStyle())
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                SettingsRow(label: "邮箱") {
                    HStack(spacing: 9) {
                        Text(AppInfo.email)
                            .font(.rj(12.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            if let u = URL(string: "mailto:\(AppInfo.email)") { NSWorkspace.shared.open(u) }
                        } label: {
                            Label("写邮件", systemImage: "envelope")
                                .font(.rj(12, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .buttonStyle(RJSubtleButtonStyle())
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                SettingsRow(label: "微信公众号") {
                    Text(AppInfo.wechat)
                        .font(.rj(12.5, weight: .semibold))
                        .foregroundStyle(Color.rjAccent)
                }
            }

            SettingsSection(title: "隐私",
                            caption: "数据全部保存在你自己的电脑上，不上传任何服务器。只有在你使用 AI 功能时，相关内容才会发送给你配置的模型接口；只有在你开启天气功能时，才会发送一个城市名。")

            SettingsSection(title: "文件格式",
                            caption: "日记是标准 Markdown，front matter 里保存标题、标签、心情、天气等元数据。用 Typora、VS Code、Obsidian 都能直接打开。")
        }
    }

    // MARK: 触控 ID 确认

    private var bioConfirmSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(Color.rjAccent.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: store.biometrySymbol)
                        .font(.rj(19))
                        .foregroundStyle(Color.rjAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("开启\(store.biometryName)解锁").font(.rj(15, weight: .semibold))
                    Text("先输入打开密码确认身份，之后就能用\(store.biometryName)进日记了。")
                        .font(.rj(12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SecureField("当前密码", text: $bioPassword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirmBio() }

            if let bioError {
                Text(bioError).font(.rj(12.5)).foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { showBioSheet = false }
                    .buttonStyle(RJPlainButtonStyle())
                Button { confirmBio() } label: {
                    Label("确认开启", systemImage: "checkmark").font(.rj(13, weight: .semibold))
                }
                .buttonStyle(RJPrimaryButtonStyle())
                .disabled(bioPassword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func confirmBio() {
        if store.enableBiometric(password: bioPassword) {
            showBioSheet = false
            bioPassword = ""
            bioError = nil
            securityMessage = "已开启\(store.biometryName)解锁"
        } else {
            bioError = "密码不正确，请重试"
        }
    }

    // MARK: 行为

    private func changePwd() {
        guard newPwd.count >= 4 else { securityMessage = "新密码至少 4 位"; return }
        guard newPwd == confirmPwd else { securityMessage = "两次输入不一致"; return }
        if store.changePassword(from: oldPwd, to: newPwd) {
            securityMessage = "已修改"
            oldPwd = ""; newPwd = ""; confirmPwd = ""
        } else {
            securityMessage = "当前密码不正确"
        }
    }

    // MARK: 模型

    /// 常见的模型名，按接口地址猜。
    /// 猜不到就返回空 —— 宁可让人点「拉取」，也不要瞎给一串对不上的名字。
    private var modelPresets: [String] {
        let base = store.settings.aiBaseURL.lowercased()
        if base.contains("deepseek") { return ["deepseek-chat", "deepseek-reasoner"] }
        if base.contains("moonshot") { return ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"] }
        if base.contains("dashscope") || base.contains("aliyun") {
            return ["qwen-plus", "qwen-turbo", "qwen-max", "qwen-long"]
        }
        if base.contains("bigmodel") || base.contains("zhipu") { return ["glm-4-plus", "glm-4-air", "glm-4-flash"] }
        if base.contains("openai.com") { return ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"] }
        if base.contains("siliconflow") { return ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-72B-Instruct"] }
        if base.contains("volces") || base.contains("ark") { return ["doubao-pro-32k", "doubao-lite-32k"] }
        // 认不出来的服务商（比如小米 MiMo）：留空，让「拉取」去问
        return []
    }

    private func setModel(_ m: String) {
        store.settings.aiModel = m
        store.saveConfig()
        modelError = nil
    }

    private func fetchModels() {
        fetchingModels = true
        modelError = nil
        let key = apiKey.trimmed.isEmpty ? (AIKeyStore.read() ?? "") : apiKey
        let base = store.settings.aiBaseURL
        Task {
            do {
                let list = try await AIService().listModels(baseURL: base, apiKey: key)
                modelCandidates = list
                if !list.contains(store.settings.aiModel) {
                    modelError = "当前填的「\(store.settings.aiModel)」不在这份列表里，多半用不了"
                }
            } catch let e as AIError {
                modelError = e.message
            } catch {
                modelError = error.localizedDescription
            }
            fetchingModels = false
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        Task {
            let err = await AIService().test(baseURL: store.settings.aiBaseURL,
                                             apiKey: apiKey,
                                             model: store.settings.aiModel)
            testResult = err == nil ? "连接成功 ✓" : "失败：\(err ?? "")"
            testing = false
        }
    }

    private func testWeather() {
        weatherTesting = true
        weatherTest = nil
        Task {
            let w = await store.currentWeather(force: true)
            if let w {
                weatherTest = "当前 \(w.city) \(w.summary)"
            } else {
                weatherTest = "取不到：\(store.weatherError ?? "未知原因")"
            }
            weatherTesting = false
        }
    }

    private func changeDataPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "使用此文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            store.changeDataPath(to: url)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { store.settings[keyPath: keyPath] = $0; store.saveConfig() }
        )
    }
}

// MARK: - 左侧导航行

struct SettingsNavRow: View {
    var page: SettingsPage
    var active: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.rj(13, weight: .medium))
                    .foregroundStyle(active ? Color.rjAccent : Color.secondary)
                    .frame(width: 20)
                Text(page.title)
                    .font(.rj(13.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.primary : Color.primary.opacity(0.85))
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Color.rjAccent.opacity(0.14)
                          : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.18), value: active)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.98, pressedOpacity: 0.85))
        .onHover { hovering = $0 }
    }
}

// MARK: - 写作区设置页的示例内容
//
// 覆盖每一种排版元素（标题 / 行内样式 / 引用 / 列表 / 待办 / 表格 / 代码 / 分割线），
// 这样在设置里拖滑块时，一眼能看到所有元素一起跟着变。

enum MDPreviewSample {
    static let text = """
    # 标题一

    正文里的 **加粗**、*斜体*、~~删除线~~ 和 `行内代码`，还有一个 [链接](https://example.com)。

    > 引用块：左侧一条竖线，配一层很淡的底纹。

    - 无序列表第一项
    - 第二项
      - 嵌套一层的空心圆点
    - [ ] 没做完的待办
    - [x] 做完的待办（会被划掉）

    | 项目 | 数量 | 说明 |
    | --- | --- | --- |
    | 日记 | 128 | 全部本地保存 |
    | 图片 | 34 | 放在 attachments |

    ```swift
    let style = MDStyle.default
    ```
    """
}

// MARK: - 设置分组

struct SettingsSection<Content: View>: View {
    var title: String
    var caption: String? = nil
    /// 只有说明文字、没有行的分区不画卡片，免得留一个空框
    var showsCard: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.rj(14, weight: .semibold))
            if let caption {
                Text(caption)
                    .font(.rj(12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsCard {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(interactive: false)
            }
        }
    }
}

extension SettingsSection where Content == EmptyView {
    /// 纯文字分区（只有标题 + 说明）
    init(title: String, caption: String? = nil) {
        self.init(title: title, caption: caption, showsCard: false) { EmptyView() }
    }
}

// MARK: - 设置行

struct SettingsRow<Content: View>: View {
    var label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.rj(13.5))
                if let hint {
                    Text(hint)
                        .font(.rj(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            content()
        }
    }
}
