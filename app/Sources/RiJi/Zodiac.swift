import Foundation

// MARK: - 星座与今日运势
//
// 星座（太阳星座）的日期区间是通行的西洋占星划分，各资料略有 ±1 天的出入
// （取决于当年交节时刻），这里用最常见的版本。
//
// ⚠️ 运势部分是**娱乐向**的：没有天文或统计依据，文案是按「星座 + 日期」
// 从本地文案库里取一条，同一天同一星座稳定不变，跨天才换。
// 这一点在界面上也如实写明，不装成有依据的预测。

struct ZodiacSign: Identifiable {
    var name: String          // 天秤座
    var emoji: String         // ♎
    var from: (Int, Int)      // 起始月日
    var to: (Int, Int)        // 结束月日
    var element: String       // 风象 / 火象 / 土象 / 水象

    /// 元组不满足 Equatable，所以用名字当 id —— 星座名本来就是唯一的
    var id: String { name }

    /// 「9/23 – 10/23」
    var dateRange: String { "\(from.0)/\(from.1) – \(to.0)/\(to.1)" }
}

/// 一天的运势
struct Fortune: Equatable {
    var summary: String
    var love: String
    var career: String
    var money: String
    var luckyColor: String
    var luckyNumber: Int
    var stars: Int            // 1...5，综合指数
}

enum Zodiac {

    static let signs: [ZodiacSign] = [
        ZodiacSign(name: "摩羯座", emoji: "♑", from: (12, 22), to: (1, 19), element: "土象"),
        ZodiacSign(name: "水瓶座", emoji: "♒", from: (1, 20), to: (2, 18), element: "风象"),
        ZodiacSign(name: "双鱼座", emoji: "♓", from: (2, 19), to: (3, 20), element: "水象"),
        ZodiacSign(name: "白羊座", emoji: "♈", from: (3, 21), to: (4, 19), element: "火象"),
        ZodiacSign(name: "金牛座", emoji: "♉", from: (4, 20), to: (5, 20), element: "土象"),
        ZodiacSign(name: "双子座", emoji: "♊", from: (5, 21), to: (6, 21), element: "风象"),
        ZodiacSign(name: "巨蟹座", emoji: "♋", from: (6, 22), to: (7, 22), element: "水象"),
        ZodiacSign(name: "狮子座", emoji: "♌", from: (7, 23), to: (8, 22), element: "火象"),
        ZodiacSign(name: "处女座", emoji: "♍", from: (8, 23), to: (9, 22), element: "土象"),
        ZodiacSign(name: "天秤座", emoji: "♎", from: (9, 23), to: (10, 23), element: "风象"),
        ZodiacSign(name: "天蝎座", emoji: "♏", from: (10, 24), to: (11, 22), element: "水象"),
        ZodiacSign(name: "射手座", emoji: "♐", from: (11, 23), to: (12, 21), element: "火象"),
    ]

    /// 某一天属于哪个太阳星座
    static func sign(for date: Date) -> ZodiacSign {
        let cal = Almanac.gregorian
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let key = m * 100 + d

        for s in signs {
            let a = s.from.0 * 100 + s.from.1
            let b = s.to.0 * 100 + s.to.1
            if a <= b {
                if key >= a && key <= b { return s }
            } else {
                // 跨年区间（摩羯座）：12/22 – 1/19
                if key >= a || key <= b { return s }
            }
        }
        return signs[0]
    }

    /// 按月日算星座（给「生日」这种没有年份的输入用）
    static func sign(month: Int, day: Int) -> ZodiacSign? {
        guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        let key = month * 100 + day
        for s in signs {
            let a = s.from.0 * 100 + s.from.1
            let b = s.to.0 * 100 + s.to.1
            if a <= b {
                if key >= a && key <= b { return s }
            } else {
                if key >= a || key <= b { return s }
            }
        }
        return nil
    }

    static func sign(named name: String) -> ZodiacSign? {
        signs.first { $0.name == name }
    }

    /// 从设置里那行生日文本解出星座。
    /// 认「1992-06-23」「1992/6/23」「06-23」「19920623」这几种写法，
    /// 认不出来就返回 nil（界面会退回显示当天的太阳星座）。
    static func sign(fromBirthday text: String) -> ZodiacSign? {
        let t = text.trimmed
        guard !t.isEmpty else { return nil }
        let parts = t.split(whereSeparator: { !$0.isNumber }).map(String.init)

        if parts.count >= 2 {
            let m = Int(parts[parts.count - 2]) ?? 0
            let d = Int(parts[parts.count - 1]) ?? 0
            return sign(month: m, day: d)
        }
        // 纯 8 位数字：19920623
        if parts.count == 1, parts[0].count == 8 {
            let s = parts[0]
            let m = Int(s.dropFirst(4).prefix(2)) ?? 0
            let d = Int(s.suffix(2)) ?? 0
            return sign(month: m, day: d)
        }
        return nil
    }

    // MARK: - 文案库（娱乐向）

    private static let summaryPool = [
        "今天适合把拖了很久的那件事往前推一格，不用推完。",
        "别急着解释自己，懂的人不需要，不懂的人听不进去。",
        "会有一件小事让你心情变好，记得留意它。",
        "今天的信息量偏大，挑重要的记住，其余随风。",
        "适合整理：桌面、文件夹、或者是脑子里的待办。",
        "有人会向你求助，帮得上就帮，帮不上直说。",
        "今天适合做决定，但别做不可逆的决定。",
        "把「我应该」换成「我想」，今天的效率会更高。",
        "会想起一个很久没联系的人，想起就够了。",
        "今天适合少说多听，你会听到有用的东西。",
        "情绪起伏比平时明显，先承认它，再处理事情。",
        "有一笔小开销是值得的，别为此内耗。",
        "今天适合换个环境做事，哪怕只是换张桌子。",
        "别人对你的评价今天格外不准，别太当回事。",
        "适合给一件做久了的事收个尾。",
        "今天遇到的拖延，多半是因为事情没被拆小。",
        "会有意外的收获，来自你顺手做的一件小事。",
        "今天适合确认细节，你之前觉得「应该没问题」的地方要再看一眼。",
        "把手机放远一点，今天你会因此多出一小时。",
        "适合说一句真话，哪怕只是对自己说。",
        "今天的运气偏向「已经开始的人」，先动手。",
        "会有个小误会，早说一句就散了。",
        "今天适合补觉，或者至少早点放下手机。",
        "你比昨天更接近那个你想成为的人，虽然看不出来。",
    ]

    private static let lovePool = [
        "有话直说，今天对方接得住。",
        "别把猜测当结论。",
        "适合一起做件小事，比说很多话有用。",
        "今天需要一点独处的空间，说明白就好。",
        "旧的情绪今天可能翻上来，让它过去。",
        "一句具体的夸奖，比十句客套管用。",
        "适合把「你从来不」换成「我希望」。",
        "今天不必勉强社交，安静也是相处方式。",
        "有人在默默观察你的好，今天会被看见。",
        "界限清楚一点，关系反而轻松。",
        "今天适合原谅一件小事，包括原谅自己。",
        "别在情绪最高点做判断。",
    ]

    private static let careerPool = [
        "先做最难的那件，今天的专注力够用。",
        "把想法写成字，说出口的时候会清楚很多。",
        "今天适合问问题，别自己扛着猜。",
        "会有人给你一个反馈，先听完再回应。",
        "今天适合推进流程，不适合开启新的。",
        "把「做完」和「做好」分开，今天先做完。",
        "你的判断今天偏准，可以信一次直觉。",
        "适合把手上的事分个优先级，别平均用力。",
        "今天不必证明什么，把事做完就是最好的证明。",
        "遇到卡点，换个问法就有答案。",
        "适合跟同行聊两句，信息比努力值钱。",
        "今天的成果可能不显眼，但它在累积。",
    ]

    private static let moneyPool = [
        "今天适合记账，不适合下单。",
        "有一笔支出可以再放 24 小时再决定。",
        "别为省小钱花大力气。",
        "今天的判断偏乐观，大额决定往后挪一挪。",
        "适合把订阅服务过一遍，砍掉不用的。",
        "会把钱花在让自己变好的地方，这笔值得。",
        "今天的运气偏向「先攒后花」。",
        "别听信来路太顺的赚钱机会。",
        "适合算一次「时薪」，你会重新安排优先级。",
        "小额投入今天回报不错，大额先观望。",
        "会有一笔意料之外的进账或退款。",
        "今天的理财建议来自你自己，安静想想。",
    ]

    private static let colors = ["珊瑚橘", "雾霾蓝", "奶油白", "沉香棕", "抹茶绿", "藕荷紫",
                                 "蜜桃粉", "石青灰", "琥珀金", "月白", "砖红", "青竹绿"]

    /// 今日运势。同一天同一星座稳定不变。
    static func fortune(for sign: ZodiacSign, date: Date) -> Fortune {
        let calm = Almanac.gregorian
        let day = calm.ordinality(of: .day, in: .year, for: date) ?? 1
        let year = calm.component(.year, from: date)
        let idx = signs.firstIndex { $0.name == sign.name } ?? 0

        // 换个种子来源，免得四项运势跟着同一条文案一起跳
        func pick(_ pool: [String], _ salt: Int) -> String {
            guard !pool.isEmpty else { return "" }
            let seed = day &* 17 &+ year &* 3 &+ idx &* 29 &+ salt
            return pool[((seed % pool.count) + pool.count) % pool.count]
        }

        let seed = day &* 13 &+ year &* 5 &+ idx &* 31
        let stars = ((seed % 5) + 5) % 5 + 1
        let number = ((seed % 9) + 9) % 9 + 1

        return Fortune(
            summary: pick(summaryPool, 1),
            love: pick(lovePool, 2),
            career: pick(careerPool, 3),
            money: pick(moneyPool, 4),
            luckyColor: colors[((seed % colors.count) + colors.count) % colors.count],
            luckyNumber: number,
            stars: stars
        )
    }

    /// 星座图标：SF Symbols 里没有现成的占星符号，用系统自带的行星符号更省事
    static func symbol(for sign: ZodiacSign) -> String {
        "sparkles"
    }
}
