import Foundation

// MARK: - 农历 · 黄历
//
// 全部本地推算，不联网。每一项的依据都写在下面，不是拍脑袋凑的：
//
//   · 农历月日 —— Foundation 的 Calendar(identifier: .chinese)，系统内置农历表
//   · 二十四节气 —— Meeus《Astronomical Algorithms》太阳视黄经低精度公式，
//                   再用牛顿迭代求黄经等于 15°×n 的时刻
//   · 干支纪日 —— 锚点：1949-10-01 为甲子日。这是《农历的编算和颁行》规定的
//                 干支纪日循环参考点（见华东师大《六十干支周纪时系统及公式的构建》）
//   · 干支纪年 —— 以立春为界，1984 年为甲子年（公认锚点）
//   · 黄黑道十二神 —— 《协纪辨方书》《玉匣记》口诀：
//                 「寅申须加子，卯酉却居寅，辰戌龙位上，巳亥午上存，
//                   子午临申地，丑未戌相寻」
//   · 建除十二神 —— 月建与日支同支为「建」，顺行十二神
//   · 宜忌 —— 民间通行说法，各流派并不一致。这里只作参考，不是命理依据。
//
// 时区固定东八区：农历、节气、干支都以北京时间为准。

/// 某一天的农历 / 黄历信息
struct AlmanacDay: Equatable {
    var date: Date = Date()

    // 农历
    var lunarMonthName = ""      // 八月 / 闰六月
    var lunarDayName = ""        // 十五
    var lunarYearGanzhi = ""     // 丙午
    var zodiac = ""              // 马

    // 干支
    var dayGanzhi = ""           // 壬寅
    var monthGanzhi = ""         // 丁酉
    var monthBranch = 0          // 月支序（0=子）

    // 节气
    var term = ""                // 当天正好是节气，填名称；否则空
    var nextTerm = ""            // 下一个节气
    var daysToNextTerm = 0       // 离下一个节气还有几天

    // 黄历
    var officer = ""             // 建除十二神：建 / 除 / … / 闭
    var deity = ""               // 黄黑道十二神：青龙 / 明堂 / …
    var isYellowRoad = false     // 是不是黄道吉日
    var suitable: [String] = []  // 宜
    var avoid: [String] = []     // 忌
    var clashZodiac = ""         // 冲什么生肖

    // 节日
    var festivals: [String] = []

    /// 一行式农历：「八月十五」
    var lunarText: String { lunarMonthName + lunarDayName }

    /// 一行式干支：「丙午年 丁酉月 壬寅日」
    var ganzhiLine: String { "\(lunarYearGanzhi)年 \(monthGanzhi)月 \(dayGanzhi)日" }
}

enum Almanac {

    // MARK: - 基础表

    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    static let lunarMonthNames = ["正月", "二月", "三月", "四月", "五月", "六月",
                                  "七月", "八月", "九月", "十月", "冬月", "腊月"]

    static let solarTermNames = ["小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
                                 "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
                                 "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
                                 "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"]

    static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }()

    static let chinese: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.timeZone = timeZone
        return c
    }()

    // MARK: - 二十四节气

    /// 二十四节气：名字 / 太阳黄经 / 公历近似日期（近似值只用来做牛顿迭代的初值）
    private static let termLon: [Double] = [285, 300, 315, 330, 345, 0,
                                            15, 30, 45, 60, 75, 90,
                                            105, 120, 135, 150, 165, 180,
                                            195, 210, 225, 240, 255, 270]
    private static let termApprox: [(Int, Int)] = [(1, 6), (1, 20), (2, 4), (2, 19), (3, 6), (3, 21),
                                                   (4, 5), (4, 20), (5, 6), (5, 21), (6, 6), (6, 21),
                                                   (7, 7), (7, 23), (8, 8), (8, 23), (9, 8), (9, 23),
                                                   (10, 8), (10, 23), (11, 7), (11, 22), (12, 7), (12, 22)]

    /// 节气日期缓存。UI 每帧都可能问「今天是什么节气」，不能每次重算。
    private static var termCache: [Int: [Date]] = [:]

    /// 太阳视黄经（度，0..360）
    private static func sunLongitude(jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525.0
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        let mr = m * .pi / 180
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(mr)
              + (0.019993 - 0.000101 * t) * sin(2 * mr)
              + 0.000289 * sin(3 * mr)
        var lambda = l0 + c
        // 章动 + 光行差修正
        let omega = 125.04 - 1934.136 * t
        lambda -= 0.00569 + 0.00478 * sin(omega * .pi / 180)
        return (lambda.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 儒略日
    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// 求太阳黄经等于 target 的时刻（牛顿迭代；太阳每天走约 0.9856°）
    private static func solve(target: Double, guess: Double) -> Double {
        var jd = guess
        for _ in 0..<20 {
            var diff = sunLongitude(jd: jd) - target
            while diff > 180 { diff -= 360 }
            while diff < -180 { diff += 360 }
            jd -= diff / 0.9856473
        }
        return jd
    }

    /// 某年 24 个节气的日期（北京时间，按当天 0 点归到所在日）
    static func solarTerms(ofYear year: Int) -> [Date] {
        if let hit = termCache[year] { return hit }
        var out: [Date] = []
        for i in 0..<24 {
            var comps = DateComponents()
            comps.year = year
            comps.month = termApprox[i].0
            comps.day = termApprox[i].1
            comps.hour = 12
            guard let guess = gregorian.date(from: comps) else { continue }
            let jd = solve(target: termLon[i], guess: julianDay(guess))
            let at = Date(timeIntervalSince1970: (jd - 2440587.5) * 86400.0)
            out.append(gregorian.startOfDay(for: at))
        }
        termCache[year] = out
        return out
    }

    /// 某年第 index 个节气的日期（0 = 小寒）
    static func solarTermDate(year: Int, index: Int) -> Date? {
        let all = solarTerms(ofYear: year)
        guard index >= 0, index < all.count else { return nil }
        return all[index]
    }

    /// 立春（干支年的分界）
    static func startOfGanzhiYear(_ solarYear: Int) -> Date? {
        solarTermDate(year: solarYear, index: 2)   // 2 = 立春
    }

    // MARK: - 干支

    /// 干支纪日：以 1949-10-01 = 甲子日为锚点
    static func dayGanzhiIndex(_ date: Date) -> Int {
        let anchor = 2433191   // 1949-10-01 的儒略日数（正午）
        let jd = gregorianJDN(gregorian.startOfDay(for: date))
        return ((jd - anchor) % 60 + 60) % 60
    }

    /// 公历日 → 儒略日数
    static func gregorianJDN(_ date: Date) -> Int {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2000, m = c.month ?? 1, d = c.day ?? 1
        let a = (14 - m) / 12
        let yy = y + 4800 - a
        let mm = m + 12 * a - 3
        return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
    }

    /// 干支纪年：以立春为界，1984 年为甲子年
    static func yearGanzhiIndex(_ date: Date) -> Int {
        let cy = gregorian.component(.year, from: date)
        var y = cy
        if let lichun = startOfGanzhiYear(cy), date < lichun { y = cy - 1 }
        return ((y - 1984) % 60 + 60) % 60
    }

    /// 月支：按节气划分（立春起寅月）
    static func monthBranchIndex(_ date: Date) -> Int {
        latestTermBranch(date) ?? 1
    }

    /// 找出「最近一个已经过去的节」对应的月支
    ///
    /// 十二个月的界是「节」不是「气」：立春、惊蛰、清明、立夏、芒种、小暑、
    /// 立秋、白露、寒露、立冬、大雪、小寒 —— 正好是节气表里的偶数位。
    private static func latestTermBranch(_ date: Date) -> Int? {
        let cy = gregorian.component(.year, from: date)
        var best: (Date, Int)?
        for year in [cy - 1, cy, cy + 1] {
            let terms = solarTerms(ofYear: year)
            for i in stride(from: 0, to: 24, by: 2) {     // 只看「节」
                guard i < terms.count else { continue }
                let d = terms[i]
                if d <= date, best == nil || d > best!.0 {
                    best = (d, (i / 2 + 1) % 12)
                }
            }
        }
        return best?.1
    }

    /// 干支纪月：月支定了，月干由年干推（五虎遁：甲己之年丙作首）
    static func monthGanzhiIndex(_ date: Date) -> Int {
        let yg = yearGanzhiIndex(date) % 10          // 年干
        let yinStem = ((yg % 5) * 2 + 2) % 10        // 寅月的天干
        let branch = monthBranchIndex(date)          // 0=子 … 2=寅
        let offset = ((branch - 2) % 12 + 12) % 12
        let stem = (yinStem + offset) % 10
        // 月干支的 60 循环序号：天干为 stem、地支为 branch
        for n in 0..<60 where n % 10 == stem && n % 12 == branch { return n }
        return 0
    }

    /// 由 60 序号取「甲子」这样的字符串
    static func ganzhi(_ index: Int) -> String {
        let n = ((index % 60) + 60) % 60
        return stems[n % 10] + branches[n % 12]
    }

    // MARK: - 建除十二神 / 黄黑道十二神

    static let officers = ["建", "除", "满", "平", "定", "执", "破", "危", "成", "收", "开", "闭"]

    /// 建除十二神：月建与日支同支为「建」，顺行
    static func officerIndex(_ date: Date) -> Int {
        let mb = monthBranchIndex(date)
        let db = dayGanzhiIndex(date) % 12
        return ((db - mb) % 12 + 12) % 12
    }

    static let deities = ["青龙", "明堂", "天刑", "朱雀", "金匮", "天德",
                          "白虎", "玉堂", "天牢", "玄武", "司命", "勾陈"]

    /// 黄道六神（其余为黑道）
    static let yellowDeities: Set<String> = ["青龙", "明堂", "金匮", "天德", "玉堂", "司命"]

    /// 青龙起于哪一支 —— 《协纪辨方书》口诀
    static func deityStartBranch(monthBranch: Int) -> Int {
        switch monthBranch {
        case 2, 8:   return 0    // 寅申月，子日起青龙
        case 3, 9:   return 2    // 卯酉月，寅日起青龙
        case 4, 10:  return 4    // 辰戌月，辰日起青龙
        case 5, 11:  return 6    // 巳亥月，午日起青龙
        case 0, 6:   return 8    // 子午月，申日起青龙
        default:     return 10   // 丑未月，戌日起青龙
        }
    }

    /// 十二值神
    static func deityIndex(_ date: Date) -> Int {
        let mb = monthBranchIndex(date)
        let db = dayGanzhiIndex(date) % 12
        let start = deityStartBranch(monthBranch: mb)
        return ((db - start) % 12 + 12) % 12
    }

    // MARK: - 宜忌（民间通行说法）

    private static let officerSuitable: [String: [String]] = [
        "建": ["出行", "赴任", "会友", "上书", "见工"],
        "除": ["除服", "疗病", "扫舍", "解除", "出行"],
        "满": ["祭祀", "祈福", "开市", "纳财", "结网"],
        "平": ["修饰垣墙", "平治道涂", "整理内务", "交易"],
        "定": ["嫁娶", "纳采", "冠带", "修造", "安床"],
        "执": ["捕捉", "纳畜", "修造", "造屋", "祈福"],
        "破": ["破屋", "坏垣", "求医", "治病"],
        "危": ["安床", "祭祀", "祈福", "安葬"],
        "成": ["嫁娶", "开市", "入学", "立券", "动土"],
        "收": ["纳财", "开市", "交易", "纳畜", "进人口"],
        "开": ["祭祀", "入学", "开市", "动土", "修造"],
        "闭": ["筑堤", "埋穴", "补垣", "塞穴"],
    ]

    private static let officerAvoid: [String: [String]] = [
        "建": ["动土", "开仓", "嫁娶", "纳采"],
        "除": ["求财", "开市", "动土", "签约"],
        "满": ["嫁娶", "移徙", "赴任", "服药"],
        "平": ["祈福", "求嗣", "开渠", "掘井"],
        "定": ["诉讼", "出行", "移徙", "开仓"],
        "执": ["开市", "移徙", "出财", "开仓"],
        "破": ["嫁娶", "开市", "动土", "签约"],
        "危": ["登高", "乘船", "出行", "赴任"],
        "成": ["诉讼", "掘井", "栽种"],
        "收": ["开仓", "出货", "安葬", "破土"],
        "开": ["安葬", "破土", "放水"],
        "闭": ["开市", "出行", "求医", "开渠"],
    ]

    // MARK: - 农历日名 / 月名

    static func lunarDayName(_ day: Int) -> String {
        let ones = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        switch day {
        case 1...10:  return "初" + ones[day]
        case 11...19: return "十" + ones[day - 10]
        case 20:      return "二十"
        case 21...29: return "廿" + ones[day - 20]
        case 30:      return "三十"
        default:      return "\(day)"
        }
    }

    // MARK: - 节日

    /// 农历节日（月, 日）→ 名称。闰月不算。
    private static let lunarFestivals: [String: String] = [
        "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头",
        "5-5": "端午节", "7-7": "七夕", "7-15": "中元节",
        "8-15": "中秋节", "9-9": "重阳节", "12-8": "腊八节", "12-23": "小年",
    ]

    /// 公历节日（月, 日）→ 名称
    private static let solarFestivals: [String: String] = [
        "1-1": "元旦", "2-14": "情人节", "3-8": "妇女节", "3-12": "植树节",
        "5-1": "劳动节", "5-4": "青年节", "5-12": "护士节", "6-1": "儿童节",
        "7-1": "建党节", "8-1": "建军节", "9-10": "教师节", "10-1": "国庆节",
        "12-24": "平安夜", "12-25": "圣诞节",
    ]

    // MARK: - 主入口

    /// 日历一屏要问 42 天，编辑器还会反复重绘 —— 不缓存的话每次都重算农历表
    private static var dayCache: [String: AlmanacDay] = [:]

    /// 算这一天的农历与黄历
    static func day(_ date: Date) -> AlmanacDay {
        let key = Fmt.day.string(from: gregorian.startOfDay(for: date))
        if let hit = dayCache[key] { return hit }
        let out = compute(date)
        // 简单限容：攒够就清空重来，翻几个月日历也攒不满
        if dayCache.count > 900 { dayCache.removeAll() }
        dayCache[key] = out
        return out
    }

    private static func compute(_ date: Date) -> AlmanacDay {
        var out = AlmanacDay()
        let d0 = gregorian.startOfDay(for: date)
        out.date = d0

        // 农历
        let c = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: d0)
        let lm = c.month ?? 1
        let ld = c.day ?? 1
        let leap = c.isLeapMonth ?? false
        if lm >= 1, lm <= 12 {
            out.lunarMonthName = (leap ? "闰" : "") + lunarMonthNames[lm - 1]
        } else {
            out.lunarMonthName = "\(lm)月"
        }
        out.lunarDayName = lunarDayName(ld)

        // 干支
        let yIdx = yearGanzhiIndex(d0)
        out.lunarYearGanzhi = ganzhi(yIdx)
        out.zodiac = zodiacs[yIdx % 12]
        out.dayGanzhi = ganzhi(dayGanzhiIndex(d0))
        out.monthGanzhi = ganzhi(monthGanzhiIndex(d0))
        out.monthBranch = monthBranchIndex(d0)

        // 节气
        let cy = gregorian.component(.year, from: d0)
        var upcoming: [(Date, String)] = []
        for year in [cy - 1, cy, cy + 1] {
            let terms = solarTerms(ofYear: year)
            for i in 0..<min(24, terms.count) { upcoming.append((terms[i], solarTermNames[i])) }
        }
        upcoming.sort { $0.0 < $1.0 }
        if let today = upcoming.first(where: { gregorian.isDate($0.0, inSameDayAs: d0) }) {
            out.term = today.1
        }
        if let next = upcoming.first(where: { $0.0 > d0 }) {
            out.nextTerm = next.1
            let days = gregorian.dateComponents([.day], from: d0, to: next.0).day ?? 0
            out.daysToNextTerm = max(0, days)
        }

        // 黄历
        let oi = officerIndex(d0)
        out.officer = officers[oi]
        let di = deityIndex(d0)
        out.deity = deities[di]
        out.isYellowRoad = yellowDeities.contains(out.deity)
        out.suitable = officerSuitable[out.officer] ?? []
        out.avoid = officerAvoid[out.officer] ?? []
        out.clashZodiac = zodiacs[(dayGanzhiIndex(d0) % 12 + 6) % 12]

        // 节日
        var fes: [String] = []
        if !leap, let f = lunarFestivals["\(lm)-\(ld)"] { fes.append(f) }
        if let f = solarFestivals["\(gregorian.component(.month, from: d0))-\(gregorian.component(.day, from: d0))"] {
            fes.append(f)
        }
        if out.term == "清明" { fes.append("清明节") }
        // 除夕：农历腊月，且次日就是正月初一
        if lm == 12, let tomorrow = gregorian.date(byAdding: .day, value: 1, to: d0) {
            let tc = chinese.dateComponents([.month, .day], from: tomorrow)
            if tc.month == 1 && tc.day == 1 { fes.append("除夕") }
        }
        out.festivals = fes

        return out
    }

    // MARK: - 摘要文案

    /// 给 UI 用的短标签，比如「八月十五」「十五」
    static func shortLunar(_ date: Date) -> String {
        let d = day(date)
        // 初一直接显示月名，信息量更大（八月十五 → 八月十五；正月初一 → 正月初一）
        if d.lunarDayName == "初一" { return d.lunarText }
        return d.lunarDayName
    }
}
