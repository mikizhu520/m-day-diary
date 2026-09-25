import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 导出

@MainActor
enum Exporter {

    /// 把一篇日记渲染成 PDF
    static func pdfData(entry: Entry, store: Store) -> Data? {
        let width: CGFloat = 595   // A4 宽（pt）
        let content = VStack(alignment: .leading, spacing: 0) {
            Text(entry.displayTitle)
                .font(.rj(23.5, weight: .bold))
                .padding(.bottom, 4)
            Text("\(Fmt.full.string(from: entry.createdAt))  \(entry.timeText)   ·   \(store.journal(for: entry.journalId)?.name ?? "")")
                .font(.rj(12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
            MarkdownPreview(text: entry.body, store: store, entry: entry, fontSize: 13,
                            style: store.settings.mdStyle)
        }
        .padding(48)
        .frame(width: width, alignment: .leading)
        .background(Color.white)

        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 1200)
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 200)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host.dataWithPDF(inside: host.bounds)
    }

    static func savePDF(entry: Entry, store: Store) {
        guard let data = pdfData(entry: entry, store: store) else {
            store.show("导出失败")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(Fmt.day.string(from: entry.createdAt))-\(entry.displayTitle).pdf"
        panel.prompt = "导出"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                store.show("已导出 PDF")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                store.show("写入失败：\(error.localizedDescription)")
            }
        }
    }

    static func saveMarkdown(entry: Entry, store: Store) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(Fmt.day.string(from: entry.createdAt))-\(entry.displayTitle).md"
        panel.prompt = "导出"
        if panel.runModal() == .OK, let url = panel.url {
            var text = "# \(entry.displayTitle)\n\n"
            text += "> \(Fmt.full.string(from: entry.createdAt)) \(entry.timeText)"
            if !entry.tags.isEmpty { text += "  ·  " + entry.tags.map { "#\($0)" }.joined(separator: " ") }
            text += "\n\n" + entry.body + "\n"
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                store.show("已导出 Markdown")
            } catch {
                store.show("写入失败")
            }
        }
    }

    static func copyPlainText(_ entry: Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.plainText, forType: .string)
        NotificationCenter.default.post(name: .rjToast, object: "已复制纯文本")
    }

    /// 全库备份为 JSON
    ///
    /// 走的是 `visible` 而不是 `entries`：上锁且未解锁的日记本不进备份。
    /// 理由和别处一致 —— 这是一份**可以随手发出去**的文件，
    /// 不能因为「顺手备份」就把锁住的内容绕出去。要备份那几本，先解锁再导。
    static func backupJSON(store: Store) {
        let payload: [String: Any] = [
            "exportedAt": Fmt.iso.string(from: Date()),
            "journals": store.journals.map {
                ["id": $0.id, "name": $0.name, "color": $0.colorHex, "locked": $0.locked]
            },
            "entries": store.visible.map { e in
                [
                    "id": e.id,
                    "journalId": e.journalId,
                    "createdAt": Fmt.iso.string(from: e.createdAt),
                    "updatedAt": Fmt.iso.string(from: e.updatedAt),
                    "title": e.title,
                    "body": e.body,
                    "tags": e.tags,
                    "mood": e.mood
                ] as [String: Any]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .withoutEscapingSlashes]) else {
            store.show("备份失败")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MDay备份-\(Fmt.day.string(from: Date())).json"
        panel.prompt = "备份"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                store.show("已生成备份")
            } catch {
                store.show("写入失败")
            }
        }
    }

    /// 把整个数据目录导出到用户选择的位置（其实就是复制 Markdown 文件夹）
    static func exportFolder(store: Store) {
        Exporter.backupJSON(store: store)
    }
}

extension Notification.Name {
    static let rjToast = Notification.Name("rj.toast")
}
