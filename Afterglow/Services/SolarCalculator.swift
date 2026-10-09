import Foundation

/// 太阳位置计算（低精度天文算法，误差约 1 分钟 / 0.1°，对摄影足够）
enum SolarCalculator {
    struct Position { var elevation: Double; var azimuth: Double }

    static func position(at date: Date, _ c: Coordinate) -> Position {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.0000004 * n) * rad
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda))
        let dec = asin(sin(eps) * sin(lambda))
        let gmstHours = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let lst = (gmstHours * 15 + c.longitude) * rad
        let h = lst - ra
        let lat = c.latitude * rad
        let el = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h))
        var az = atan2(-sin(h) * cos(dec), sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(h)) / rad
        az = (az + 360).truncatingRemainder(dividingBy: 360)
        return Position(elevation: el / rad, azimuth: az)
    }

    /// 在 [start, end] 内寻找太阳高度角穿越 target 的时刻
    static func crossing(_ c: Coordinate, target: Double, from start: Date, to end: Date, rising: Bool) -> Date? {
        let step: TimeInterval = 600
        var t = start
        var prev = position(at: t, c).elevation - target
        while t < end {
            let next = t.addingTimeInterval(step)
            let cur = position(at: next, c).elevation - target
            let crossed = rising ? (prev < 0 && cur >= 0) : (prev > 0 && cur <= 0)
            if crossed {
                var a = t, b = next
                for _ in 0..<20 {
                    let m = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
                    let v = position(at: m, c).elevation - target
                    if (v >= 0) == rising { b = m } else { a = m }
                }
                return a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            }
            prev = cur
            t = next
        }
        return nil
    }

    struct Day {
        var sunrise: Date?
        var sunset: Date?
        /// 晨间：蓝调时刻 (-6°→-4°) 与黄金时刻 (-4°→6°)
        var morningBlue: DateInterval?
        var morningGolden: DateInterval?
        var eveningGolden: DateInterval?
        var eveningBlue: DateInterval?
    }

    /// 计算某个本地日的太阳事件
    static func day(_ c: Coordinate, dayStart: Date) -> Day {
        let noon = dayStart.addingTimeInterval(12 * 3600)
        let end = dayStart.addingTimeInterval(24 * 3600)
        let h0 = -0.833
        var d = Day()
        d.sunrise = crossing(c, target: h0, from: dayStart, to: noon, rising: true)
        d.sunset = crossing(c, target: h0, from: noon, to: end, rising: false)
        if let a = crossing(c, target: -6, from: dayStart, to: noon, rising: true),
           let b = crossing(c, target: -4, from: dayStart, to: noon, rising: true), b > a {
            d.morningBlue = DateInterval(start: a, end: b)
            if let g = crossing(c, target: 6, from: dayStart, to: noon, rising: true), g > b {
                d.morningGolden = DateInterval(start: b, end: g)
            }
        }
        if let g = crossing(c, target: 6, from: noon, to: end, rising: false),
           let b = crossing(c, target: -4, from: noon, to: end, rising: false), b > g {
            d.eveningGolden = DateInterval(start: g, end: b)
            if let e = crossing(c, target: -6, from: noon, to: end, rising: false), e > b {
                d.eveningBlue = DateInterval(start: b, end: e)
            }
        }
        return d
    }

    static func directionName(_ azimuth: Double) -> String {
        let names = ["北", "北偏东", "东北", "东偏北", "东", "东偏南", "东南", "南偏东",
                     "南", "南偏西", "西南", "西偏南", "西", "西偏北", "西北", "北偏西"]
        let idx = Int(((azimuth + 11.25).truncatingRemainder(dividingBy: 360)) / 22.5)
        return names[min(max(idx, 0), names.count - 1)]
    }
}
