import Foundation
import SwiftUI

// MARK: - 天气类型

/// 日记里记录的天气。保存的是代号（如 rain），不是图标，方便跨设备与手工编辑。
enum WeatherKind: String, CaseIterable, Codable {
    case clear
    case partly
    case overcast
    case drizzle
    case rain
    case heavyRain
    case thunder
    case sleet
    case snow
    case fog
    case haze
    case windy
    case unknown

    /// 手动选择时列出的顺序（unknown 只用于解析失败兜底，不给用户选）
    static var pickable: [WeatherKind] {
        [.clear, .partly, .overcast, .drizzle, .rain, .heavyRain,
         .thunder, .snow, .sleet, .fog, .haze, .windy]
    }

    var name: String {
        switch self {
        case .clear: return "晴"
        case .partly: return "多云"
        case .overcast: return "阴"
        case .drizzle: return "小雨"
        case .rain: return "雨"
        case .heavyRain: return "大雨"
        case .thunder: return "雷阵雨"
        case .sleet: return "雨夹雪"
        case .snow: return "雪"
        case .fog: return "雾"
        case .haze: return "霾"
        case .windy: return "大风"
        case .unknown: return "未知"
        }
    }

    var symbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partly: return "cloud.sun.fill"
        case .overcast: return "cloud.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        case .sleet: return "cloud.sleet.fill"
        case .snow: return "cloud.snow.fill"
        case .fog: return "cloud.fog.fill"
        case .haze: return "sun.haze.fill"
        case .windy: return "wind"
        case .unknown: return "cloud.sun.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clear: return Color(red: 0.95, green: 0.62, blue: 0.10)
        case .partly: return Color(red: 0.42, green: 0.58, blue: 0.74)
        case .overcast: return Color(red: 0.47, green: 0.51, blue: 0.57)
        case .drizzle: return Color(red: 0.31, green: 0.60, blue: 0.80)
        case .rain: return Color(red: 0.19, green: 0.44, blue: 0.78)
        case .heavyRain: return Color(red: 0.12, green: 0.32, blue: 0.64)
        case .thunder: return Color(red: 0.55, green: 0.37, blue: 0.78)
        case .sleet, .snow: return Color(red: 0.36, green: 0.64, blue: 0.85)
        case .fog, .haze: return Color(red: 0.58, green: 0.55, blue: 0.49)
        case .windy: return Color(red: 0.40, green: 0.62, blue: 0.55)
        case .unknown: return Color.secondary
        }
    }

    /// WMO 天气代码 → 天气类型（Open-Meteo 用的是 WMO code）
    static func from(wmo code: Int) -> WeatherKind {
        switch code {
        case 0, 1: return .clear
        case 2: return .partly
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53, 55: return .drizzle
        case 56, 57, 66, 67: return .sleet      // 冻雨
        case 61, 63, 80, 81: return .rain
        case 65, 82: return .heavyRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunder
        default: return .unknown
        }
    }
}

// MARK: - 一条天气记录

struct WeatherInfo: Codable, Hashable {
    var kind: WeatherKind = .clear
    /// 摄氏度，手动选择时为 nil
    var temp: Double?
    var city: String = ""
    /// true = 自己挑的，false = 自动抓取的
    var isManual: Bool = false

    var icon: String { kind.symbol }
    var name: String { kind.name }

    /// 展示文案，例如「25° 多云」
    var summary: String {
        if let temp { return "\(Int(temp.rounded()))° \(kind.name)" }
        return kind.name
    }

    // MARK: front matter 编解码

    /// 写进 Markdown 顶部的紧凑写法：clear|24.7|北京|auto
    var frontMatterValue: String {
        var parts: [String] = [kind.rawValue]
        parts.append(temp.map { String(format: "%.1f", $0) } ?? "")
        parts.append(city)
        parts.append(isManual ? "manual" : "auto")
        while parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
        return parts.joined(separator: "|")
    }

    /// 解析 front matter 里的写法，容忍缺字段、多空格、大小写
    init?(frontMatter raw: String) {
        let text = raw.trimmed
        guard !text.isEmpty else { return nil }
        let parts = text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmed }
        guard let head = parts.first,
              let parsed = WeatherKind(rawValue: head.lowercased()),
              parsed != .unknown else { return nil }

        var w = WeatherInfo(kind: parsed)
        if parts.count > 1, !parts[1].isEmpty, let t = Double(parts[1]) { w.temp = t }
        if parts.count > 2, !parts[2].isEmpty { w.city = parts[2] }
        if parts.count > 3 { w.isManual = (parts[3].lowercased() == "manual") }
        self = w
    }

    init(kind: WeatherKind = .clear, temp: Double? = nil, city: String = "", isManual: Bool = false) {
        self.kind = kind
        self.temp = temp
        self.city = city
        self.isManual = isManual
    }
}

// MARK: - 错误

enum WeatherError: LocalizedError {
    case emptyCity
    case cityNotFound(String)
    case network(String)
    case badResponse

    var message: String {
        switch self {
        case .emptyCity: return "还没填城市"
        case .cityNotFound(let c): return "没找到城市「\(c)」，换个写法试试"
        case .network(let m): return "网络不通（\(m)）"
        case .badResponse: return "天气服务返回了看不懂的数据"
        }
    }

    var errorDescription: String? { message }
}

// MARK: - 天气服务（Open-Meteo，免 API Key）

enum WeatherService {

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// 抓取指定城市的实时天气
    static func fetch(city: String) async throws -> WeatherInfo {
        let name = city.trimmed
        guard !name.isEmpty else { throw WeatherError.emptyCity }
        let place = try await coordinate(for: name)

        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.lat)),
            URLQueryItem(name: "longitude", value: String(place.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = comps.url else { throw WeatherError.badResponse }
        let data = try await load(url)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let code = current["weather_code"] as? Int else {
            throw WeatherError.badResponse
        }

        var info = WeatherInfo(kind: WeatherKind.from(wmo: code))
        if let t = current["temperature_2m"] as? Double { info.temp = t }
        info.city = place.name
        info.isManual = false
        return info
    }

    // MARK: 内部

    /// 城市名 → 经纬度（结果缓存进 UserDefaults，避免每次请求都查一遍）
    private static func coordinate(for city: String) async throws -> (lat: Double, lon: Double, name: String) {
        let key = "rj.geo." + city
        if let cached = UserDefaults.standard.string(forKey: key) {
            let parts = cached.split(separator: "|").map(String.init)
            if parts.count == 3, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                return (lat, lon, parts[2])
            }
        }

        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { throw WeatherError.badResponse }
        let data = try await load(url)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first,
              let lat = first["latitude"] as? Double,
              let lon = first["longitude"] as? Double else {
            throw WeatherError.cityNotFound(city)
        }
        let resolved = (first["name"] as? String) ?? city
        UserDefaults.standard.set("\(lat)|\(lon)|\(resolved)", forKey: key)
        return (lat, lon, resolved)
    }

    private static func load(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw WeatherError.network("HTTP \(http.statusCode)")
            }
            return data
        } catch let e as WeatherError {
            throw e
        } catch {
            throw WeatherError.network(error.localizedDescription)
        }
    }
}
