import SwiftUI
import AppKit

// MARK: - 新建 / 编辑日记本
//
// 用一个弹窗同时干三件事：起名字、挑颜色、挑图标。
// 改动全部先落在 `JournalDraft` 上，按「保存」才写进 config.json ——
// 所以改到一半按 Esc 不会把真实数据改坏。

struct JournalEditor: View {
    @EnvironmentObject var store: Store

    /// 草稿是独立副本：弹窗里怎么改都不影响外面的 store
    @State private var draft: JournalDraft
    @State private var showDeleteConfirm = false
    @FocusState private var nameFocused: Bool

    init(draft: JournalDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewCard
                    nameField
                    lockSection
                    colorSection
                    symbolSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            HairLine()
            footer
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .background(Color.rjBar)
        .tint(Color.rjAccent)
        .task {
            // 新建时把光标直接放进名字框，省一次点击；
            // 延迟一点点是因为 sheet 的转场动画还没结束时设焦点会被吃掉。
            guard draft.isNew else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            nameFocused = true
        }
        .alert("删除「\(draft.name)」？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteNow() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("日记本会被移除，里面的 \(entryCount) 篇日记仍然保留在「全部日记」里。")
        }
    }

    // MARK: 尺寸
    //
    // 固定宽度要按当前界面缩放留够，不然「特大」档下内容会被挤。

    private var sheetWidth: CGFloat { 560 * UIScale.factor }

    private var sheetHeight: CGFloat {
        let usable = (NSScreen.main?.visibleFrame.height ?? 800) - 90
        return min(680 * UIScale.factor, usable)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            JournalIconBadge(symbol: draft.symbol,
                             color: Color(hex: draft.colorHex),
                             size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.title).font(.rj(16, weight: .bold, design: .rounded))
                Text(draft.isNew ? "起个名字，挑个图标" : "改名、换色、换图标、管隐私")
                    .font(.rj(11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    // MARK: 预览

    private var previewCard: some View {
        let typed = draft.name.trimmed
        return HStack(spacing: 14) {
            JournalIconBadge(symbol: draft.symbol, color: Color(hex: draft.colorHex), size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(typed.isEmpty ? Journal.fallbackName : typed)
                    .font(.rj(17, weight: .bold, design: .rounded))
                    .foregroundStyle(typed.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(previewSubtitle)
                    .font(.rj(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
    }

    private var entryCount: Int {
        draft.isNew ? 0 : store.journalCount(draft.id)
    }

    private var previewSubtitle: String {
        if draft.isNew { return "保存后就会出现在左侧的日记本列表里" }
        return entryCount > 0 ? "已有 \(entryCount) 篇日记" : "还是空的，等着第一篇"
    }

    // MARK: 名称

    private var nameField: some View {
        section("名称") {
            TextField("比如：旅行、读书、健身", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.rj(14.5, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .focused($nameFocused)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(nameFocused ? Color.rjAccent.opacity(0.65)
                                      : Color(nsColor: .separatorColor),
                                      lineWidth: nameFocused ? 1.5 : 1)
                )
                .animation(.easeOut(duration: 0.15), value: nameFocused)
                .onSubmit { if draft.canSave { save() } }
        }
    }

    // MARK: 隐私
    //
    // 上锁的前提是设过打开密码 —— 校验用的就是那一套，不另设一本子的密码。
    // 没设的时候不能只是「存不上」：得把原因写出来，并且指向设置页的那一项。

    private var lockSection: some View {
        let hasPassword = store.security.hasPassword
        return section("隐私") {
            Toggle(isOn: lockBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("单独上锁").font(.rj(13))
                    Text(hasPassword
                         ? "点开这一本时要先过指纹或打开密码；本次打开期间解开一次就够。"
                         : "需要先在「设置 → 安全」里设置打开密码，才能给日记本上锁。")
                        .font(.rj(11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!hasPassword)
            .opacity(hasPassword ? 1 : 0.55)
        }
    }

    /// 没设打开密码时，永远显示成「关」——否则配置文件被手改过的话，
    /// 这个开关会呈现出一个根本生效不了的状态，看着像坏了。
    private var lockBinding: Binding<Bool> {
        Binding(get: { draft.locked && store.security.hasPassword },
                set: { draft.locked = $0 })
    }

    // MARK: 颜色

    private var colorSection: some View {
        section("颜色") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 10)], spacing: 10) {
                ForEach(Journal.palette, id: \.self) { hex in
                    colorCell(hex)
                }
            }
        }
    }

    private func colorCell(_ hex: String) -> some View {
        let selected = draft.colorHex.lowercased() == hex.lowercased()
        return Button {
            draft.colorHex = hex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 26, height: 26)
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.rj(11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(hex)
    }

    // MARK: 图标

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 标题右边挂一个「已选」：图标库有六组、要滚才能看完，
            // 光靠网格里的高亮，滚不到那一组时会以为没选中。
            HStack(spacing: 6) {
                Text("图标").font(.rj(13, weight: .semibold))
                Spacer()
                Text("已选").font(.rj(11)).foregroundStyle(.tertiary)
                JournalIconBadge(symbol: draft.symbol, color: Color(hex: draft.colorHex), size: 20)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Journal.iconGroups) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(group.title)
                            .font(.rj(11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                            ForEach(group.symbols, id: \.self) { sym in
                                symbolCell(sym)
                            }
                        }
                    }
                }
            }
        }
    }

    private func symbolCell(_ sym: String) -> some View {
        let selected = draft.symbol == sym
        return Button {
            draft.symbol = sym
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color(hex: draft.colorHex) : Color.primary.opacity(0.06))
                Image(systemName: sym)
                    .font(.rj(12.5, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.62))
            }
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.9))
        .help(sym)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if !draft.isNew, store.journals.count > 1 {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.rj(12.5))
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                .buttonStyle(RJPlainButtonStyle())
            }

            if !draft.canSave {
                Text("给日记本起个名字")
                    .font(.rj(11.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("取消") { cancel() }
                .buttonStyle(RJPlainButtonStyle())
                .font(.rj(13))
                .keyboardShortcut(.cancelAction)

            Button {
                save()
            } label: {
                Label(draft.isNew ? "创建" : "保存", systemImage: "checkmark")
                    .font(.rj(13, weight: .semibold))
            }
            .buttonStyle(RJPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.canSave)
            .opacity(draft.canSave ? 1 : 0.4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Color.rjBar)
    }

    // MARK: 小工具

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.rj(13, weight: .semibold))
            content()
        }
    }

    private func save() {
        guard draft.canSave else { return }
        store.commitJournalDraft(draft)
    }

    private func cancel() {
        store.cancelJournalDraft()
    }

    private func deleteNow() {
        let target = store.journal(for: draft.id)
        store.cancelJournalDraft()
        if let target { store.deleteJournal(target) }
    }
}
