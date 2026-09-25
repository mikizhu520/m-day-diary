import SwiftUI
import AppKit

// MARK: - 界面截图（开发用）
//
// 系统的屏幕录制权限拿不到时，让 App 自己把窗口画出来：
// 直接抓自己的 NSWindow（不需要任何系统权限），把真实的滚动区、
// 菜单、毛玻璃、输入框全部拍下来。
//
//   RiJi --snapshot /tmp/rj-ui
//
// 截图模式会切到一个临时目录 + 一批示例日记，绝不碰用户的真实数据。

enum SnapshotState {
    static var settingsPage: SettingsPage = .general
}

@MainActor
enum SnapshotRunner {

    static var enabled: Bool { CommandLine.arguments.contains("--snapshot") }

    private static var outDir: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/rj-ui", isDirectory: true)
    }

    static func run(store: Store) async {
        // 关掉 stdout 缓冲，这样边跑边能看到进度（不然崩了就没日志）
        setvbuf(stdout, nil, _IONBF, 0)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print("▶︎ 截图模式 → \(outDir.path)")

        await settle(1.8)
        // 窗口放大到能容下四栏，截图更接近日常使用；
        // 但必须小于屏幕 visibleFrame，否则右侧会被裁掉。
        // RJ_WIN=WxH 可强制指定窗口尺寸，用来做窄宽度的回归验证
        // （例如 RJ_WIN=1120x700 检查 AI 面板打开时侧边栏会不会被折叠）。
        if let w = targetWindow(sheet: false) {
            let visible = (w.screen ?? NSScreen.main)?.visibleFrame ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 840)
            var size = NSSize(width: min(1440, visible.width - 24),
                              height: min(840, visible.height - 8))
            if let forced = ProcessInfo.processInfo.environment["RJ_WIN"] {
                let parts = forced.lowercased().split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, parts[0] > 400, parts[1] > 300 {
                    size = NSSize(width: parts[0], height: parts[1])
                }
            }
            w.setContentSize(size)
            w.center()
            w.makeKeyAndOrderFront(nil)
            let actual = w.contentView?.bounds.size ?? .zero
            print("▶︎ 屏幕可用区域 \(Int(visible.width))×\(Int(visible.height))，请求 \(Int(size.width))×\(Int(size.height))"
                  + "，实际 \(Int(actual.width))×\(Int(actual.height))"
                  + "，窗口最小 \(Int(w.contentMinSize.width))×\(Int(w.contentMinSize.height))")
            // 侧边栏宽度诊断：窄宽度下要确认它没被系统偷偷压窄（压窄就会把文字裁掉）
            for v in Self.splitColumns(w) {
                print("   分栏 \(v.0)：x=\(Int(v.1.minX)) 宽=\(Int(v.1.width))")
            }
        }
        await settle(1.6)
        if let w = targetWindow(sheet: false) { dumpTree(w) }
        capture(store: store, "01-main")

        // 深色模式对照：走设置里的外观（RootView 用 preferredColorScheme 接管，
        // 直接改 NSApp.appearance 是没用的），拍完就还原。
        let originalAppearance = store.settings.appearance
        store.settings.appearance = "dark"
        await settle(1.5)
        capture(store: store, "01b-main-dark")
        store.settings.appearance = originalAppearance
        await settle(1.0)

        // 即时渲染全语法对照：临时把第一篇换成「语法大杂烩」，
        // 光标停在文末（最后一行为空行，没有标记要露出来），整篇都处于渲染态。
        if var demo = store.entries.first {
            let backup = demo
            demo.body = DemoContent.liveSample
            store.update(demo, immediate: true)
            await settle(1.4)
            if let tv = EditorRegistry.shared.textView {
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
            await settle(1.0)
            capture(store: store, "01c-live-render")
            // 再看一眼文档尾部：代码块和分割线长什么样
            if let tv = EditorRegistry.shared.textView {
                tv.scrollRangeToVisible(NSRange(location: (tv.string as NSString).length, length: 0))
            }
            await settle(1.0)
            capture(store: store, "01d-live-tail")

            // 纯预览模式：同一篇文档，预览和即时渲染共用一份排版规格，观感应该一致
            NotificationCenter.default.post(name: .rjEditorMode, object: EditorMode.preview)
            await settle(1.3)
            capture(store: store, "01e-preview")
            NotificationCenter.default.post(name: .rjEditorMode, object: EditorMode.live)
            await settle(0.8)

            // 写作区样式的对照：同一篇文档换成「杂志」预设 + 收窄版心，
            // 用来证明设置页里调的那几项真的落到了编辑器上。拍完还原。
            let styleBackup = store.settings.mdStyle
            store.settings.mdStyle = MDStyle.Preset.magazine
                .apply(to: styleBackup)
            store.settings.mdStyle.contentWidth = 680
            await settle(1.5)
            capture(store: store, "01f-style-magazine")
            store.settings.mdStyle = styleBackup
            await settle(1.0)

            store.update(backup, immediate: true)
            await settle(0.9)
        }

        NotificationCenter.default.post(name: .rjToggleAI, object: nil)
        await settle(2.6)
        capture(store: store, "02-ai-panel")
        NotificationCenter.default.post(name: .rjToggleAI, object: nil)
        await settle(1.2)

        for page in SettingsPage.allCases {
            SnapshotState.settingsPage = page
            NotificationCenter.default.post(name: .rjOpenSettings, object: nil)
            await settle(1.2)
            NotificationCenter.default.post(name: .rjSettingsPage, object: page)
            await settle(0.9)
            capture(store: store, "03-settings-\(page.rawValue)", sheet: true)
            // 关掉设置。必须让 SwiftUI 自己收到「该关了」——
            // 直接调 NSWindow.endSheet 只收窗口不改状态，下一张 sheet 会被系统丢掉。
            NotificationCenter.default.post(name: .rjCloseSettings, object: nil)
            await settle(1.0)
        }

        // 新建 / 编辑日记本弹窗。
        // 直接把草稿填好再拍，这样图里能看到「名字 + 颜色 + 图标选中」的完整状态。
        store.journalDraft = JournalDraft(name: "旅行", colorHex: "#2AA6A6", symbol: "airplane")
        await settle(1.8)
        dumpSheets("新建日记本")
        capture(store: store, "03b-journal-new", sheet: true)
        store.cancelJournalDraft()
        await settle(1.0)

        if let first = store.journals.first {
            store.beginEditJournal(first)
            await settle(1.6)
            dumpSheets("编辑日记本")
            capture(store: store, "03c-journal-edit", sheet: true)
            store.cancelJournalDraft()
            await settle(1.0)
        }

        // 日记本单独上锁。把最后一本锁上：侧边栏会出现闭合的锁、篇数隐掉，
        // 点它会弹解锁面板。拍完就还原，免得影响后面的日历 / 统计（那些图要的是全量数据）。
        if let idx = store.journals.indices.last {
            let lockedId = store.journals[idx].id
            store.journals[idx].locked = true
            store.unlockedJournals.removeAll()
            store.objectWillChange.send()
            await settle(1.5)
            capture(store: store, "03f-journal-locked")

            store.requestJournalUnlock(lockedId)
            await settle(1.7)
            dumpSheets("日记本解锁")
            capture(store: store, "03g-journal-unlock", sheet: true)
            store.cancelJournalGate()
            await settle(1.0)

            store.journals[idx].locked = false
            store.objectWillChange.send()
            await settle(0.9)
        }

        // 九宫格日记面板。先拍「填到一半」的样子（把答案预填进去），
        // 再拍一张空白骨架 + 换到晨间模板的样子。
        store.gridDraft = GridDraft(
            templateId: GridTemplate.builtIns[0].id,
            prefillAnswers: [
                "把产品方案初稿发给老板",
                "午休时在楼下晒了十分钟太阳",
                "同事帮我改了那段文案",
                "早上六点半就起来了，没赖床",
                "下午犯困，效率掉了两个小时",
                "用 CGM 看到饭后血糖冲得比想象中快",
                "眼睛有点酸，肩膀是紧的",
                "十一点前躺下，不看手机",
                ""
            ])
        await settle(1.9)
        dumpSheets("九宫格日记")
        capture(store: store, "03d-grid-journal", sheet: true)
        store.cancelGridDraft()
        await settle(1.0)

        store.gridDraft = GridDraft(templateId: GridTemplate.builtIns[1].id)
        await settle(1.8)
        capture(store: store, "03e-grid-blank", sheet: true)
        store.cancelGridDraft()
        await settle(1.0)

        // 日历
        NotificationCenter.default.post(name: .rjScopeCalendar, object: nil)
        await settle(1.0)
        capture(store: store, "04-calendar")

        // 统计
        NotificationCenter.default.post(name: .rjScopeStats, object: nil)
        await settle(1.0)
        capture(store: store, "05-stats")

        // 窄宽度回归：把窗口压到最小，检查侧边栏会不会被系统折叠、工具条会不会撑破布局。
        //
        // 这两张（01g / 02b）原来要**另外单独跑一次** `RJ_WIN=1120x700 … --snapshot`，
        // 结果就是长期忘记跑、图一直停在旧版本上（肉眼完全看不出来，因为文件名没变）。
        // 现在并进主流程：自己改窗口尺寸、拍完再改回去。
        await narrowPass(store: store)

        // 锁屏
        store.security.hasPassword = true
        store.lock()
        await settle(1.2)
        capture(store: store, "06-lock")

        print("✓ 截图完成")
        exit(0)
    }

    /// 窄宽度那两张。
    ///
    /// 窗口最小宽 1120 是「侧边栏 226 + 中栏 286 + 编辑区 ~300 + AI 面板 300」推出来的，
    /// 所以这个宽度必须真的能站住 —— 一旦某处写了 `frame(width:)` 硬撑，
    /// 系统会把最左边那一栏整个收走（之前「打开 AI 助手，左侧导航被挤跑」就是这个）。
    private static func narrowPass(store: Store) async {
        guard let w = targetWindow(sheet: false) else { return }
        let backup = w.contentView?.bounds.size ?? .zero

        // 先回到「今天」，让窄版主界面拍的是常规状态而不是刚拍完的统计页
        NotificationCenter.default.post(name: .rjGoToday, object: nil)
        w.setContentSize(NSSize(width: 1120, height: 700))
        w.center()
        await settle(1.6)
        print("▶︎ 窄宽度回归 1120×700")
        capture(store: store, "01g-main-narrow")

        NotificationCenter.default.post(name: .rjToggleAI, object: nil)
        await settle(2.2)
        capture(store: store, "02b-ai-panel-narrow")
        NotificationCenter.default.post(name: .rjToggleAI, object: nil)
        await settle(1.2)

        // 还原。用备份的尺寸而不是写死 1440×840 —— RJ_WIN 覆盖过的时候要还回覆盖值。
        if backup.width > 100 { w.setContentSize(backup) }
        w.center()
        await settle(1.3)
    }

    // MARK: 逐张抓图

    private static func capture(store: Store, _ name: String, sheet: Bool = false) {
        // 窗口不是 key / 不在前台时，系统会把整块内容画得发灰，
        // 所以出图前先把它激活，再强制重画一遍。
        NSApp.activate(ignoringOtherApps: true)
        if let main = NSApp.windows.first(where: { $0.sheetParent == nil && $0.isVisible }) {
            main.makeKeyAndOrderFront(nil)
        }
        guard let window = targetWindow(sheet: sheet),
              let view = window.contentView else {
            print("  ✗ \(name)：找不到窗口")
            return
        }
        window.makeKey()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let bounds = view.bounds
        guard bounds.width > 10, bounds.height > 10 else {
            print("  ✗ \(name)：窗口尺寸异常")
            return
        }

        // 先试窗口级抓图（能看到系统毛玻璃），不行再退回 CALayer 自绘
        var cg = windowShot(window)
        if cg == nil || cg!.isBlank {
            cg = layerShot(view, bounds: bounds)
        }
        guard let image = cg else {
            print("  ✗ \(name)：出图失败")
            return
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("  ✗ \(name)：编码失败")
            return
        }
        try? png.write(to: outDir.appendingPathComponent("\(name).png"))
        print("  ✓ \(name).png  \(Int(bounds.width))×\(Int(bounds.height))")
    }

    /// 抓自己的窗口（不需要屏幕录制权限），能带上系统毛玻璃
    private static func windowShot(_ window: NSWindow) -> CGImage? {
        window.displayIfNeeded()
        let id = CGWindowID(window.windowNumber)
        guard id > 0 else { return nil }
        return CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming])
    }

    /// 自绘图层树：绕开系统材质层
    private static func layerShot(_ view: NSView, bounds: CGRect) -> CGImage? {
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil,
                                  width: Int(bounds.width * scale),
                                  height: Int(bounds.height * scale),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return nil
        }
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        // CALayer 原点在左下角，翻过来才和屏幕方向一致
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        view.layer?.render(in: ctx)
        return ctx.makeImage()
    }

    // MARK: 诊断

    /// 打印当前可见的 sheet。弹窗抓错（抓到上一张没关干净的）时看这个最快。
    static func dumpSheets(_ tag: String) {
        let sheets = NSApp.windows.filter { $0.isVisible && $0.sheetParent != nil }
        let desc = sheets.map {
            "\(Int($0.frame.width))×\(Int($0.frame.height))\($0 == NSApp.keyWindow ? "[key]" : "")"
        }.joined(separator: ", ")
        print("· \(tag)：可见 sheet \(sheets.count) 个 → \(desc.isEmpty ? "（无）" : desc)")
    }

    /// 找出窗口里所有 NSSplitView 的直接子栏（NavigationSplitView 就靠它排三栏），
    /// 返回「名称 → 在 splitView 坐标系里的 frame」，用来量侧边栏到底有多宽。
    static func splitColumns(_ window: NSWindow) -> [(String, NSRect)] {
        var out: [(String, NSRect)] = []
        func walk(_ v: NSView) {
            if let split = v as? NSSplitView {
                for (i, sub) in split.subviews.enumerated() {
                    let name = i == 0 ? "第1栏(侧边栏)" : (i == split.subviews.count - 1 ? "第\(i + 1)栏(末栏)" : "第\(i + 1)栏(中栏)")
                    out.append((name, sub.frame))
                }
            }
            for s in v.subviews { walk(s) }
        }
        if let root = window.contentView { walk(root) }
        return out
    }

    /// 打印窗口的视图树，看看侧边栏到底有没有内容
    static func dumpTree(_ window: NSWindow) {
        print("· 视图树")
        func walk(_ v: NSView, _ depth: Int) {
            guard depth < 9 else { return }
            let pad = String(repeating: "  ", count: depth)
            let kind = v.layer.map { String(describing: type(of: $0)) } ?? "-"
            print(String(format: "%@%@ frame=%.0f,%.0f %.0fx%.0f hidden=%@ layer=%@",
                         pad, String(describing: type(of: v)),
                         v.frame.origin.x, v.frame.origin.y,
                         v.frame.width, v.frame.height,
                         v.isHidden ? "Y" : "N", kind))
            for s in v.subviews { walk(s, depth + 1) }
        }
        if let root = window.contentView { walk(root, 0) }
        // 工具栏诊断：看清每个按钮被系统放到了哪一栏
        if let tb = window.toolbar {
            let visible = tb.visibleItems?.map { $0.itemIdentifier.rawValue } ?? []
            print("· 工具栏 共 \(tb.items.count) 项，可见 \(visible.count) 项: \(visible.joined(separator: ", "))")
            for item in tb.items {
                let frame = item.view?.frame ?? .zero
                print(String(format: "   - %@ label=%@ x=%.0f y=%.0f w=%.0f",
                             item.itemIdentifier.rawValue, item.label,
                             frame.origin.x, frame.origin.y, frame.width))
            }
        } else {
            print("· 工具栏：无")
        }
    }

    /// sheet 模式下抓弹出窗口；否则抓最大的那个主窗口
    private static func targetWindow(sheet: Bool) -> NSWindow? {
        let visible = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        if sheet {
            return visible.first { $0.sheetParent != nil && $0 == NSApp.keyWindow }
                ?? visible.first { $0.sheetParent != nil }
        }
        return visible.filter { $0.sheetParent == nil }
            .max { a, b in
                let az = (a.contentView?.bounds.width ?? 0) * (a.contentView?.bounds.height ?? 0)
                let bz = (b.contentView?.bounds.width ?? 0) * (b.contentView?.bounds.height ?? 0)
                return az < bz
            }
    }

    private static func settle(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        // 让 SwiftUI 有机会把动画走完
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}

// MARK: - 空白判断

extension CGImage {
    /// 采样判断整张图是不是基本一个颜色（抓图失败时会是空白）
    var isBlank: Bool {
        let w = width, h = height
        guard w > 8, h > 8 else { return true }
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return false }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var seen = Set<UInt32>()
        var step = 0
        let stride = max(1, min(w, h) / 40)
        while step < 40 {
            let x = (step * stride * 7 + 3) % w
            let y = (step * stride * 11 + 5) % h
            let i = (y * w + x) * 4
            let px = (UInt32(buf[i]) << 24) | (UInt32(buf[i + 1]) << 16) | (UInt32(buf[i + 2]) << 8) | UInt32(buf[i + 3])
            seen.insert(px)
            if seen.count > 3 { return false }
            step += 1
        }
        return true
    }
}

// MARK: - 示例日记（截图 / 预览用）
enum DemoContent {

    /// 语法大杂烩：只用来看「即时渲染」把每种写法变成了什么样
    static let liveSample = """
    # 一级标题

    这是一段正文，里面有 **加粗**、*斜体*、~~删除线~~、`行内代码`，还有 [链接](https://example.com)。

    ## 二级标题

    ### 三级标题

    > 引用：写日记不是为了给别人看，是为了把这一天钉住。

    - 无序列表第一项
    - 无序列表第二项

    1. 有序列表第一项
    2. 有序列表第二项

    - [x] 已经完成的待办
    - [ ] 还没做的待办

    | 项目 | 状态 |
    | --- | --- |
    | 界面重做 | 已完成 |
    | 即时渲染 | 已完成 |

    ```swift
    let text = "代码块里的 **星号** 不会被当成加粗"
    editor.render(text)
    ```

    ---

    最后一段，结束。
    """

    static func entries(journals: [Journal]) -> [Entry] {
        guard let daily = journals.first?.id else { return [] }
        let work = journals.count > 1 ? journals[1].id : daily
        let health = journals.count > 2 ? journals[2].id : daily
        let idea = journals.count > 3 ? journals[3].id : daily

        let cal = Calendar.current
        let now = Date()

        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            var c = cal.dateComponents([.year, .month, .day], from: day)
            c.hour = hour
            c.minute = minute
            return cal.date(from: c) ?? day
        }

        var list: [Entry] = []

        var e1 = Entry(journalId: daily, createdAt: at(0, 22, 41), updatedAt: at(0, 22, 41))
        e1.title = "把「MDay」的界面重做了一遍"
        e1.body = """
        今天最大的收获，是想明白了一件事：**界面丑不是审美问题，是细节密度的问题**。

        ## 改了什么

        - 把所有蓝色按钮换成图标按钮，鼠标移上去有反馈
        - 选中侧边栏那一项不再是大色块，而是柔和的暖色
        - 字号整体放大了一档，看久了眼睛不累
        - 设置页改成左边标题、右边内容

        > 一个软件好不好用，往往藏在这些「说不出来但能感觉到」的地方。

        ## 明天

        - [ ] 把日历格子再调大一点
        - [ ] 检查深色模式下的对比度

        今天状态不错，晚上喝了杯热牛奶，准备早点睡。
        """
        e1.mood = "😌"
        e1.tags = ["产品", "设计"]
        e1.weather = WeatherInfo(kind: .partly, temp: 24.7, city: "北京")
        list.append(e1)

        var e2 = Entry(journalId: work, createdAt: at(0, 15, 12), updatedAt: at(0, 15, 12))
        e2.title = "周会：把需求砍掉一半"
        e2.body = """
        上午的周会开了一个半小时，最后只留下三件事。

        | 事项 | 负责人 | 截止 |
        | --- | --- | --- |
        | 首页改版 | 我 | 下周三 |
        | 数据看板 | 小李 | 本周五 |

        结论：**先把主路径跑通，其余全部砍掉**。
        """
        e2.mood = "🤔"
        e2.tags = ["会议"]
        e2.weather = WeatherInfo(kind: .partly, temp: 24.7, city: "北京")
        list.append(e2)

        var e3 = Entry(journalId: health, createdAt: at(0, 7, 30), updatedAt: at(0, 7, 30))
        e3.body = """
        昨晚睡了七个小时，中间醒过一次，之后又睡回去了。

        早上出门前做了十分钟拉伸，肩膀松了不少。
        """
        e3.mood = "🙂"
        e3.tags = ["健康"]
        e3.weather = WeatherInfo(kind: .partly, temp: 24.7, city: "北京")
        list.append(e3)

        var e4 = Entry(journalId: idea, createdAt: at(1, 23, 5), updatedAt: at(1, 23, 5))
        e4.title = "只写一句话的日记"
        e4.body = "如果每天都只能写一句话，我会写什么？这个问题本身，比答案更有意思。"
        e4.mood = "😄"
        e4.tags = ["灵感"]
        list.append(e4)

        var e5 = Entry(journalId: daily, createdAt: at(1, 20, 18), updatedAt: at(1, 20, 18))
        e5.title = "下班路上的晚霞"
        e5.body = "地铁口出来的时候，天是橙红色的，很多人停下来拍照。我也拍了一张。\n\n可惜拍不出那个颜色。"
        e5.weather = WeatherInfo(kind: .clear, temp: 26.3, city: "北京")
        e5.mood = "😍"
        list.append(e5)

        var e6 = Entry(journalId: work, createdAt: at(3, 18, 40), updatedAt: at(3, 18, 40))
        e6.title = "面试了两个候选人"
        e6.body = "第二个候选人问了一个很好的问题：这个岗位最难的部分是什么？\n\n我想了想，是**坚持做减法**。"
        e6.tags = ["工作"]
        list.append(e6)

        var e7 = Entry(journalId: daily, createdAt: at(5, 21, 2), updatedAt: at(5, 21, 2))
        e7.title = "回家"
        e7.body = "火车上人不多，窗外是大片的平地。到家的时候妈妈已经做好饭了。"
        e7.mood = "🥳"
        e7.weather = WeatherInfo(kind: .rain, temp: 19.2, city: "杭州")
        list.append(e7)

        return list
    }
}
