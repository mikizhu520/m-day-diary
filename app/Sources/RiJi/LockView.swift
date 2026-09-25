import SwiftUI
import AppKit

// MARK: - 解锁界面
//
// 版式照用户给的参考图重做：**整块底色 + 顶部挂一个白色飘带 logo + 中间指纹 + 底部一个白色密码框**。
// 参考图里没有卡片、没有毛玻璃、没有任何标题文字 —— 这里也一个都不加。
//
// 为什么换掉旧版：旧版是「灰底 + 居中毛玻璃卡片 + 圆形锁徽章」，看着像系统弹窗；
// 整块纯色更像一扇「门」，一眼就知道这是进不去的地方。而且底色用品牌色，
// 锁屏和图标、按钮是同一个颜色体系。
//
// 飘带的宽度按窗口宽的比例算，但**必须给上限**：窗口拉到 1440 时，
// 0.23 的比例会变成 330pt 宽的一条巨幅白布，把整屏压死。
//
// 2026-09-25 再收一版：用户说「大小改为现在的四分之一」。
// 「大小」按视觉面积算，所以边长缩一半（`sizeScale`）。
// 密码框的宽度不跟着缩到底 —— 等比缩成 188pt 就窄得没法输密码了，单独给 240 的下限。
//
// 同一天：顶部那个白色飘带换成 **反白的应用 logo**。
// 飘带是照参考图做的，但它和 MDay 自己没有关系（谁家书签长这样都行），
// 换成 logo 之后锁屏一眼就认得出是哪个 App。

/// 锁屏主视觉整体的缩放系数。面积 = 边长²，所以 0.5 就是「四分之一大小」。
private let sizeScale: CGFloat = 0.5

struct LockView: View {
    @EnvironmentObject var store: Store
    @State private var password = ""
    @State private var errorText: String?
    @State private var shake = false
    @State private var showHint = false
    @State private var bioWorking = false
    @State private var didAutoTry = false
    @State private var opening = false
    @State private var appeared = false
    @FocusState private var focused: Bool

    private var canUseBiometric: Bool { store.biometricEnabled && store.biometricAvailable }

    var body: some View {
        GeometryReader { geo in
            let markW = min(geo.size.width * 0.15, 144) * sizeScale
            let fieldW = max(240, min(376, max(280, geo.size.width * 0.30)) * sizeScale)

            ZStack {
                background

                VStack(spacing: 0) {
                    // 顶部留出标题栏那一条（交通灯在左上角，这儿是中间，不打架），
                    // 再往下放 logo。
                    LogoMark(width: markW, lineColor: Color.rjAccent)
                        .padding(.top, 62)
                        .scaleEffect(appeared ? 1 : 0.86)
                        .opacity(appeared ? 1 : 0)

                    Spacer(minLength: 12)

                    unlockGlyph

                    Spacer(minLength: 14)

                    panel(width: fieldW)
                        .padding(.bottom, max(20, geo.size.height * 0.06))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            focused = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
            autoTryBiometric()
        }
    }

    // MARK: 背景

    /// 整块纯色，没有渐变、没有卡片。
    private var background: some View {
        Color.rjAccent
    }

    // MARK: 中间的指纹 / 锁

    @ViewBuilder
    private var unlockGlyph: some View {
        if canUseBiometric {
            Button {
                Task { await bioUnlock() }
            } label: {
                ZStack {
                    if bioWorking {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: store.biometrySymbol)
                            .font(.rj(54 * sizeScale, weight: .light))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 96 * sizeScale, height: 96 * sizeScale)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("用\(store.biometryName)解锁")
            .opacity(appeared ? 1 : 0)
        } else {
            Image(systemName: "lock.fill")
                .font(.rj(46 * sizeScale, weight: .light))
                .foregroundStyle(.white.opacity(0.92))
                .frame(height: 96 * sizeScale)
                .opacity(appeared ? 1 : 0)
        }
    }

    // MARK: 底部：密码框 + 提示

    private func panel(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            field(width: width)

            if let errorText {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill").font(.rj(12))
                    Text(errorText).font(.rj(13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.16)))
                .transition(.opacity)
            }

            HStack(spacing: 14) {
                Button("忘记密码？") {
                    withAnimation(.easeOut(duration: 0.18)) { showHint.toggle() }
                }
                .buttonStyle(.plain)
                .font(.rj(12.5))
                .foregroundStyle(.white.opacity(0.85))

                if store.biometricAvailable && !store.biometricEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: store.biometrySymbol).font(.rj(12))
                        Text("用密码解锁后可开启\(store.biometryName)")
                            .font(.rj(12))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                }
            }

            if showHint {
                Text("密码只保存在本机，无法找回。\n如果确实忘了：退出 \(AppInfo.name)，删除\n~/Library/Application Support/日迹/config.json\n后重新打开即可重置（注意：如果没有开启加密，日记内容不受影响；开了加密则日记会无法解密）。")
                    .font(.rj(12))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(width: 396)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.18)))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Text("\(AppInfo.name) · 本地优先的日记本")
                .font(.rj(11))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
    }

    // MARK: 密码框

    private func field(width: CGFloat) -> some View {
        HStack(spacing: 7) {
            SecureField("密码", text: $password)
                .textFieldStyle(.plain)
                .font(.rj(13.5))
                .foregroundStyle(Color.black.opacity(0.85))
                .tint(Color.rjAccent)
                .focused($focused)
                .onSubmit { attempt() }

            Button(action: attempt) {
                ZStack {
                    Circle()
                        .fill(Color.rjAccent.opacity(password.isEmpty ? 0.22 : 1))
                        .frame(width: 24, height: 24)
                    if opening {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.rj(12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(password.isEmpty || opening)
            .help("解锁")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        // 锁屏底色不受深浅色模式影响（品牌色永远一样），但输入框是白底 ——
        // 深色模式下不钉住 light，光标和输入的字会是白的，白底白字直接看不见。
        .environment(\.colorScheme, .light)
        .offset(x: shake ? -8 : 0)
        .animation(.default.repeatCount(3, autoreverses: true).speed(7), value: shake)
    }

    // MARK: 解锁

    private func attempt() {
        guard !opening else { return }
        store.touch()
        let entered = password

        guard store.verify(entered) else {
            errorText = "密码不正确"
            shake = true
            password = ""
            Task {
                try? await Task.sleep(nanoseconds: 420_000_000)
                shake = false
            }
            return
        }

        // 密码对了：先播一下开锁动效，再真正进入
        errorText = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { opening = true }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = store.unlock(password: entered)
            password = ""
            opening = false
            // 本机支持指纹但还没开 → 问一句要不要开（直接用刚输入的密码，省得再输一遍）
            store.offerBiometricIfNeeded(password: entered)
        }
    }

    /// 打开锁屏时自动弹出一次指纹验证
    private func autoTryBiometric() {
        guard canUseBiometric, !didAutoTry else { return }
        didAutoTry = true
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await bioUnlock()
        }
    }

    private func bioUnlock() async {
        guard !bioWorking else { return }
        bioWorking = true
        errorText = nil
        let ok = await store.unlockWithBiometric()
        bioWorking = false
        guard ok else {
            // 用户取消或验证失败时静默；只有密码失配才提示
            if let issue = store.biometricIssue { errorText = issue }
            focused = true
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { opening = true }
        store.touch()
    }
}

// MARK: - 反白 logo
//
// 应用图标是「白色底 + 品牌色本子 + 白字」（见 tools/gen_icon.swift）。
// 锁屏底色本身就是品牌色，所以直接放图标会糊成一片 —— 这里把颜色关系反过来：
// 本子用白色，本子上那三行用底色（视觉上就是镂空）。合起来就是「反白的 logo」。
//
// 所有比例跟 gen_icon.swift 里那一套对齐（本子高宽比 1.233、圆角 0.155、
// 行宽 0.60/0.552/0.36、行高 0.0765、行距 0.2404、首行起点 0.3268），
// 图标和锁屏上的 logo 才是同一个东西，改一边记得改另一边。

struct LogoMark: View {
    /// 本子的宽度。高度、圆角、三行字都按这个宽度推出来
    var width: CGFloat
    /// 三行字的颜色。传锁屏底色（品牌色）即可得到「镂空」效果
    var lineColor: Color

    var body: some View {
        let w = width
        let h = w * 1.233
        let barH = w * 0.0765
        let step = w * 0.2404
        let x = w * 0.20
        let y0 = w * 0.3268

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: w * 0.155, style: .continuous)
                .fill(.white)

            // 第一行是「今天写下的那一行」，实色；后两行淡一档，做出「还在写」的层次
            bar(x: x, y: y0, w: w * 0.600, h: barH, color: lineColor, alpha: 1.0)
            bar(x: x, y: y0 + step, w: w * 0.552, h: barH, color: lineColor, alpha: 0.60)
            bar(x: x, y: y0 + step * 2, w: w * 0.360, h: barH, color: lineColor, alpha: 0.60)
        }
        .frame(width: w, height: h)
    }

    private func bar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                     color: Color, alpha: Double) -> some View {
        Capsule(style: .continuous)
            .fill(color.opacity(alpha))
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

// MARK: - 首次启动引导

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    var onFinish: () -> Void

    @State private var step = 0
    @State private var dataPath = ""
    @State private var usePassword = true
    @State private var password = ""
    @State private var confirm = ""
    @State private var enableEncryption = false
    @State private var error: String?
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            RadialGradient(colors: [Color.rjAccent.opacity(0.18), Color.clear],
                           center: .top, startRadius: 10, endRadius: 640)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 15) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.65)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 70, height: 70)
                            .shadow(color: Color.rjAccent.opacity(0.3), radius: 14, y: 6)
                        Image(systemName: "book.closed.fill")
                            .font(.rj(28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("欢迎使用 \(AppInfo.name)").font(.rj(24, weight: .bold, design: .rounded))
                    Text("本地优先的 Markdown 日记本，数据只存在你的电脑里。")
                        .font(.rj(13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 22)

                Group {
                    switch step {
                    case 0: storageStep
                    case 1: securityStep
                    default: doneStep
                    }
                }
                .frame(width: 450)
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07)))
                .shadow(color: .black.opacity(0.10), radius: 20, y: 8)

                if let error {
                    Text(error).font(.rj(12)).foregroundStyle(.red).padding(.top, 10)
                }

                Spacer(minLength: 24)
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            dataPath = store.dataURL.path
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: 步骤 1

    private var storageStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("日记保存位置", systemImage: "folder.fill")
                .font(.rj(14, weight: .semibold))

            HStack(spacing: 8) {
                Text(dataPath)
                    .font(.rj(12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                Button("更改…") { pickFolder() }
                    .buttonStyle(RJSubtleButtonStyle())
                    .font(.rj(12.5, weight: .semibold))
            }

            Text("每一篇日记都会存成一个独立的 .md 文件，图片放在同目录的 attachments 里。你可以随时用任何编辑器打开它们。")
                .font(.rj(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.18)) { step = 1 } } label: {
                    Label("下一步", systemImage: "arrow.right").font(.rj(13.5, weight: .semibold))
                }
                .buttonStyle(RJPrimaryButtonStyle())
            }
        }
    }

    // MARK: 步骤 2

    private var securityStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("给日记上把锁", systemImage: "lock.shield.fill")
                .font(.rj(14, weight: .semibold))

            Toggle("设置打开密码", isOn: $usePassword)
                .toggleStyle(.switch)
                .controlSize(.small)

            if usePassword {
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                SecureField("再输一次", text: $confirm)
                    .textFieldStyle(.roundedBorder)

                Toggle("同时加密日记文件（AES-256）", isOn: $enableEncryption)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text(enableEncryption
                     ? "开启后日记正文以密文写盘，离开这个 App 无法直接阅读，安全性最高。"
                     : "默认只锁界面，磁盘上保持明文 Markdown，方便随时用其他工具打开。")
                    .font(.rj(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("上一步") { withAnimation(.easeOut(duration: 0.18)) { step = 0 } }
                    .buttonStyle(RJPlainButtonStyle())
                Spacer()
                Button { finish() } label: {
                    Label("开始使用", systemImage: "checkmark").font(.rj(13.5, weight: .semibold))
                }
                .buttonStyle(RJPrimaryButtonStyle())
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("准备好了", systemImage: "checkmark.circle.fill")
                .font(.rj(14, weight: .semibold))
            Text("· ⌘N 新建日记\n· ⌘F 搜索\n· ⌘J 打开 AI 面板\n· ⌘L 锁定\n· ⌘, 设置")
                .font(.rj(12.5, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button { onFinish() } label: {
                    Label("完成", systemImage: "checkmark").font(.rj(13.5, weight: .semibold))
                }
                .buttonStyle(RJPrimaryButtonStyle())
            }
        }
    }

    // MARK: 行为

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            dataPath = url.path
        }
    }

    private func finish() {
        error = nil
        let url = URL(fileURLWithPath: dataPath)
        store.changeDataPath(to: url)

        if usePassword {
            guard password.count >= 4 else { error = "密码至少 4 位"; return }
            guard password == confirm else { error = "两次输入的密码不一致"; return }
            store.settings.encryptionEnabled = enableEncryption
            store.setPassword(password)
            store.saveConfig()
        } else {
            store.settings.encryptionEnabled = false
            store.saveConfig()
        }
        store.settings.isConfigured = true
        store.saveConfig()
        onFinish()
    }
}
