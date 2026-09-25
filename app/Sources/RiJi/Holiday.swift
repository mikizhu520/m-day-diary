import Foundation

// MARK: - 法定节假日与调休
//
// 数据来源：国务院办公厅《关于××年部分节假日安排的通知》
//   · 2024 年 https://www.gov.cn/yaowen/liebiao/202310/content_6911540.htm
//   · 2025 年 https://www.gov.cn/zhengce/zhengceku/202411/content_6986383.htm
//   · 2026 年 https://www.gov.cn/gongbao/2025/issue_12406/202511/content_7048922.html
//
// 为什么写死在代码里而不是联网取：
//   放假安排一年才出一次（一般前一年 11 月发布），联网取的成本远大于收益，
//   而且本地没有网的时候也得能看。没有收录的年份就老实显示「未收录」，
//   不猜、不外推 —— 调休凑出来的安排没法用规律推。

/// 某一天在放假安排里的身份
struct HolidayMark: Equatable {
    /// 所属节日，如「春节」
    var name: String
    /// true = 放假；false = 调休上班（周末要补班）
    var isRest: Bool

    /// 展示用文案：「春节假期」「春节调休」
    var label: String { isRest ? "\(name)假期" : "\(name)调休" }
}

enum Holiday {

    /// 放假区间（同一年内，含首尾）
    private struct RestSpan {
        var name: String
        var from: (Int, Int)
        var to: (Int, Int)
    }

    /// 调休上班的单独日子
    private struct Workday {
        var name: String
        var date: (Int, Int)
    }

    private static let table: [Int: (rests: [RestSpan], works: [Workday])] = [
        2024: (
            rests: [
                RestSpan(name: "元旦", from: (1, 1), to: (1, 1)),
                RestSpan(name: "春节", from: (2, 10), to: (2, 17)),
                RestSpan(name: "清明节", from: (4, 4), to: (4, 6)),
                RestSpan(name: "劳动节", from: (5, 1), to: (5, 5)),
                RestSpan(name: "端午节", from: (6, 8), to: (6, 10)),
                RestSpan(name: "中秋节", from: (9, 15), to: (9, 17)),
                RestSpan(name: "国庆节", from: (10, 1), to: (10, 7)),
            ],
            works: [
                Workday(name: "春节", date: (2, 4)),
                Workday(name: "春节", date: (2, 18)),
                Workday(name: "清明节", date: (4, 7)),
                Workday(name: "劳动节", date: (4, 28)),
                Workday(name: "劳动节", date: (5, 11)),
                Workday(name: "中秋节", date: (9, 14)),
                Workday(name: "国庆节", date: (9, 29)),
                Workday(name: "国庆节", date: (10, 12)),
            ]
        ),
        2025: (
            rests: [
                RestSpan(name: "元旦", from: (1, 1), to: (1, 1)),
                RestSpan(name: "春节", from: (1, 28), to: (2, 4)),
                RestSpan(name: "清明节", from: (4, 4), to: (4, 6)),
                RestSpan(name: "劳动节", from: (5, 1), to: (5, 5)),
                RestSpan(name: "端午节", from: (5, 31), to: (6, 2)),
                RestSpan(name: "国庆节·中秋节", from: (10, 1), to: (10, 8)),
            ],
            works: [
                Workday(name: "春节", date: (1, 26)),
                Workday(name: "春节", date: (2, 8)),
                Workday(name: "劳动节", date: (4, 27)),
                Workday(name: "国庆节", date: (9, 28)),
                Workday(name: "国庆节", date: (10, 11)),
            ]
        ),
        2026: (
            rests: [
                RestSpan(name: "元旦", from: (1, 1), to: (1, 3)),
                RestSpan(name: "春节", from: (2, 15), to: (2, 23)),
                RestSpan(name: "清明节", from: (4, 4), to: (4, 6)),
                RestSpan(name: "劳动节", from: (5, 1), to: (5, 5)),
                RestSpan(name: "端午节", from: (6, 19), to: (6, 21)),
                RestSpan(name: "中秋节", from: (9, 25), to: (9, 27)),
                RestSpan(name: "国庆节", from: (10, 1), to: (10, 7)),
            ],
            works: [
                Workday(name: "元旦", date: (1, 4)),
                Workday(name: "春节", date: (2, 14)),
                Workday(name: "春节", date: (2, 28)),
                Workday(name: "劳动节", date: (5, 9)),
                Workday(name: "国庆节", date: (9, 20)),
                Workday(name: "国庆节", date: (10, 10)),
            ]
        ),
    ]

    /// 收录了哪些年份
    static var availableYears: [Int] { table.keys.sorted() }

    /// 这一天是放假、补班，还是普通日子
    static func mark(_ date: Date) -> HolidayMark? {
        let cal = Almanac.gregorian
        let year = cal.component(.year, from: date)
        guard let entry = table[year] else { return nil }
        let md = (cal.component(.month, from: date), cal.component(.day, from: date))

        for w in entry.works where w.date == md {
            return HolidayMark(name: w.name, isRest: false)
        }
        for r in entry.rests where inSpan(md, r.from, r.to) {
            return HolidayMark(name: r.name, isRest: true)
        }
        return nil
    }

    private static func inSpan(_ md: (Int, Int), _ from: (Int, Int), _ to: (Int, Int)) -> Bool {
        func key(_ t: (Int, Int)) -> Int { t.0 * 100 + t.1 }
        return key(md) >= key(from) && key(md) <= key(to)
    }

    /// 这一年有没有收录。没有的话界面上要老实说明，不能装作「这天不放假」。
    static func hasData(for year: Int) -> Bool { table[year] != nil }

    /// 某年所有放假日（用来在日历上打点）
    static func restDays(inYear year: Int) -> [Date] {
        guard let entry = table[year] else { return [] }
        var out: [Date] = []
        for r in entry.rests {
            var md = r.from
            while key(md) <= key(r.to) {
                var comps = DateComponents()
                comps.year = year
                comps.month = md.0
                comps.day = md.1
                comps.hour = 12
                if let d = Almanac.gregorian.date(from: comps) {
                    out.append(Almanac.gregorian.startOfDay(for: d))
                }
                md = nextDay(md)
            }
        }
        return out
    }

    private static func key(_ t: (Int, Int)) -> Int { t.0 * 100 + t.1 }

    private static func nextDay(_ md: (Int, Int)) -> (Int, Int) {
        var comps = DateComponents()
        comps.year = 2001          // 用平年推，2 月按 28 天；跨月够用
        comps.month = md.0
        comps.day = md.1
        comps.hour = 12
        guard let d = Almanac.gregorian.date(from: comps),
              let n = Almanac.gregorian.date(byAdding: .day, value: 1, to: d) else { return (md.0, md.1 + 1) }
        return (Almanac.gregorian.component(.month, from: n), Almanac.gregorian.component(.day, from: n))
    }
}
