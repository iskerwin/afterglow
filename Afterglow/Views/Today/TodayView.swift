import SwiftUI
import Charts

struct TodayView: View {
    @Environment(ForecastStore.self) private var store
    @Environment(PlaceSelection.self) private var places
    @Environment(\.modelContext) private var context

    @State private var selectedID: String?
    @State private var showPlaces = false
    @State private var showSettings = false

    private var selected: SkyEvent? {
        store.events.first { $0.id == selectedID } ?? store.nextEvent
    }

    var body: some View {
        ZStack {
            SkyBackground(score: selected?.score ?? 10, kind: selected?.kind ?? .sunset)
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let e = selected {
                        hero(e)
                        timeline(e)
                        reasons(e)
                        metrics(e)
                        cloudChart(e)
                    } else if store.isLoading {
                        ProgressView().tint(.white).padding(.top, 160)
                    } else {
                        emptyState
                    }
                    if !store.upcoming.isEmpty { weekList }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await reload() }
        }
        .sheet(isPresented: $showPlaces) { PlacePickerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { showPlaces = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: places.selected?.isCurrentLocation == true ? "location.fill" : "mappin.and.ellipse")
                    Text(places.selected?.name ?? "选择地点").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.rounded(16, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            if store.isLoading { ProgressView().tint(.white) }
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Hero

    private func hero(_ e: SkyEvent) -> some View {
        let tz = store.timeZone
        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: e.kind.symbol)
                Text("\(relativeDayName(e.dayStart, tz: tz)) · \(e.kind.title)")
            }
            .font(.rounded(17, .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 10)

            ScoreRing(score: e.score)

            Text(e.result.level.title)
                .font(.rounded(34, .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, Theme.color(for: max(e.score, 40))], startPoint: .top, endPoint: .bottom))
            Text(e.result.level.advice)
                .font(.rounded(15, .medium))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 18) {
                Label("\(e.kind.sunTitle) \(e.sunTime.fmt("HH:mm", tz: tz))", systemImage: "clock")
                Label("\(SolarCalculator.directionName(e.result.azimuth)) \(Int(e.result.azimuth))°", systemImage: "location.north.line")
            }
            .font(.rounded(14, .medium))
            .foregroundStyle(Theme.secondaryText)

            if e.isPast {
                Text("已结束 · 实况回算值").font(.rounded(12)).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    // MARK: - Timeline

    private func timeline(_ e: SkyEvent) -> some View {
        let tz = store.timeZone
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "拍摄时间窗", icon: "camera.aperture")
                HStack(spacing: 10) {
                    windowTile("黄金时刻", e.golden, tz: tz, color: Color(hex: 0xF7B267))
                    windowTile("最佳霞光", DateInterval(start: e.peakTime.addingTimeInterval(-600), duration: 1200), tz: tz, color: Theme.color(for: max(e.score, 60)))
                    windowTile("蓝调时刻", e.blue, tz: tz, color: Color(hex: 0x6C8EEF))
                }
            }
        }
    }

    private func windowTile(_ title: String, _ iv: DateInterval?, tz: TimeZone, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 6)
            Text(title).font(.rounded(12, .medium)).foregroundStyle(Theme.secondaryText)
            Text(iv.map { "\($0.start.fmt("HH:mm", tz: tz))" } ?? "–").font(.rounded(19, .bold)).foregroundStyle(.white)
            Text(iv.map { "至 \($0.end.fmt("HH:mm", tz: tz))" } ?? "").font(.rounded(11)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reasons

    private func reasons(_ e: SkyEvent) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "为什么是这个分数", icon: "sparkles")
                Text(e.result.summary)
                    .font(.rounded(16, .semibold))
                    .foregroundStyle(.white)
                ForEach(e.result.factors) { f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: f.impact == .positive ? "plus.circle.fill" : (f.impact == .negative ? "minus.circle.fill" : "circle.fill"))
                            .foregroundStyle(f.impact == .positive ? Color(hex: 0x7DDE92) : (f.impact == .negative ? Color(hex: 0xFF7A7A) : .white.opacity(0.5)))
                            .font(.system(size: 15))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.rounded(14, .semibold)).foregroundStyle(.white)
                            Text(f.detail).font(.rounded(12)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Metrics

    private func metrics(_ e: SkyEvent) -> some View {
        let r = e.result
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "关键指标", icon: "gauge.with.dots.needle.33percent")
                LazyVGrid(columns: cols, spacing: 10) {
                    MetricTile(icon: "cloud.fill", title: "高云 / 中云", value: "\(Int(r.high))% / \(Int(r.mid))%", caption: "画布 \(Int(r.canvas * 100))", tint: Color(hex: 0xC9B6FF))
                    MetricTile(icon: "smoke.fill", title: "本地低云", value: "\(Int(r.low))%", caption: "视线 \(Int(r.localClear * 100))", tint: Color(hex: 0x9FB4D9))
                    MetricTile(icon: "sun.haze.fill", title: "光路通透度", value: "\(Int(r.lightPath * 100))", caption: "太阳方向低云 \(Int(r.upstreamLow))%", tint: Color(hex: 0xFFB36B))
                    MetricTile(icon: "humidity.fill", title: "湿度", value: r.humidity.map { "\(Int($0))%" } ?? "–", caption: "大气 \(Int(r.atmosphere * 100))", tint: Color(hex: 0x7CC6FE))
                    MetricTile(icon: "eye.fill", title: "能见度", value: r.visibilityKm.map { "\(Int($0)) km" } ?? "–", caption: "越高越通透", tint: Color(hex: 0x9EE6C9))
                    MetricTile(icon: "aqi.medium", title: "气溶胶 AOD", value: r.aod.map { String(format: "%.2f", $0) } ?? "–", caption: "0.1–0.35 最出色", tint: Color(hex: 0xF3A6C8))
                }
            }
        }
    }

    // MARK: - Cloud chart

    private struct CloudPoint: Identifiable {
        var id: String { "\(layer)-\(date.timeIntervalSince1970)" }
        var date: Date
        var layer: String
        var value: Double
    }

    private func cloudChart(_ e: SkyEvent) -> some View {
        let series = store.field?.centerSeries
        let start = e.peakTime.addingTimeInterval(-4 * 3600)
        var pts: [CloudPoint] = []
        if let s = series {
            for i in 0...10 {
                let t = start.addingTimeInterval(Double(i) * 1800)
                if let v = s.value(.high, at: t) { pts.append(.init(date: t, layer: "高云", value: v)) }
                if let v = s.value(.mid, at: t) { pts.append(.init(date: t, layer: "中云", value: v)) }
                if let v = s.value(.low, at: t) { pts.append(.init(date: t, layer: "低云", value: v)) }
            }
        }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "本地云层变化", icon: "chart.xyaxis.line")
                Chart {
                    ForEach(pts) { p in
                        AreaMark(x: .value("时间", p.date), y: .value("云量", p.value), stacking: .unstacked)
                            .foregroundStyle(by: .value("层", p.layer))
                            .opacity(0.35)
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("时间", p.date), y: .value("云量", p.value))
                            .foregroundStyle(by: .value("层", p.layer))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    RuleMark(x: .value(e.kind.sunTitle, e.sunTime))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .center) {
                            Text(e.kind.sunTitle).font(.rounded(10, .semibold)).foregroundStyle(.white.opacity(0.8))
                        }
                }
                .chartForegroundStyleScale(["高云": Color(hex: 0xC9B6FF), "中云": Color(hex: 0xFF9F80), "低云": Color(hex: 0x8FA3BF)])
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { v in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").foregroundStyle(Theme.secondaryText) }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 1)) { v in
                        AxisValueLabel {
                            if let d = v.as(Date.self) { Text(d.fmt("HH", tz: store.timeZone)).foregroundStyle(Theme.secondaryText) }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 170)
            }
        }
    }

    // MARK: - Week list

    private var weekList: some View {
        let tz = store.timeZone
        let days = Dictionary(grouping: store.upcoming, by: \.dayStart).sorted { $0.key < $1.key }
        return GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(title: "未来几天", icon: "calendar.day.timeline.left")
                    .padding(.bottom, 6)
                ForEach(days, id: \.key) { entry in
                    let day = entry.key
                    let evs = entry.value
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(relativeDayName(day, tz: tz)).font(.rounded(15, .semibold)).foregroundStyle(.white)
                            Text(day.fmt("M月d日", tz: tz)).font(.rounded(11)).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(width: 64, alignment: .leading)
                        ForEach(SkyEventKind.allCases) { k in
                            if let ev = evs.first(where: { $0.kind == k }) {
                                eventButton(ev)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    if day != days.last?.key { Divider().overlay(.white.opacity(0.08)) }
                }
            }
        }
    }

    private func eventButton(_ ev: SkyEvent) -> some View {
        let isSel = ev.id == selected?.id
        return Button {
            withAnimation(.spring) { selectedID = ev.id }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: ev.kind.symbol).font(.system(size: 11))
                    Text(ev.kind.title).font(.rounded(11, .medium))
                    Spacer(minLength: 2)
                    Text("\(Int(ev.score.rounded()))").font(.rounded(15, .bold)).monospacedDigit()
                }
                .foregroundStyle(.white)
                ScoreBar(score: ev.score)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSel ? Theme.color(for: ev.score).opacity(0.35) : .white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSel ? Theme.color(for: ev.score) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Misc

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "cloud.sun").font(.system(size: 36)).foregroundStyle(.white)
                Text(store.errorMessage ?? "选择一个地点开始预测").font(.rounded(15, .medium)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("重试") { Task { await reload() } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 120)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let err = store.errorMessage, selected != nil {
                Text(err).foregroundStyle(Color(hex: 0xFF9A9A))
            }
            if let t = store.lastUpdated {
                Text("更新于 \(t.fmt("HH:mm", tz: .current)) · 天气数据 Open-Meteo")
            }
        }
        .font(.rounded(11))
        .foregroundStyle(Theme.secondaryText)
        .padding(.top, 4)
    }

    private func reload() async {
        guard let p = places.selected else { return }
        await store.refresh(place: p, context: context)
    }
}
