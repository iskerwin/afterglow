import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(ForecastStore.self) private var store
    @Environment(PlaceSelection.self) private var places
    @Environment(\.modelContext) private var context
    @Query(sort: \PredictionRecord.eventDate, order: .reverse) private var records: [PredictionRecord]
    @Query(sort: \Observation.date, order: .reverse) private var observations: [Observation]

    @State private var kind: SkyEventKind = .sunset
    @State private var showEditor = false
    @State private var editing: Observation?

    private var placeKey: String? { places.selected?.coordinate.key }

    private var placeRecords: [PredictionRecord] {
        records.filter { $0.placeKey == placeKey && $0.kind == kind && $0.bestScore != nil }
    }

    private var last30: [PredictionRecord] {
        let from = Date.now.addingTimeInterval(-30 * 86400)
        let to = Date.now.addingTimeInterval(7 * 86400)
        return Array(placeRecords.filter { $0.eventDate >= from && $0.eventDate <= to }.reversed())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(score: 25, kind: kind)
                ScrollView {
                    VStack(spacing: 16) {
                        Picker("", selection: $kind) {
                            ForEach(SkyEventKind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        stats
                        chart
                        observationList
                        recordList
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("霞光档案")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = nil; showEditor = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20))
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                ObservationEditor(observation: editing, defaultKind: kind)
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        let past = last30.filter { $0.eventDate < .now }
        let scores = past.compactMap(\.bestScore)
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        let fires = scores.filter { $0 >= 60 }.count
        let rated = observations.filter { $0.kind == kind && $0.predictedScore != nil }
        let accuracy: String = {
            guard rated.count >= 3 else { return "–" }
            let err = rated.map { abs(Double($0.rating) * 20 - ($0.predictedScore ?? 0)) }.reduce(0, +) / Double(rated.count)
            return "\(max(0, 100 - Int(err)))%"
        }()
        return HStack(spacing: 10) {
            statTile("\(fires)", "近 30 天\n中烧以上", Theme.color(for: 75))
            statTile("\(Int(avg))", "平均\n霞光指数", Theme.color(for: avg))
            statTile(accuracy, "预测吻合度\n(≥3 次打卡)", Color(hex: 0x7DDE92))
        }
    }

    private func statTile(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.rounded(26, .bold)).foregroundStyle(color).monospacedDigit()
            Text(title).font(.rounded(11, .medium)).foregroundStyle(Theme.secondaryText).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Chart

    private var chart: some View {
        let obs = observations.filter { $0.kind == kind && $0.date >= Date.now.addingTimeInterval(-30 * 86400) }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "\(places.selected?.name ?? "") · 近 30 天 + 未来 7 天", icon: "chart.bar.fill")
                    Spacer()
                }
                if last30.isEmpty {
                    Text("刷新预报后，这里会自动记录每天的霞光指数").font(.rounded(13)).foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart {
                        ForEach(last30) { r in
                            BarMark(x: .value("日期", r.eventDate, unit: .day), y: .value("指数", r.bestScore ?? 0))
                                .foregroundStyle(Theme.color(for: r.bestScore ?? 0).opacity(r.eventDate > .now ? 0.5 : 1))
                                .cornerRadius(3)
                        }
                        ForEach(obs) { o in
                            PointMark(x: .value("日期", o.date, unit: .day), y: .value("实拍", Double(o.rating) * 20))
                                .symbol(.diamond)
                                .symbolSize(70)
                                .foregroundStyle(.white)
                        }
                        RuleMark(x: .value("今天", Date.now, unit: .day))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 40, 60, 80, 100]) { v in
                            AxisGridLine().foregroundStyle(.white.opacity(0.08))
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").foregroundStyle(Theme.secondaryText) }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { v in
                            AxisValueLabel { if let d = v.as(Date.self) { Text(d.fmt("M/d", tz: store.timeZone)).foregroundStyle(Theme.secondaryText) } }
                        }
                    }
                    .frame(height: 190)
                    HStack(spacing: 14) {
                        Label("预测 / 回算", systemImage: "square.fill").foregroundStyle(Theme.color(for: 65))
                        Label("实拍评分", systemImage: "diamond.fill").foregroundStyle(.white)
                    }
                    .font(.rounded(11, .medium))
                }
            }
        }
    }

    // MARK: - Observations

    private var observationList: some View {
        let obs = observations.filter { $0.kind == kind }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "我的实拍打卡", icon: "camera.fill")
                if obs.isEmpty {
                    Button { editing = nil; showEditor = true } label: {
                        Label("记录今天看到的天空", systemImage: "plus")
                            .font(.rounded(14, .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .foregroundStyle(.white)
                }
                ForEach(obs.prefix(20)) { o in
                    Button { editing = o; showEditor = true } label: { ObservationRow(o: o, tz: store.timeZone) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { context.delete(o); try? context.save() } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
        }
    }

    // MARK: - Records

    private var recordList: some View {
        let tz = store.timeZone
        let list = placeRecords.filter { $0.eventDate < .now }.prefix(60)
        return GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(title: "历史指数", icon: "clock.arrow.circlepath").padding(.bottom, 6)
                if list.isEmpty {
                    Text("暂无历史").font(.rounded(13)).foregroundStyle(Theme.secondaryText)
                }
                ForEach(Array(list)) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.eventDate.fmt("M月d日 EEE", tz: tz)).font(.rounded(14, .semibold)).foregroundStyle(.white)
                            Text(r.forecastScore.map { "当时预测 \(Int($0))" } ?? "实况回算")
                                .font(.rounded(11)).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        ScoreBar(score: r.bestScore ?? 0).frame(width: 90)
                        ScoreChip(score: r.bestScore)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}

struct ObservationRow: View {
    var o: Observation
    var tz: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let d = o.photo, let ui = UIImage(data: d) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: Theme.sky(for: Double(o.rating) * 20, kind: o.kind), startPoint: .top, endPoint: .bottom)
                        .overlay(Image(systemName: o.kind.symbol).foregroundStyle(.white.opacity(0.8)))
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        Image(systemName: i < o.rating ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(i < o.rating ? Theme.color(for: 70) : .white.opacity(0.3))
                    }
                }
                Text("\(o.date.fmt("M月d日 HH:mm", tz: tz)) · \(o.placeName)").font(.rounded(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                if !o.note.isEmpty {
                    Text(o.note).font(.rounded(12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer()
            if let p = o.predictedScore {
                VStack(spacing: 2) {
                    Text("预测").font(.rounded(10)).foregroundStyle(Theme.secondaryText)
                    ScoreChip(score: p, compact: true)
                }
            }
        }
    }
}
