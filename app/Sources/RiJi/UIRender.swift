import SwiftUI
import AppKit

// MARK: - 界面渲染（开发用）
//
// 系统不给屏幕录制权限时，用 ImageRenderer 把界面在自己进程里画成 PNG，
// 这样就能真实地检查排版、字号、配色。
//
//   RiJi --render /tmp/rj-ui
//
// 只读地构造一个 Store（不写配置、不碰用户数据），喂一批示例日记再渲染。

enum UIRender {

    @MainActor
    static func run(to dir: String) {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let store = Store()
        guard let firstJournal = Journal.defaults.first else { return }

        store.journals = Journal.defaults
        store.security = SecurityRecord()
        store.isLocked = false
        store.hasLoaded = true
        store.biometricEnabled = false
        store.settings.isConfigured = true
        store.settings.encryptionEnabled = false
        store.settings.appearance = "light"
        store.settings.editorFontSize = 15
        store.settings.defaultJournalId = firstJournal.id
        store.settings.aiModel = "deepseek-chat"
        store.entries = DemoContent.entries(journals: store.journals)

        let ai = AIService()
        let todayId = store.entries.first?.id ?? ""

        print("▶︎ 渲染界面到 \(out.path)")

        shot(out, "01-main", 1420, 900) {
            mainComposite(store: store, ai: ai, todayId: todayId)
        }
        shot(out, "02-editor", 860, 900) {
            EditorView(entryId: todayId, initialMode: .preview)
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "03-settings-general", 790, 590) {
            SettingsView(initialPage: .general)
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "04-settings-security", 790, 590) {
            SettingsView(initialPage: .security)
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "05-settings-ai", 790, 590) {
            SettingsView(initialPage: .ai)
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "06-lock", 900, 680) {
            LockView()
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "07-ai-panel", 420, 780) {
            AIPanel(currentEntryId: todayId, isPresented: .constant(true))
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "08-calendar", 380, 780) {
            CalendarPane(selectedId: .constant(todayId))
                .environmentObject(store)
                .environmentObject(ai)
        }
        shot(out, "09-stats", 820, 900) {
            StatsView()
                .environmentObject(store)
                .environmentObject(ai)
        }
        print("✓ 完成")
    }

    // MARK: 主界面三栏拼装

    @MainActor
    private static func mainComposite(store: Store, ai: AIService, todayId: String) -> some View {
        HStack(spacing: 0) {
            SidebarView(scope: .constant(.today))
                .frame(width: 252)
                .environmentObject(store)
                .environmentObject(ai)
            Divider()
            EntryListView(title: "全部日记",
                          subtitle: "共 \(store.entries.count) 篇 · \(store.totalWords()) 字",
                          entries: store.entries,
                          selectedId: .constant(todayId),
                          onCreate: {},
                          showDayHeader: true)
                .frame(width: 350)
                .environmentObject(store)
                .environmentObject(ai)
            Divider()
            EditorView(entryId: todayId, initialMode: .preview)
                .environmentObject(store)
                .environmentObject(ai)
        }
    }

    // MARK: 渲染单张

    @MainActor
    private static func shot<V: View>(_ out: URL, _ name: String,
                                      _ width: CGFloat, _ height: CGFloat,
                                      @ViewBuilder content: () -> V) {
        let view = ZStack {
            Color(nsColor: .windowBackgroundColor)
            content()
        }
        .frame(width: width, height: height)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("  ✗ \(name) 渲染失败")
            return
        }
        let url = out.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("  ✓ \(name).png")
    }
}
