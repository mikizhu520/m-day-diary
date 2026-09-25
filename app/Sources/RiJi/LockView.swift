import SwiftUI
import AppKit

// MARK: - 解锁界面

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
        ZStack {
            background

            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    lockBadge

                    VStack(spacing: 6) {
                        // 取 AppInfo 而不是写死字符串：显示名改过一次（日迹 → MDay），
                        // 写死的地方就漏了一处，锁屏上还挂着旧名字。
                        Text(AppInfo.name).font(.rj(28, weight: .bold, design: .rounded))
                        Text(canUseBiometric ? "按一下\(store.biometryName)，或输入密码" : "输入密码解锁你的日记")
                            .font(.rj(13.5))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 11) {
                        passwordField

                        Button(action: attempt) {
                            HStack(spacing: 7) {
                                Image(systemName: opening ? "lock.open.fill" : "lock.fill")
                                    .font(.rj(13, weight: .semibold))
                                Text(opening ? "正在打开…" : "解锁")
                                    .font(.rj(14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RJPrimaryButtonStyle())
                        .disabled(password.isEmpty || opening)
                        .opacity(password.isEmpty ? 0.55 : 1)
                        .animation(.easeOut(duration: 0.18), value: password.isEmpty)

                        if canUseBiometric {
                            Button {
                                Task { await bioUnlock() }
                            } label: {
                                HStack(spacing: 7) {
                                    if bioWorking {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: store.biometrySymbol).font(.rj(15))
                                    }
                                    Text(bioWorking ? "正在验证…" : "用\(store.biometryName)解锁")
                                        .font(.rj(13.5, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(RJSubtleButtonStyle())
                            .disabled(bioWorking)
                        }

                        if let errorText {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.circle.fill").font(.rj(12))
                                Text(errorText).font(.rj(12.5))
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: 344)

                    VStack(spacing: 10) {
                        Button("忘记密码？") { withAnimation(.easeOut(duration: 0.18)) { showHint.toggle() } }
                            .buttonStyle(RJPlainButtonStyle())
                            .font(.rj(12.5))

                        if store.biometricAvailable && !store.biometricEnabled {
                            HStack(spacing: 7) {
                                Image(systemName: store.biometrySymbol)
                                    .font(.rj(13))
                                    .foregroundStyle(Color.rjAccent)
                                Text("本机支持\(store.biometryName)，用密码解锁后就能开启")
                                    .font(.rj(12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.rjAccent.opacity(0.10)))
                        }

                        if showHint {
                            Text("密码只保存在本机，无法找回。\n如果确实忘了：退出 \(AppInfo.name)，删除\n~/Library/Application Support/日迹/config.json\n后重新打开即可重置（注意：如果没有开启加密，日记内容不受影响；开了加密则日记会无法解密）。")
                                .font(.rj(12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 380)
                                .padding(13)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.05)))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(38)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10))
                )
                .shadow(color: .black.opacity(0.16), radius: 26, y: 10)
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)
            }
            .padding(40)
        }
        .onAppear {
            focused = true
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { appeared = true }
            autoTryBiometric()
        }
    }

    // MARK: 背景

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.rjAccent.opacity(0.20), Color.clear],
                           center: .top, startRadius: 10, endRadius: 620)
        }
        .ignoresSafeArea()
    }

    // MARK: 锁图标

    private var lockBadge: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.rjAccent, Color.rjAccent.opacity(0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 82, height: 82)
                .shadow(color: Color.rjAccent.opacity(opening ? 0.5 : 0.28),
                        radius: opening ? 22 : 12, y: 6)
            Image(systemName: opening ? "lock.open.fill" : "lock.fill")
                .font(.rj(32, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(opening ? 1.12 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: opening)
        .offset(x: shake ? -7 : 0)
        .animation(.default.repeatCount(3, autoreverses: true).speed(7), value: shake)
    }

    // MARK: 密码框

    private var passwordField: some View {
        HStack(spacing: 9) {
            Image(systemName: "key.fill")
                .font(.rj(13))
                .foregroundStyle(.tertiary)
            SecureField("密码", text: $password)
                .textFieldStyle(.plain)
                .font(.rj(14.5))
                .focused($focused)
                .onSubmit { attempt() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(errorText == nil ? Color(nsColor: .separatorColor) : Color.red.opacity(0.75),
                              lineWidth: errorText == nil ? 1 : 1.5)
        )
        .offset(x: shake ? -7 : 0)
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
