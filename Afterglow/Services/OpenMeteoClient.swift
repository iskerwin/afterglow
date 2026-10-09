import Foundation

/// Open-Meteo 免费天气 API（无需 Key，CC BY 4.0）
/// 文档：https://open-meteo.com/en/docs
enum OpenMeteoClient {
    struct APIError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private struct Response: Decodable {
        var latitude: Double
        var longitude: Double
        var utcOffsetSeconds: Int?
        var timezone: String?
        var hourly: Hourly?
    }

    private struct Hourly: Decodable {
        var time: [Double]
        var cloudCoverLow: [Double?]?
        var cloudCoverMid: [Double?]?
        var cloudCoverHigh: [Double?]?
        var relativeHumidity2m: [Double?]?
        var visibility: [Double?]?
        var precipitation: [Double?]?
        var aerosolOpticalDepth: [Double?]?
    }

    private struct ErrorBody: Decodable { var reason: String? }

    static let cloudVariables = [
        "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
        "relative_humidity_2m", "visibility", "precipitation",
    ]

    enum Range {
        case relative(pastDays: Int, forecastDays: Int)
        case dates(start: String, end: String)   // yyyy-MM-dd（地点本地日期）
    }

    /// 网格：按纬度升序、经度升序排列
    struct GridSpec {
        var lats: [Double]
        var lons: [Double]

        static func around(_ c: Coordinate, size: Int, spacingKm: Double) -> GridSpec {
            let dLat = spacingKm / 111.0
            let dLon = spacingKm / (111.0 * max(cos(c.latitude * .pi / 180), 0.2))
            let half = size / 2
            let lats = (-half...half).map { c.latitude + Double($0) * dLat }
            let lons = (-half...half).map { c.longitude + Double($0) * dLon }
            return GridSpec(lats: lats, lons: lons)
        }

        var points: [Coordinate] {
            lats.flatMap { la in lons.map { Coordinate(latitude: la, longitude: $0) } }
        }
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private static func get(_ base: String, _ items: [URLQueryItem]) async throws -> Data {
        var comps = URLComponents(string: base)!
        comps.queryItems = items
        let (data, resp) = try await session.data(from: comps.url!)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let reason = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.reason
            throw APIError(message: reason ?? "天气服务返回错误 \(http.statusCode)")
        }
        return data
    }

    private static func decode(_ data: Data) throws -> [Response] {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        if let many = try? d.decode([Response].self, from: data) { return many }
        return [try d.decode(Response.self, from: data)]
    }

    private static func rangeItems(_ r: Range) -> [URLQueryItem] {
        switch r {
        case let .relative(p, f):
            return [.init(name: "past_days", value: "\(p)"), .init(name: "forecast_days", value: "\(f)")]
        case let .dates(s, e):
            return [.init(name: "start_date", value: s), .init(name: "end_date", value: e)]
        }
    }

    private static func coordString(_ v: [Double]) -> String {
        v.map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    /// 拉取网格云场
    static func cloudField(_ spec: GridSpec, range: Range) async throws -> CloudField {
        let pts = spec.points
        var items: [URLQueryItem] = [
            .init(name: "latitude", value: coordString(pts.map(\.latitude))),
            .init(name: "longitude", value: coordString(pts.map(\.longitude))),
            .init(name: "hourly", value: cloudVariables.joined(separator: ",")),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        items += rangeItems(range)
        let data = try await get("https://api.open-meteo.com/v1/forecast", items)
        let resps = try decode(data)
        guard resps.count == pts.count else { throw APIError(message: "天气数据不完整") }

        var grid: [[HourlySeries]] = []
        var k = 0
        for _ in spec.lats {
            var row: [HourlySeries] = []
            for _ in spec.lons {
                let h = resps[k].hourly
                var s = HourlySeries()
                s.times = h?.time ?? []
                s.cloudLow = h?.cloudCoverLow ?? []
                s.cloudMid = h?.cloudCoverMid ?? []
                s.cloudHigh = h?.cloudCoverHigh ?? []
                s.humidity = h?.relativeHumidity2m ?? []
                s.visibility = h?.visibility ?? []
                s.precipitation = h?.precipitation ?? []
                row.append(s)
                k += 1
            }
            grid.append(row)
        }
        let first = resps[0]
        let tz = first.timezone.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: first.utcOffsetSeconds ?? 0) ?? .current
        return CloudField(lats: spec.lats, lons: spec.lons, grid: grid, timeZone: tz)
    }

    /// 气溶胶光学厚度（CAMS），失败时返回 nil 不影响主流程
    static func aod(_ c: Coordinate, pastDays: Int, forecastDays: Int) async -> AODSeries? {
        let items: [URLQueryItem] = [
            .init(name: "latitude", value: String(format: "%.4f", c.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", c.longitude)),
            .init(name: "hourly", value: "aerosol_optical_depth"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "past_days", value: "\(pastDays)"),
            .init(name: "forecast_days", value: "\(forecastDays)"),
        ]
        guard let data = try? await get("https://air-quality-api.open-meteo.com/v1/air-quality", items),
              let r = try? decode(data).first, let h = r.hourly,
              let v = h.aerosolOpticalDepth else { return nil }
        return AODSeries(times: h.time, values: v)
    }
}
