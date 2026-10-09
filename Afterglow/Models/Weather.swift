import Foundation
import CoreLocation

enum SkyEventKind: String, Codable, CaseIterable, Identifiable {
    case sunrise, sunset
    var id: String { rawValue }
    var title: String { self == .sunrise ? "朝霞" : "晚霞" }
    var sunTitle: String { self == .sunrise ? "日出" : "日落" }
    var symbol: String { self == .sunrise ? "sunrise.fill" : "sunset.fill" }
}

struct Coordinate: Hashable, Codable {
    var latitude: Double
    var longitude: Double

    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// 沿方位角（正北顺时针，度）前进 distanceKm 后的坐标（大圆航线）
    func moved(bearing: Double, distanceKm: Double) -> Coordinate {
        let R = 6371.0
        let δ = distanceKm / R
        let θ = bearing * .pi / 180
        let φ1 = latitude * .pi / 180
        let λ1 = longitude * .pi / 180
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        return Coordinate(latitude: φ2 * 180 / .pi, longitude: λ2 * 180 / .pi)
    }

    func distanceKm(to o: Coordinate) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: o.latitude, longitude: o.longitude)) / 1000
    }

    func bearing(to o: Coordinate) -> Double {
        let φ1 = latitude * .pi / 180, φ2 = o.latitude * .pi / 180
        let Δλ = (o.longitude - longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 用于持久化的地点键（约 1 km 精度）
    var key: String { String(format: "%.2f,%.2f", latitude, longitude) }
}

/// 当前选择的地点
struct PlaceRef: Hashable, Codable {
    var name: String
    var coordinate: Coordinate
    var isCurrentLocation: Bool
}

/// 单个格点的逐小时序列
struct HourlySeries {
    var times: [TimeInterval] = []          // unix 秒，逐小时
    var cloudLow: [Double?] = []
    var cloudMid: [Double?] = []
    var cloudHigh: [Double?] = []
    var humidity: [Double?] = []
    var visibility: [Double?] = []          // 米
    var precipitation: [Double?] = []       // mm

    enum Variable { case low, mid, high, humidity, visibility, precipitation }

    func array(_ v: Variable) -> [Double?] {
        switch v {
        case .low: return cloudLow
        case .mid: return cloudMid
        case .high: return cloudHigh
        case .humidity: return humidity
        case .visibility: return visibility
        case .precipitation: return precipitation
        }
    }

    var range: ClosedRange<TimeInterval>? {
        guard let f = times.first, let l = times.last else { return nil }
        return f...l
    }

    /// 线性插值取值
    func value(_ v: Variable, at date: Date) -> Double? {
        let arr = array(v)
        guard let t0 = times.first, times.count > 1, arr.count == times.count else { return nil }
        let x = (date.timeIntervalSince1970 - t0) / 3600
        guard x >= 0, x <= Double(times.count - 1) else { return nil }
        let i = Int(floor(x)), j = min(i + 1, times.count - 1)
        let f = x - Double(i)
        switch (arr[i], arr[j]) {
        case let (a?, b?): return a + (b - a) * f
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    /// 时间窗内求和（如累计降水）
    func sum(_ v: Variable, from: Date, to: Date) -> Double {
        let arr = array(v)
        var s = 0.0
        for (i, t) in times.enumerated() where t >= from.timeIntervalSince1970 && t <= to.timeIntervalSince1970 {
            if i < arr.count, let x = arr[i] { s += x }
        }
        return s
    }
}

/// 规则网格上的云场，支持双线性采样
struct CloudField {
    var lats: [Double]                 // 升序
    var lons: [Double]                 // 升序
    var grid: [[HourlySeries]]         // [latIndex][lonIndex]
    var timeZone: TimeZone

    var center: Coordinate {
        Coordinate(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
    }

    var centerSeries: HourlySeries { grid[lats.count / 2][lons.count / 2] }

    func contains(_ c: Coordinate) -> Bool {
        guard let a = lats.first, let b = lats.last, let x = lons.first, let y = lons.last else { return false }
        return c.latitude >= a && c.latitude <= b && c.longitude >= x && c.longitude <= y
    }

    func sample(_ v: HourlySeries.Variable, at c: Coordinate, date: Date) -> Double? {
        guard lats.count > 1, lons.count > 1 else { return grid.first?.first?.value(v, at: date) }
        func locate(_ arr: [Double], _ x: Double) -> (Int, Double) {
            let x = min(max(x, arr.first!), arr.last!)
            var i = 0
            while i < arr.count - 2 && x > arr[i + 1] { i += 1 }
            let f = (x - arr[i]) / (arr[i + 1] - arr[i])
            return (i, f)
        }
        let (i, fy) = locate(lats, c.latitude)
        let (j, fx) = locate(lons, c.longitude)
        let corners: [(Int, Int, Double)] = [
            (i, j, (1 - fy) * (1 - fx)), (i, j + 1, (1 - fy) * fx),
            (i + 1, j, fy * (1 - fx)), (i + 1, j + 1, fy * fx),
        ]
        var sum = 0.0, wsum = 0.0
        for (a, b, w) in corners where w > 0 {
            if let val = grid[a][b].value(v, at: date) { sum += val * w; wsum += w }
        }
        return wsum > 0 ? sum / wsum : nil
    }
}

/// 气溶胶光学厚度（AOD）序列
struct AODSeries {
    var times: [TimeInterval]
    var values: [Double?]

    func value(at date: Date) -> Double? {
        var s = HourlySeries()
        s.times = times
        s.cloudLow = values
        return s.value(.low, at: date)
    }
}
