import SwiftUI

/// 动态天空背景：渐变 + 缓慢漂移的光晕
struct SkyBackground: View {
    var score: Double
    var kind: SkyEventKind = .sunset

    var body: some View {
        let colors = Theme.sky(for: score, kind: kind)
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(Theme.color(for: max(score, 30)).opacity(0.55))
                        .frame(width: geo.size.width * 1.1)
                        .blur(radius: 90)
                        .offset(x: CGFloat(sin(t / 9)) * 60, y: geo.size.height * 0.42 + CGFloat(cos(t / 11)) * 30)
                    Circle()
                        .fill(Color(hex: 0x6B4BC2).opacity(0.35))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 100)
                        .offset(x: -geo.size.width * 0.3 + CGFloat(cos(t / 13)) * 50, y: -geo.size.height * 0.05)
                    StarField(opacity: max(0, 0.6 - score / 120))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: score)
    }
}

struct StarField: View {
    var opacity: Double
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 7)
            for _ in 0..<70 {
                let x = rng.next() * size.width
                let y = rng.next() * size.height * 0.45
                let r = 0.5 + rng.next() * 1.3
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.white.opacity(opacity * (0.4 + rng.next() * 0.6))))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
    }
}

/// 玻璃质感卡片
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}

struct SectionTitle: View {
    var title: String
    var icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.rounded(13, .semibold))
            .foregroundStyle(Theme.secondaryText)
            .textCase(nil)
    }
}

/// 环形霞光指数表盘
struct ScoreRing: View {
    var score: Double
    var size: CGFloat = 220
    var lineWidth: CGFloat = 18

    var body: some View {
        let frac = min(max(score / 100, 0), 1)
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(frac, 0.005))
                .stroke(
                    AngularGradient(colors: (0...10).map { Theme.color(for: Double($0) * 10 * max(frac, 0.1)) },
                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(frac, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.color(for: score).opacity(0.8), radius: 14)
            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: score))
                    .foregroundStyle(.white)
                Text("霞光指数")
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: score)
    }
}

/// 小号指数胶囊
struct ScoreChip: View {
    var score: Double?
    var compact = false

    var body: some View {
        let s = score ?? 0
        HStack(spacing: 4) {
            if !compact, score != nil {
                Text(GlowLevel(score: s).title).font(.rounded(11, .semibold))
            }
            Text(score.map { "\(Int($0.rounded()))" } ?? "–").font(.rounded(13, .bold)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
            Capsule().fill(score == nil ? AnyShapeStyle(Color.white.opacity(0.12)) :
                AnyShapeStyle(LinearGradient(colors: [Theme.color(for: s * 0.7), Theme.color(for: s)], startPoint: .leading, endPoint: .trailing)))
        )
    }
}

/// 指数色带条
struct ScoreBar: View {
    var score: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.color(for: 0), Theme.color(for: max(score, 1))], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * score / 100))
            }
        }
        .frame(height: 6)
    }
}

struct MetricTile: View {
    var icon: String
    var title: String
    var value: String
    var caption: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).foregroundStyle(Theme.secondaryText)
            }
            .font(.rounded(12, .medium))
            Text(value).font(.rounded(22, .bold)).foregroundStyle(.white).monospacedDigit()
            Text(caption).font(.rounded(11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 0–100 图例
struct ScoreLegend: View {
    var body: some View {
        VStack(spacing: 4) {
            LinearGradient(colors: stride(from: 0.0, through: 100, by: 10).map { Theme.color(for: $0) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Capsule())
            HStack {
                ForEach(GlowLevel.allCases, id: \.self) { l in
                    Text(l.title).frame(maxWidth: .infinity)
                }
            }
            .font(.rounded(10, .medium))
            .foregroundStyle(Theme.secondaryText)
        }
    }
}

extension Date {
    func fmt(_ pattern: String, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: self)
    }
}

func relativeDayName(_ day: Date, tz: TimeZone) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let today = cal.startOfDay(for: .now)
    let diff = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: day)).day ?? 0
    switch diff {
    case 0: return "今天"
    case 1: return "明天"
    case 2: return "后天"
    case -1: return "昨天"
    default: return day.fmt("EEE", tz: tz)
    }
}
