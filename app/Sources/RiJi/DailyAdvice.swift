import SwiftUI

// MARK: - 今日一句
//
// 内容来自凯文·凯利《宝贵的人生建议》和松浦弥太郎《100 个基本》，
// 两本轮换着出（原始条目见 LifeAdvice.swift / Basic100.swift）。
//
// 为什么不做成「每次打开随机一句」：那样每刷新一次就换一句，读的人还没记住
// 就跑了，反而像广告位。这里按「年内日序 + 年份」取模 —— 同一天无论重开几次
// 都是同一句，跨年才会换。想换就自己点，属于「今天这次会话内」的临时偏移，
// 明天自动回到按天那一条。

/// 侧边栏里的紧凑卡片。空间有限，长句子会截断，鼠标悬停看全文。
struct DailyAdviceCard: View {

    /// 点了几次「换一句」。不落盘 —— 明天要回到按天那条。
    @State private var offset = 0
    @State private var hovering = false

    /// 今天这一句，连出处一起取 —— 出处得跟着句子走，
    /// 金句现在有两个来源（凯文·凯利 / 松浦弥太郎），写死一个会标错。
    private var quote: DailyQuote { LifeAdvice.quote(offset: offset) }
    /// 面板变窄时字体不跟着缩，否则长句会挤成一条黑线
    private var full: String { quote.text }
    /// 卡片里实际显示的版本：按字数截到 `LifeAdvice.cardCharLimit`，
    /// 全文挂在悬停提示里。截断用字数而不是行数，理由见 LifeAdvice.cardCharLimit。
    private var advice: String { LifeAdvice.cardText(full) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "quote.opening")
                    .font(.rj(9.5, weight: .bold))
                    .foregroundStyle(Color.rjAccent.opacity(0.75))
                Text("今日一句")
                    .font(.rj(10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                // 常驻显示，只是平时淡一点。藏在 hover 里的话，
                // 不把鼠标移上去根本不知道这里能点。
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { offset += 1 }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.rj(10.5, weight: .medium))
                        .foregroundStyle(Color.rjAccent.opacity(hovering ? 1 : 0.55))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("换一句")
            }

            Text(advice)
                .font(.rj(11.5))
                .foregroundStyle(.primary.opacity(0.84))
                .lineSpacing(2.5)
                .multilineTextAlignment(.leading)
                // 不再限行数 —— 长度由 LifeAdvice.cardCharLimit 的字数上限兜住，
                // 行数限制会跟着字号档位浮动，量不准。
                // 但**保底上限必须留着**：SwiftUI 算「理想高度」时是用零宽度量的，
                // fixedSize(vertical: true) 的 Text 没有 lineLimit 的话，
                // 115 个字会折成一百多行，把卡片理想高度撑到上千 pt ——
                // NavigationSplitView 跟着自算出 1128pt 的身高在窗口里居中，
                // 顶部被红绿灯压住、底部「写日记 / 设置」整条被裁出窗外（2026-09-25 实锤）。
                // 12 行是渲染兜底：正常档位 115 字只要 4–6 行，特大字号 + 最窄侧边栏也才 10 行。
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                .help(full)
                // 换一句时让文字有个淡入，不至于「啪」地跳一下
                .id(offset)
                .transition(.opacity)

            // 出处。侧边栏窄，字号再收一档、允许缩一点点，保证一行放得下
            Text(quote.sourceLine)
                .font(.rj(10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RJ.rowRadius, style: .continuous)
                .fill(Color.rjAccent.opacity(hovering ? 0.10 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RJ.rowRadius, style: .continuous)
                .strokeBorder(Color.rjAccent.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

/// 宽版：给「关于」这类有整片留白的地方用，字号大一点、可以看全。
struct DailyAdviceBanner: View {
    @State private var offset = 0

    private var quote: DailyQuote { LifeAdvice.quote(offset: offset) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.rj(11, weight: .bold))
                    .foregroundStyle(Color.rjAccent.opacity(0.8))
                Text("今日一句")
                    .font(.rj(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { offset += 1 }
                } label: {
                    Label("换一句", systemImage: "arrow.triangle.2.circlepath")
                        .font(.rj(11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.rjAccent)
            }

            Text(quote.text)
                .font(.rj(14))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .id(offset)
                .transition(.opacity)

            Text(quote.sourceLine)
                .font(.rj(11.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.rjAccent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.rjAccent.opacity(0.15), lineWidth: 1)
        )
    }
}
