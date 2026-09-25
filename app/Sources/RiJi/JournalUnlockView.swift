import SwiftUI

// MARK: - 日记本解锁面板
//
// 侧边栏点到一本上锁的日记本时弹出来。
//
// 和 `LockView`（整个 App 的锁屏）刻意长得不一样：那个是全屏接管，
// 这个是「一本本子的门」，所以做成紧凑的小面板，名字和颜色都跟着那一本走，
// 一眼能确认「我正在开的是哪一本」。校验用的是同一套打开密码。

struct JournalUnlockView: View {
    @EnvironmentObject var store: Store

    /// 要解锁的日记本 id
    let journalId: String
    /// 解开之后：把侧边栏切过去
    var onUnlocked: (String) -> Void
    var onCancel: () -> Void

    @State private var password = ""
    @State private var errorText: String?
    @State private var shake = false
    @State private var bioWorking = false
    @State private var didAutoTry = false
    @State private var appeared = false
    @FocusState private var focused: Bool

    private var journal: Journal? { store.journal(for: journalId) }
    private var name: String { journal?.name ?? "日记本" }
    private var color: Color { Color(hex: journal?.colorHex ?? RJ.accentDefault)}
    private var symbol: String { journal?.symbol ?? Journal.fallbackSymbol }

    private var canUseBiometric: Bool {
        store.biometricEnabled && store.biometricAvailable && store.security.hasPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairLine()

            VStack(spacing: 13) {
                passwordField

                Button(action: attempt) {
                    Label("解锁", systemImage: "lock.open.fill")
                        .font(.rj(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RJPrimaryButtonStyle())
                .disabled(password.isEmpty)
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

                Text("解锁后本次使用一直有效；按 ⌘L 锁定或关掉 App 会重新锁上。")
                    .font(.rj(11.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            HairLine()
            footer
        }
        .frame(width: 400 * UIScale.factor)
        .background(Color.rjBar)
        .tint(Color.rjAccent)
        .scaleEffect(appeared ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { appeared = true }
            focused = true
            autoTryBiometric()
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                JournalIconBadge(symbol: symbol, color: color, size: 40)
                // 右下角压一个小锁：一眼看出「这本是锁着的」
                Image(systemName: "lock.fill")
                    .font(.rj(9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3.5)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor).opacity(0.8)))
                    .offset(x: 15, y: 15)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("「\(name)」已上锁")
                    .font(.rj(15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(canUseBiometric
                     ? "按一下\(store.biometryName)，或输入密码"
                     : "输入打开密码才能进去")
                    .font(.rj(11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            IconButton(symbol: "xmark", help: "取消", size: 26, iconSize: 11) { onCancel() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: 密码框

    private var passwordField: some View {
        HStack(spacing: 9) {
            Image(systemName: "key.fill")
                .font(.rj(13))
                .foregroundStyle(.tertiary)
            SecureField("打开密码", text: $password)
                .textFieldStyle(.plain)
                .font(.rj(14))
                .focused($focused)
                .onSubmit { attempt() }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(errorText == nil ? Color(nsColor: .separatorColor)
                              : Color.red.opacity(0.75),
                              lineWidth: errorText == nil ? 1 : 1.5)
        )
        .offset(x: shake ? -6 : 0)
        .animation(.default.repeatCount(3, autoreverses: true).speed(7), value: shake)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button("取消") { onCancel() }
                .buttonStyle(RJPlainButtonStyle())
                .font(.rj(13))
                .keyboardShortcut(.cancelAction)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    // MARK: 行为

    private func attempt() {
        let entered = password
        guard store.unlockJournal(journalId, password: entered) else {
            errorText = "密码不正确"
            shake = true
            password = ""
            Task {
                try? await Task.sleep(nanoseconds: 420_000_000)
                shake = false
            }
            return
        }
        errorText = nil
        password = ""
        onUnlocked(journalId)
    }

    /// 面板一出来就自动请一次指纹 —— 大多数情况下这才是用户想要的，
    /// 键盘都不用碰。失败就静静退回密码框。
    private func autoTryBiometric() {
        guard canUseBiometric, !didAutoTry else { return }
        didAutoTry = true
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await bioUnlock()
        }
    }

    private func bioUnlock() async {
        guard !bioWorking else { return }
        bioWorking = true
        errorText = nil
        let ok = await store.unlockJournalWithBiometric(journalId)
        bioWorking = false
        guard ok else {
            // 用户主动取消是常态，不报错；只有密码失配才给提示
            if let issue = store.biometricIssue { errorText = issue }
            focused = true
            return
        }
        onUnlocked(journalId)
    }
}
