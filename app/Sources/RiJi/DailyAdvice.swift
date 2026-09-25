import SwiftUI

// MARK: - 今日一句
//
// 内容来自凯文·凯利《宝贵的人生建议》（原始条目见 LifeAdvice.swift）。
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

    /// 面板变窄时字体不跟着缩，否则长句会挤成一条黑线
    private var advice: String { LifeAdvice.today(offset: offset) }

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
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .help(advice)
                // 换一句时让文字有个淡入，不至于「啪」地跳一下
                .id(offset)
                .transition(.opacity)
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

            Text(LifeAdvice.today(offset: offset))
                .font(.rj(14))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .id(offset)
                .transition(.opacity)
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
