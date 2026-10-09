import Foundation

struct GlowFactor: Identifiable, Hashable {
    enum Impact { case positive, neutral, negative }
    var id: String { title }
    var title: String
    var detail: String
    var impact: Impact
}

struct GlowResult: Hashable {
    var score: Double
    var azimuth: Double
    // 0~1 的分项
    var canvas: Double
    var lightPath: Double
    var localClear: Double
    var atmosphere: Double
    var rain: Double
    // 原始指标
    var high: Double
    var mid: Double
    var low: Double
    var upstreamLow: Double
    var upstreamMid: Double
    var humidity: Double?
    var visibilityKm: Double?
    var aod: Double?
    var precipitation: Double

    var level: GlowLevel { GlowLevel(score: score) }

    var factors: [GlowFactor] {
        var f: [GlowFactor] = []
        let canvasPct = Int(min(100, high + mid * (1 - high / 100)))
        if canvasPct < 15 {
            f.append(.init(title: "高中云 \(canvasPct)%", detail: "天空太干净，缺少可被染色的「画布」", impact: .negative))
        } else if canvasPct > 88 {
            f.append(.init(title: "高中云 \(canvasPct)%", detail: "云层过厚，光线难以穿透", impact: .negative))
        } else {
            f.append(.init(title: "高中云 \(canvasPct)%", detail: canvasPct >= 35 ? "理想的画布，云底会被夕阳染红" : "画布偏少，染色范围有限", impact: canvasPct >= 35 ? .positive : .neutral))
        }
        let dir = SolarCalculator.directionName(azimuth)
        if upstreamLow < 25 {
            f.append(.init(title: "\(dir)方光路通透", detail: "太阳方向 30–120 km 内低云仅 \(Int(upstreamLow))%", impact: .positive))
        } else if upstreamLow < 55 {
            f.append(.init(title: "\(dir)方低云 \(Int(upstreamLow))%", detail: "光路被部分遮挡，色彩可能断续", impact: .neutral))
        } else {
            f.append(.init(title: "\(dir)方低云 \(Int(upstreamLow))%", detail: "阳光在途中被挡住，云彩难以点亮", impact: .negative))
        }
        if low > 60 {
            f.append(.init(title: "本地低云 \(Int(low))%", detail: "头顶低云密布，视线受阻", impact: .negative))
        }
        if let v = visibilityKm {
            f.append(.init(title: "能见度 \(Int(v)) km", detail: v >= 15 ? "空气通透" : "偏朦胧，色彩会发灰", impact: v >= 15 ? .positive : .negative))
        }
        if let a = aod {
            let good = a >= 0.08 && a <= 0.4
            f.append(.init(title: String(format: "气溶胶 %.2f", a), detail: good ? "适量颗粒散射出更浓的橙红" : (a < 0.08 ? "空气极干净，色彩偏淡" : "霾较重，颜色偏暗"), impact: good ? .positive : .neutral))
        }
        if precipitation >= 0.2 {
            f.append(.init(title: "降水 \(String(format: "%.1f", precipitation)) mm", detail: "降雨时段，难有霞光", impact: .negative))
        } else if rain > 1 {
            f.append(.init(title: "雨后放晴", detail: "空气被洗净，常出现惊艳霞光", impact: .positive))
        }
        return f
    }

    var summary: String {
        if precipitation >= 0.5 { return "下雨时段，霞光机会很小。" }
        let limits: [(Double, String)] = [
            (canvas, high + mid < 20 ? "天空太晴朗，缺少高中云作画布，多半是干净的日落。" : "云层太厚，阳光难以透出。"),
            (lightPath, "太阳方向低云较多，阳光可能被挡在半路。"),
            (localClear, "本地低云密布，可能什么也看不到。"),
        ]
        if score >= 60 { return "画布充足、光路通透，值得提前到机位等待。" }
        let worst = limits.min { $0.0 < $1.0 }!
        return worst.1
    }
}

/// 霞光指数模型
///
/// 思路：火烧云 = 有「画布」(高/中云) + 有「光路」(太阳方向地平线附近无低云遮挡) + 有「视线」(本地低云少) + 大气通透。
/// 日落后太阳光贴着地平线，从太阳方向几十到上百公里外照射过来，所以要沿太阳方位角采样远处的低云。
enum GlowScorer {
    static let upstreamDistances: [Double] = [30, 70, 115]
    static let upstreamWeights: [Double] = [0.25, 0.35, 0.40]

    static func score(field: CloudField, at c: Coordinate, time: Date, aod: Double?) -> GlowResult? {
        guard let high = field.sample(.high, at: c, date: time),
              let mid = field.sample(.mid, at: c, date: time),
              let low = field.sample(.low, at: c, date: time) else { return nil }

        let azimuth = SolarCalculator.position(at: time, c).azimuth

        var upLow = 0.0, upMid = 0.0, wsum = 0.0
        for (d, w) in zip(upstreamDistances, upstreamWeights) {
            let p = c.moved(bearing: azimuth, distanceKm: d)
            if let l = field.sample(.low, at: p, date: time) {
                upLow += l * w
                upMid += (field.sample(.mid, at: p, date: time) ?? mid) * w
                wsum += w
            }
        }
        if wsum > 0 { upLow /= wsum; upMid /= wsum } else { upLow = low; upMid = mid }

        // 1. 画布：高云 + 中云的合成覆盖率，40%–80% 最佳
        let cover = min(100, high + mid * (1 - high / 100))
        let canvas: Double
        switch cover {
        case ..<10: canvas = cover / 10 * 0.2
        case ..<40: canvas = 0.2 + 0.8 * (cover - 10) / 30
        case ...80: canvas = 1
        default: canvas = 1 - (cover - 80) / 20 * 0.6
        }

        // 2. 光路：太阳方向远处的低云（以及厚中云）会挡住贴地的阳光
        let block = 1 - (1 - upLow / 100) * (1 - 0.45 * upMid / 100)
        let lightPath = pow(max(0, 1 - block), 1.3)

        // 3. 视线：本地低云
        let localClear = low <= 30 ? 1 : 1 - 0.85 * pow((low - 30) / 70, 1.2)

        // 4. 大气：能见度、湿度、气溶胶
        let rh = field.sample(.humidity, at: c, date: time)
        let visM = field.sample(.visibility, at: c, date: time)
        let visKm = visM.map { $0 / 1000 }
        let visF: Double = visKm.map { v in v >= 30 ? 1 : (v >= 10 ? 0.75 + 0.25 * (v - 10) / 20 : max(0.35, 0.35 + 0.4 * (v - 3) / 7)) } ?? 0.85
        let humF: Double = rh.map { h in h <= 60 ? 1 : (h <= 90 ? 1 - (h - 60) / 30 * 0.35 : 0.6) } ?? 0.85
        let aodF: Double = aod.map { a in
            if a < 0.08 { return 0.85 }
            if a <= 0.35 { return 1 }
            if a <= 0.8 { return 1 - (a - 0.35) / 0.45 * 0.4 }
            return 0.5
        } ?? 0.85
        let atmosphere = visF * 0.45 + humF * 0.3 + aodF * 0.25

        // 5. 降水
        let p = field.sample(.precipitation, at: c, date: time) ?? 0
        var rain = 1.0
        if p >= 1 { rain = 0.35 }
        else if p >= 0.2 { rain = 0.7 }
        else {
            let recent = [1.0, 2, 3].reduce(0.0) {
                $0 + (field.sample(.precipitation, at: c, date: time.addingTimeInterval(-$1 * 3600)) ?? 0)
            }
            if recent >= 0.5 { rain = 1.08 }
        }

        let raw = 100 * canvas * lightPath * localClear * (0.55 + 0.45 * atmosphere) * rain
        return GlowResult(
            score: min(max(raw, 0), 100), azimuth: azimuth,
            canvas: canvas, lightPath: lightPath, localClear: localClear, atmosphere: atmosphere, rain: rain,
            high: high, mid: mid, low: low, upstreamLow: upLow, upstreamMid: upMid,
            humidity: rh, visibilityKm: visKm, aod: aod, precipitation: p
        )
    }
}
