import SwiftUI

/// 简单的 RGB 颜色，便于插值
struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

extension Color {
    init(hex: UInt32) { self = RGB(hex).color }
}

/// 霞光等级（摄影圈常用说法：小烧 / 中烧 / 大烧）
enum GlowLevel: Int, CaseIterable {
    case none, faint, small, medium, large

    init(score: Double) {
        switch score {
        case ..<20: self = .none
        case ..<40: self = .faint
        case ..<60: self = .small
        case ..<80: self = .medium
        default: self = .large
        }
    }

    var title: String {
        switch self {
        case .none: return "无霞"
        case .faint: return "微霞"
        case .small: return "小烧"
        case .medium: return "中烧"
        case .large: return "大烧"
        }
    }

    var advice: String {
        switch self {
        case .none: return "大概率是普通日落，不必专程出门"
        case .faint: return "天边可能有淡淡的粉紫色"
        case .small: return "有机会看到局部染色，顺路可以拍"
        case .medium: return "大片云彩有望被点亮，值得出门"
        case .large: return "火烧云预警！提前到机位"
        }
    }
}

enum Theme {
    /// 指数色带：灰蓝 → 薰衣草 → 粉紫 → 橙 → 橙红 → 绯红
    static let stops: [(Double, RGB)] = [
        (0, RGB(0x4A5878)),
        (20, RGB(0x7471B0)),
        (40, RGB(0xC27BB0)),
        (60, RGB(0xF4A261)),
        (80, RGB(0xF2643F)),
        (100, RGB(0xE8205A)),
    ]

    static func rgb(for score: Double) -> RGB {
        let s = min(max(score, 0), 100)
        for i in 0..<(stops.count - 1) {
            let (a, ca) = stops[i]
            let (b, cb) = stops[i + 1]
            if s <= b { return ca.mix(cb, (s - a) / (b - a)) }
        }
        return stops.last!.1
    }

    static func color(for score: Double) -> Color { rgb(for: score).color }

    /// 天空背景渐变，随指数从深蓝暮色渐变到浓烈的火烧云
    static func sky(for score: Double, kind: SkyEventKind) -> [Color] {
        let t = min(max(score / 100, 0), 1)
        let top = RGB(0x070B22).mix(RGB(0x120E35), t)
        let upper = RGB(0x18204A).mix(RGB(0x3B1E5E), t)
        let middle = RGB(0x2C3766).mix(RGB(0x9A2F63), t)
        var horizon = RGB(0x4B5A80).mix(rgb(for: max(score, 35)), t)
        if kind == .sunrise { horizon = horizon.mix(RGB(0xFFC38A), 0.18) }
        return [top.color, upper.color, middle.color, horizon.color]
    }

    static let accent = Color(hex: 0xFF8A4C)
    static let cardStroke = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.65)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
