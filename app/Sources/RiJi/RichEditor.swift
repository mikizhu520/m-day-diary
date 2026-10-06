import SwiftUI
import AppKit

// MARK: - 组字临时文本
//
// 中文/日文输入法在「组字」期间，会把拼音串和候选字以**临时文本**的形式塞进
// NSTextView 的标记区（marked range）。它还不是日记内容 —— 用户按空格选定之前，
// 随时可能整段换掉或取消。
//
// 这里踩过的坑（2026-10-06 用户报「用输入法打字，字经常上不去、就消失了」）：
//   · textDidChange 把 tv.string 整篇交给 SwiftUI 绑定，绑定里于是混进了拼音/候选字；
//   · 绑定一变，updateNSView 又用旧值 `tv.string = text` 回写，
//     回写会把 IME 的标记区掀掉 → 正在打的那几个字当场消失。
// 修法：① 交给外部的永远是「剥掉标记区之后」的正文；② 回写前先看是不是自己发出去的版本。

enum MarkedText {
    /// 去掉输入法组字中的临时文本，只留已经确定的正文。
    ///
    /// - Parameters:
    ///   - text: 编辑器当前全文（含标记区）
    ///   - marked: `NSTextView.markedRange()`；不在组字时是 `{NSNotFound, 0}`
    /// - Returns: 该写进文档与绑定的正文
    static func committed(_ text: String, marked: NSRange) -> String {
        guard marked.location != NSNotFound, marked.length > 0,
              marked.location >= 0, NSMaxRange(marked) <= (text as NSString).length else {
            return text
        }
        return (text as NSString).replacingCharacters(in: marked, with: "")
    }
}

// MARK: - 编辑器指令

enum MDAction {
    case bold
    case italic
    case strike
    case inlineCode
    case heading(Int)
    case bullet
    case numbered
    case task
    case quote
    case divider
    case body
    case link
    case insert(String)
    case indent
    case outdent
    case insertCheckbox
}

// MARK: - 编辑器注册表（工具栏 → 原生编辑器）
//
// 同一时刻只有一个编辑器可见，因此用一个弱引用注册表把工具栏动作转发给 NSTextView。

@MainActor
final class EditorRegistry {
    static let shared = EditorRegistry()
    weak var textView: NSTextView?

    func apply(_ action: MDAction, store: Store? = nil) {
        guard let tv = textView else { return }
        // 输入法正在组字：这时候插进去的文字会落进标记区里，和拼音搅在一起。
        // 让用户先把这一轮打完 —— 工具栏不抢这一下。
        guard !tv.hasMarkedText() else { return }
        tv.window?.makeFirstResponder(tv)
        let selected = tv.selectedRange()
        let source = tv.string as NSString
        let selectedText = selected.length > 0 ? source.substring(with: selected) : ""

        func replace(_ text: String, caretOffsetFromEnd: Int? = nil, selectLength: Int = 0) {
            let range = selected.length > 0 ? selected : NSRange(location: selected.location, length: 0)
            tv.insertText(text, replacementRange: range)
            if let offset = caretOffsetFromEnd {
                let end = tv.selectedRange().location
                let loc = max(0, end - offset)
                tv.setSelectedRange(NSRange(location: loc, length: selectLength))
            }
        }

        switch action {
        case .bold:
            wrap(tv, prefix: "**", suffix: "**", selected: selectedText)
        case .italic:
            wrap(tv, prefix: "*", suffix: "*", selected: selectedText)
        case .strike:
            wrap(tv, prefix: "~~", suffix: "~~", selected: selectedText)
        case .inlineCode:
            wrap(tv, prefix: "`", suffix: "`", selected: selectedText)
        case .heading(let level):
            prefixLines(tv, marker: String(repeating: "#", count: level) + " ")
        case .bullet:
            prefixLines(tv, marker: "- ")
        case .numbered:
            numberedLines(tv)
        case .task:
            prefixLines(tv, marker: "- [ ] ")
        case .quote:
            prefixLines(tv, marker: "> ")
        case .divider:
            replace("\n\n---\n\n")
        case .body:
            removeLinePrefix(tv)
        case .link:
            if selectedText.isEmpty {
                replace("[链接文字](https://)", caretOffsetFromEnd: 1)
            } else {
                replace("[\(selectedText)](https://)", caretOffsetFromEnd: 1)
            }
        case .insert(let text):
            insertAtCaret(tv, text)
        case .insertCheckbox:
            insertAtCaret(tv, "- [ ] ")
        case .indent:
            prefixLines(tv, marker: "  ", onlyIfMissing: false)
        case .outdent:
            removeLinePrefix(tv)
        }
    }

    // MARK: 内部

    private func wrap(_ tv: NSTextView, prefix: String, suffix: String, selected: String) {
        let range = tv.selectedRange()
        if selected.isEmpty {
            tv.insertText(prefix + suffix, replacementRange: range)
            let loc = tv.selectedRange().location - suffix.utf16.count
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        } else {
            // 已有包裹则去掉
            if selected.hasPrefix(prefix) && selected.hasSuffix(suffix) && selected.utf16.count > prefix.utf16.count + suffix.utf16.count {
                let inner = String(selected.dropFirst(prefix.count).dropLast(suffix.count))
                tv.insertText(inner, replacementRange: range)
                tv.setSelectedRange(NSRange(location: range.location, length: inner.utf16.count))
            } else {
                tv.insertText(prefix + selected + suffix, replacementRange: range)
                tv.setSelectedRange(NSRange(location: range.location, length: (prefix + selected + suffix).utf16.count))
            }
        }
    }

    private func lineRange(_ tv: NSTextView) -> NSRange {
        let source = tv.string as NSString
        return source.lineRange(for: tv.selectedRange())
    }

    private func prefixLines(_ tv: NSTextView, marker: String, onlyIfMissing: Bool = true) {
        let range = lineRange(tv)
        let source = tv.string as NSString
        let block = source.substring(with: range)
        let hadNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadNewline { lines.removeLast() }
        let marked = lines.map { line -> String in
            if onlyIfMissing && line.hasPrefix(marker) { return line }
            if line.trimmed.isEmpty && (marker == "- " || marker == "- [ ] " || marker == "  ") { return line }
            return marker + line
        }
        let joined = marked.joined(separator: "\n") + (hadNewline ? "\n" : "")
        tv.insertText(joined, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location, length: joined.utf16.count))
    }

    private func numberedLines(_ tv: NSTextView) {
        let range = lineRange(tv)
        let source = tv.string as NSString
        let block = source.substring(with: range)
        let hadNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadNewline { lines.removeLast() }
        var n = 1
        let out = lines.map { line -> String in
            if line.trimmed.isEmpty { return line }
            let s = "\(n). " + line
            n += 1
            return s
        }
        let joined = out.joined(separator: "\n") + (hadNewline ? "\n" : "")
        tv.insertText(joined, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location, length: joined.utf16.count))
    }

    private func removeLinePrefix(_ tv: NSTextView) {
        let range = lineRange(tv)
        let source = tv.string as NSString
        let block = source.substring(with: range)
        let hadNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadNewline { lines.removeLast() }
        let out = lines.map { line -> String in
            var s = line
            for pattern in ["^#{1,6}\\s+", "^>\\s?", "^- \\[ \\]\\s?", "^[-\\*\\+]\\s+", "^\\d+[.)]\\s+", "^\\s{1,2}"] {
                if let r = s.range(of: pattern, options: .regularExpression) {
                    s.removeSubrange(r)
                    break
                }
            }
            return s
        }
        let joined = out.joined(separator: "\n") + (hadNewline ? "\n" : "")
        tv.insertText(joined, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location, length: joined.utf16.count))
    }

    private func insertAtCaret(_ tv: NSTextView, _ text: String) {
        tv.insertText(text, replacementRange: tv.selectedRange())
    }
}

// MARK: - 原生编辑器（NSTextView 包装，支持中文输入法与撤销）

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    /// 写作区样式（行高、段间距、标题字号、装饰开关），来自设置页
    var style: MDStyle = .default
    /// 即时渲染：输入的 Markdown 语法立刻变成排版效果，
    /// 标记字符在非光标行自动隐去，光标回到那一行时再显示出来方便修改。
    var live: Bool = true
    var onActivity: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        // 换成自己的子类：标题底线、引用竖条、代码块圆角底、表格隔行色这些
        // 排版效果字符属性表达不了，得靠 drawRect 自己画。
        if let template = scroll.documentView as? NSTextView {
            let custom = RJTextView(frame: template.frame, textContainer: template.textContainer)
            custom.minSize = template.minSize
            custom.maxSize = template.maxSize
            custom.isVerticallyResizable = template.isVerticallyResizable
            custom.isHorizontallyResizable = template.isHorizontallyResizable
            custom.autoresizingMask = template.autoresizingMask
            scroll.documentView = custom
        }
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isRichText = live
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 2, height: 10)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 4
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.font = NSFont.systemFont(ofSize: fontSize * UIScale.factor)
        tv.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize * UIScale.factor),
            .foregroundColor: NSColor.labelColor
        ]
        tv.string = text
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        context.coordinator.textView = tv
        context.coordinator.lastPublished = text
        context.coordinator.appliedFontSize = fontSize
        context.coordinator.appliedStyle = style
        if let custom = tv as? RJTextView { custom.mdStyle = style }
        if live {
            tv.textStorage?.delegate = context.coordinator
            DispatchQueue.main.async { context.coordinator.renderNow() }
        }
        EditorRegistry.shared.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.textView = tv

        // ⚠️ 回写文本有三个前提，缺一个都会「打进去的字消失」：
        //   ① 本编辑器没在组字 —— 否则 `tv.string` 里含着 IME 的临时文本，
        //      覆盖式回写会把标记区掀掉，等价于当场取消用户正在打的字；
        //   ② 这个值不是本编辑器刚发出去的 —— 落盘是延迟的（0.7s），
        //      store 里随时可能比编辑器旧，回写等于把刚敲的几个字擦掉；
        //   ③ 确实和当前内容不同（真正的「外部改动」：插模板、AI 改写、切日记）。
        if !tv.hasMarkedText(),
           context.coordinator.lastPublished != text,
           tv.string != text {
            let sel = tv.selectedRange()
            let scrollOrigin = scroll.contentView.bounds.origin
            tv.string = text
            let loc = min(sel.location, tv.string.utf16.count)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
            scroll.contentView.scroll(to: scrollOrigin)
            context.coordinator.lastPublished = text
            context.coordinator.scheduleRender()
        }

        // 注意：isRichText 时 tv.font 会跟着选区变，不能用它判等，
        // 否则每次 SwiftUI 刷新都会重排一遍。用自己记的档位比对。
        if context.coordinator.appliedFontSize != fontSize {
            context.coordinator.appliedFontSize = fontSize
            let font = NSFont.systemFont(ofSize: fontSize * UIScale.factor)
            tv.font = font
            tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
            context.coordinator.scheduleRender()
        }

        // 样式（行高 / 段间距 / 标题字号 / 装饰开关）变了要整篇重排，
        // 不然设置页里调完回到编辑器，观感还是旧的。
        // 绘制层用的开关（引用底纹）也要同步过去，否则文字变了底色不变。
        if context.coordinator.appliedStyle != style {
            context.coordinator.appliedStyle = style
            if let custom = tv as? RJTextView {
                custom.mdStyle = style
                custom.needsDisplay = true
            }
            context.coordinator.scheduleRender()
        }

        EditorRegistry.shared.textView = tv
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var appliedFontSize: Double = 0
        var appliedStyle: MDStyle = .default

        private var renderQueued = false
        private var rendering = false
        /// 上一次参与渲染的光标行，用来避免「在同一行里左右移动」也整篇重排
        private var lastCaretLine = -1
        /// 最后一次「由本编辑器发出去」的正文。外面回来的值和它一样，
        /// 就说明只是绑定在回声，不是真的外部改动，绝不能拿去覆盖编辑器内容。
        var lastPublished: String?

        init(_ parent: RichTextEditor) { self.parent = parent }

        // MARK: 文本变化

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // 组字期间的拼音 / 候选字是输入法的临时缓冲，不属于日记正文。
            // 只把剥掉标记区之后的内容交出去，文档和绑定里就永远是「已确定」的字。
            let value = MarkedText.committed(tv.string, marked: tv.markedRange())
            if value != parent.text {
                lastPublished = value
                parent.text = value
            }
            parent.onActivity()
            scheduleRender()
        }

        /// 光标移动 → 上一行收起标记、当前行展开标记
        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleRender(caretOnly: true)
        }

        /// 只在「字符」发生变化时重排；重排自己改属性不会再次触发，避免递归
        func textStorage(_ textStorage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange,
                         changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !rendering else { return }
            scheduleRender()
        }

        // MARK: 渲染

        /// - Parameter caretOnly: 由光标移动触发时传 true，
        ///   这样在同一行里左右挪光标不会白白重排整篇。
        func scheduleRender(caretOnly: Bool = false) {
            guard parent.live, !renderQueued else { return }
            renderQueued = true
            DispatchQueue.main.async { [weak self] in
                self?.renderQueued = false
                self?.renderNow(caretOnly: caretOnly)
            }
        }

        func renderNow(caretOnly: Bool = false) {
            guard parent.live, let tv = textView, let storage = tv.textStorage else { return }
            // 中文输入法组字期间不要动 textStorage，否则会打断候选
            guard !tv.hasMarkedText() else { return }

            let baseSize = parent.fontSize * UIScale.factor
            let ns = storage.string as NSString
            let sel = tv.selectedRange()
            let caret = min(sel.location, ns.length)
            let caretLine = ns.length > 0
                ? ns.lineRange(for: NSRange(location: caret, length: 0))
                : NSRange(location: 0, length: 0)

            if caretOnly && caretLine.location == lastCaretLine { return }
            lastCaretLine = caretLine.location

            let undo = tv.undoManager
            let undoWasOn = undo?.isUndoRegistrationEnabled ?? false
            if undoWasOn { undo?.disableUndoRegistration() }
            rendering = true
            LiveMarkdown.render(storage, baseSize: baseSize, caretLine: caretLine,
                                style: parent.style)
            rendering = false
            if undoWasOn { undo?.enableUndoRegistration() }

            tv.typingAttributes = typingAttributes(baseSize: baseSize)
            // 排版装饰是自绘的，属性改完要让整块重画
            tv.needsDisplay = true
        }

        /// 让接着输入的字符沿用光标处的样式（标题行里继续是标题、代码块里继续是等宽）
        private func typingAttributes(baseSize: CGFloat) -> [NSAttributedString.Key: Any] {
            let fallback: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: baseSize),
                .foregroundColor: NSColor.labelColor
            ]
            guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return fallback }
            let ns = storage.string as NSString
            let sel = tv.selectedRange()
            guard sel.location > 0, sel.location <= ns.length else { return fallback }

            // 行里已经写了字才继承；空行一律回到正文，免得接着标题写
            let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
            if ns.substring(with: lineRange).trimmed.isEmpty { return fallback }

            let probe = min(sel.location, storage.length) - 1
            guard probe >= 0,
                  let font = storage.attribute(.font, at: probe, effectiveRange: nil) as? NSFont,
                  font.pointSize >= baseSize * 0.6 else { return fallback }
            var color = (storage.attribute(.foregroundColor, at: probe, effectiveRange: nil) as? NSColor) ?? .labelColor
            // 落在被淡化的标记上时别把浅色带进来
            if color.alphaComponent < 0.9 { color = .labelColor }
            return [.font: font, .foregroundColor: color]
        }

        // MARK: 键盘

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Tab / Shift+Tab 缩进
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                EditorRegistry.shared.apply(.indent)
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                EditorRegistry.shared.apply(.outdent)
                return true
            }
            return false
        }
    }
}

// MARK: - 自绘排版装饰
//
// NSTextView 的字符属性只能表达字体、颜色、下划线、背景色，
// 「整段底部横线」「左侧竖条」「圆角代码块底」「表格隔行底色」都做不到，
// 于是这些效果统一挂在 .mdDeco 属性上，由这个子类在 drawRect 里画出来。
//
// 坐标：NSTextView 是 flipped 的（y 向下），layoutManager 给的行片段矩形
// 加上 textContainerOrigin 就是视图坐标。

final class RJTextView: NSTextView {

    /// 排查排版绘制用：设了 RJ_DEBUG_DECO 环境变量就把每块装饰的矩形打出来
    private static let trace = ProcessInfo.processInfo.environment["RJ_DEBUG_DECO"] != nil

    /// 用户在设置里选的写作区样式。
    /// 绘制层需要它来判断「引用要不要铺底纹」这类开关 —— 排版量（行高、留白）
    /// 已经在 LiveMarkdown 套属性时用掉了，这里只用到装饰开关。
    var mdStyle: MDStyle = .default

    override func draw(_ dirtyRect: NSRect) {
        drawDecorations(dirtyRect)
        super.draw(dirtyRect)
    }

    private func drawDecorations(_ dirty: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let ts = textStorage,
              ts.length > 0 else { return }

        let ns = ts.string as NSString
        let origin = textContainerOrigin
        let ink = MDInk.current
        // 内容区右边界（textContainer 的可用宽度边界）
        let rightEdge = bounds.width - textContainerInset.width - tc.lineFragmentPadding

        // 多行块（引用、代码）先把同一组的几行并成一个矩形，最后整块画一次，
        // 这样圆角是完整的，而不是每行各圆各的
        var groups: [Int: (kind: MDDeco.Kind, rect: NSRect, base: CGFloat, textX: CGFloat)] = [:]

        var loc = 0
        while loc < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            defer { loc = lineRange.location + max(lineRange.length, 1) }

            guard let deco = ts.attribute(.mdDeco, at: loc, effectiveRange: nil) as? MDDeco else { continue }

            let glyph = lm.glyphIndexForCharacter(at: loc)
            // lineFragmentRect 给的是「满宽」矩形，不含 headIndent 缩进，
            // 所以项目符号、引用竖条要按段落自己声明的缩进另行推算文字左边缘。
            let fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let rect = fragment.offsetBy(dx: origin.x, dy: origin.y)
            // ⚠️ 段落设了 minimumLineHeight 时，撑出来的行高全在文字上方（文字贴着 fragment 底），
            // 拿 fragment.midY 当竖直中心，勾选框/圆点会比文字偏高。
            // locationForGlyph 的 y = 字形基线相对 fragment 原点的距离，用它 + 字体度量算文字中心。
            let textMidY = Self.textMidY(layoutManager: lm, glyph: glyph, fragmentTop: rect.minY,
                                         base: deco.base, style: mdStyle)
            let indent = (ts.attribute(.paragraphStyle, at: loc, effectiveRange: nil)
                            as? NSParagraphStyle)?.headIndent ?? 0
            let textX = rect.minX + tc.lineFragmentPadding + indent

            // 只画落在脏区附近的行
            guard rect.insetBy(dx: -40, dy: -40).intersects(dirty) else { continue }

            if deco.group > 0 {
                if let old = groups[deco.group] {
                    groups[deco.group] = (old.kind, old.rect.union(rect), old.base, min(old.textX, textX))
                } else {
                    groups[deco.group] = (deco.kind, rect, deco.base, textX)
                }
            } else {
                paint(deco.kind, rect: rect, textMidY: textMidY, textX: textX,
                      type: MDType(base: deco.base, style: mdStyle), ink: ink, rightEdge: rightEdge)
            }
        }

        // 都是画在文字底下的背景，互不重叠，顺序无所谓
        for (_, g) in groups {
            paint(g.kind, rect: g.rect, textMidY: g.rect.midY, textX: g.textX,
                  type: MDType(base: g.base, style: mdStyle), ink: ink, rightEdge: rightEdge)
        }
    }

    /// 一行文字的竖直中心（视图坐标）：基线位置 - 字体框的一半高。
    /// 勾选框、项目符号与文字对齐都以此为准；fragmentTop 传入的是已偏移到视图坐标的行框顶部。
    static func textMidY(layoutManager lm: NSLayoutManager, glyph: Int,
                         fragmentTop: CGFloat, base: CGFloat, style: MDStyle) -> CGFloat {
        let baselineY = fragmentTop + lm.location(forGlyphAt: glyph).y
        let f = NSFont.systemFont(ofSize: MDType(base: base, style: style).base, weight: .regular)
        return baselineY - (f.ascender + f.descender) / 2
    }

    // MARK: 各类装饰

    /// 待办勾选框的位置：贴在文字左边缘的左边，竖直中心对齐**文字基线**（不是行框——
    /// minimumLineHeight 撑出来的空行高在文字上方，拿行框居中会偏高）。
    /// 绘制（paint）和点击命中共用同一条公式 —— 两处各算一遍迟早会错位，
    /// 表现出来就是「看着能点，点下去没反应」。
    private static func checkboxRect(textX: CGFloat, textMidY: CGFloat, type t: MDType) -> NSRect {
        let s = t.checkBox
        return NSRect(x: textX - t.base * 0.58 - s,
                      y: textMidY - s / 2,
                      width: s, height: s)
    }

    private func paint(_ kind: MDDeco.Kind, rect: NSRect, textMidY: CGFloat, textX: CGFloat,
                       type t: MDType, ink: MDInk, rightEdge: CGFloat) {
        if Self.trace { print("🎨 \(kind) rect=\(rect) textX=\(textX) right=\(rightEdge)") }
        switch kind {

        case .headingRule(let level):
            // GitHub 的招牌做法：一级二级标题压一条通栏底边线
            let y = (rect.maxY - 1).rounded() + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rightEdge, y: y))
            path.lineWidth = t.headingRuleWidth(level)
            (level == 1 ? ink.rule : ink.rule.withAlphaComponent(0.65)).setStroke()
            path.stroke()

        case .bullet(let depth):
            let d = t.bulletDot
            let center = NSPoint(x: textX - t.base * 0.52, y: textMidY)
            let dot = NSRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            let path = NSBezierPath(ovalIn: dot)
            // 一级实心、二级以上空心，层级一眼分得开
            if depth == 0 {
                ink.accent.setFill()
                path.fill()
            } else {
                path.lineWidth = max(1, d * 0.34)
                ink.accent.withAlphaComponent(0.6).setStroke()
                path.stroke()
            }

        case .checkbox(let done):
            let s = t.checkBox
            let box = Self.checkboxRect(textX: textX, textMidY: textMidY, type: t)
            let corner = s * 0.32
            let path = NSBezierPath(roundedRect: box, xRadius: corner, yRadius: corner)
            if done {
                ink.accent.setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + s * 0.24, y: box.midY - s * 0.04))
                check.line(to: NSPoint(x: box.minX + s * 0.43, y: box.midY + s * 0.20))
                check.line(to: NSPoint(x: box.minX + s * 0.78, y: box.midY - s * 0.24))
                check.lineWidth = max(1.4, s * 0.15)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                NSColor.controlBackgroundColor.setFill()
                path.fill()
                let edge = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: corner, yRadius: corner)
                edge.lineWidth = 1
                ink.secondary.withAlphaComponent(0.5).setStroke()
                edge.stroke()
            }

        case .quote:
            // 整块（可能好几行）一次画完：淡底纹 + 左侧圆头竖条
            let barW = t.quoteBarWidth
            let barX = textX - t.quoteBarGap - barW
            if t.style.quoteTint {
                // 底纹可以在设置里关掉，只留竖条（有些人觉得底色太抢）
                let bg = NSRect(x: barX, y: rect.minY,
                                width: max(0, rightEdge - barX), height: rect.height)
                ink.quoteBG.setFill()
                NSBezierPath(roundedRect: bg, xRadius: 7, yRadius: 7).fill()
            }

            let bar = NSRect(x: barX, y: rect.minY, width: barW, height: rect.height)
            ink.quoteBar.setFill()
            NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()

        case .code:
            // 整块一次画完：圆角底 + 细描边 + 左强调条
            let padH = t.codePadH
            let padV = t.codePadV
            let bg = NSRect(x: textX - padH,
                            y: rect.minY - padV,
                            width: max(0, min(rightEdge, rect.maxX + padH) - (textX - padH)),
                            height: rect.height + padV * 2)
            let path = NSBezierPath(roundedRect: bg, xRadius: 9, yRadius: 9)
            ink.codeBG.setFill()
            path.fill()
            ink.codeEdge.setStroke()
            path.lineWidth = 1
            path.stroke()

            let bar = NSRect(x: bg.minX + 1.5, y: bg.minY + 3,
                             width: 2.5, height: max(0, bg.height - 6))
            ink.accent.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()

        case .divider:
            // GitHub 的 hr 是通栏细线
            let y = rect.midY.rounded() + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rightEdge, y: y))
            path.lineWidth = 1
            ink.rule.setStroke()
            path.stroke()

        case .tableHeader:
            var bg = rect
            bg.size.width = max(0, rightEdge - bg.origin.x)
            ink.tableHeaderBG.setFill()
            bg.fill()
            let line = NSRect(x: bg.minX, y: bg.maxY - t.tableLineWidth,
                              width: bg.width, height: t.tableLineWidth)
            ink.tableLine.setFill()
            line.fill()

        case .tableRow(let alt, let last):
            if alt {
                var bg = rect
                bg.size.width = max(0, rightEdge - bg.origin.x)
                ink.tableAltBG.setFill()
                bg.fill()
            }
            if last {
                let line = NSRect(x: rect.minX, y: rect.maxY - t.tableLineWidth,
                                  width: max(0, rightEdge - rect.minX), height: t.tableLineWidth)
                ink.tableLine.setFill()
                line.fill()
            }
        }
    }

    // MARK: 待办勾选框的点击
    //
    // 勾选框是绘制层画上去的，AppKit 完全不知道它的存在，所以鼠标事件默认只会把光标
    // 摆到那一行，方框看着能点、点下去毫无反应。这里自己补一段命中检测：
    // 点在方框上就改写源码里的 `[ ]` / `[x]`（正文存储始终是纯 Markdown，
    // 改完照常走 textDidChange → 重排，不存在「视图和内容不一致」的问题）。

    /// 事件位置落在哪个字符上（取最近的字形，点在行尾空白也算这一行）
    func characterIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer,
              let ts = textStorage, ts.length > 0 else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x,
                                  y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: inContainer, in: tc,
                                  fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < lm.numberOfGlyphs else { return nil }
        return min(lm.characterIndexForGlyph(at: glyph), ts.length - 1)
    }

    /// 某个字符所在的待办勾选框（不是待办行则返回 nil）
    func checkboxBox(at charIndex: Int) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage,
              charIndex >= 0, charIndex < ts.length else { return nil }
        var effective = NSRange()
        guard let deco = ts.attribute(.mdDeco, at: charIndex, effectiveRange: &effective) as? MDDeco,
              case .checkbox = deco.kind else { return nil }

        let glyph = lm.glyphIndexForCharacter(at: charIndex)
        let fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let rect = fragment.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        // 与绘制同一口径：竖直中心按基线 + 字体度量算，不拿被 minimumLineHeight 撑高的行框
        let textMidY = Self.textMidY(layoutManager: lm, glyph: glyph, fragmentTop: rect.minY,
                                     base: deco.base, style: mdStyle)
        let indent = (ts.attribute(.paragraphStyle, at: charIndex, effectiveRange: nil)
                        as? NSParagraphStyle)?.headIndent ?? 0
        let textX = rect.minX + tc.lineFragmentPadding + indent
        return Self.checkboxRect(textX: textX, textMidY: textMidY,
                                 type: MDType(base: deco.base, style: mdStyle))
    }

    /// 点一点宽出来的「好点区域」—— 方框本身才 15pt 见方，不加余量要瞄得很准
    private func hitRect(_ box: NSRect) -> NSRect {
        box.insetBy(dx: -6, dy: -6)
    }

    private func checkboxBox(at event: NSEvent) -> NSRect? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = characterIndex(at: point), let box = checkboxBox(at: index) else { return nil }
        return hitRect(box).contains(point) ? box : nil
    }

    /// 把 `[ ]` 换成 `[x]`（或反过来）。走 shouldChangeText / didChangeText，
    /// 这样 ⌘Z 能撤销、SwiftUI 那边的 text 也会跟着更新。
    private func toggleCheckbox(at charIndex: Int) -> Bool {
        guard let ts = textStorage else { return false }
        let ns = ts.string as NSString
        let line = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        // ⚠️ 不能拿属性查询的 effectiveRange 当行用：mdDeco 是自定义 NSObject 属性，
        // 它的 run 会被字体/颜色等其它属性的边界切成碎片（自检里实测 {0,2}/{2,1}/…），
        // 拿一小段去正则找 `[ ]` 永远找不到 —— 表现就是「点方框没反应」。
        // 口径：行内任意字符带 checkbox deco = 待办行，改写查整行。
        var isTask = false
        var i = line.location
        while i < NSMaxRange(line) {
            var eff = NSRange()
            if let d = ts.attribute(.mdDeco, at: i, effectiveRange: &eff) as? MDDeco,
               case .checkbox = d.kind {
                isTask = true
                break
            }
            i = max(eff.location + max(eff.length, 1), i + 1)
        }
        guard isTask else { return false }

        guard let toggle = LiveMarkdown.taskToggle(in: ns, range: line) else { return false }
        guard shouldChangeText(in: toggle.range, replacementString: toggle.replacement) else { return false }
        ts.replaceCharacters(in: toggle.range, with: toggle.replacement)
        didChangeText()
        return true
    }

    // MARK: 命中检测（自检可直达）

    /// 收集当前所有待办方框的矩形 —— 与 drawDecorations / paint 用同一条公式，
    /// 自检拿它和 `hitCheckbox(at:)` 对账：画在哪，就得点得中哪。
    func allCheckboxRects() -> [NSRect] {
        guard let ts = textStorage, ts.length > 0 else { return [] }
        let ns = ts.string as NSString
        var rects: [NSRect] = []
        var loc = 0
        while loc < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = lineRange.location + max(lineRange.length, 1)
            guard let deco = ts.attribute(.mdDeco, at: lineRange.location, effectiveRange: nil) as? MDDeco,
                  case .checkbox = deco.kind else { continue }
            if let box = checkboxBox(at: lineRange.location) { rects.append(box) }
        }
        return rects
    }

    /// 模拟一次点击：命中方框就切换并返回 true（走的是 mouseDown 同一条路）
    @discardableResult
    func hitCheckbox(at point: NSPoint) -> Bool {
        guard let index = characterIndex(at: point), let box = checkboxBox(at: index) else { return false }
        guard hitRect(box).contains(point) else { return false }
        return toggleCheckbox(at: index)
    }

    override func mouseDown(with event: NSEvent) {
        // 组字中（输入法还有候选没落定）：先交给系统处理这一下，
        // 它会先把候选字落定，别在这时候去改写缓冲区里的字符
        if hasMarkedText() {
            super.mouseDown(with: event)
            return
        }
        if let index = characterIndex(at: convert(event.locationInWindow, from: nil)),
           checkboxBox(at: event) != nil {
            window?.makeFirstResponder(self)
            if toggleCheckbox(at: index) { return }
        }
        super.mouseDown(with: event)
    }

    /// 悬停在勾选框上换成小手，让人知道这块能点
    override func cursorUpdate(with event: NSEvent) {
        if checkboxBox(at: event) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}
