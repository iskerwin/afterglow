import SwiftUI
import MapKit

struct MapCell: Identifiable, Hashable {
    var id: Int
    var center: Coordinate
    var corners: [CLLocationCoordinate2D]
    var result: GlowResult
    var score: Double { result.score }

    static func == (a: MapCell, b: MapCell) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
@Observable
final class MapStore {
    var cells: [MapCell] = []
    var isLoading = false
    var errorMessage: String?
    private var loadedKey: String?

    var best: MapCell? { cells.max { $0.score < $1.score } }

    func load(event: SkyEvent, center: Coordinate, tz: TimeZone, aod: Double?) async {
        let key = "\(center.key)|\(event.id)"
        guard key != loadedKey else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let spacing = 22.0
        let spec = OpenMeteoClient.GridSpec.around(center, size: 9, spacingKm: spacing)
        let day = event.dayStart.fmt("yyyy-MM-dd", tz: tz)
        do {
            let field = try await OpenMeteoClient.cloudField(spec, range: .dates(start: day, end: day))
            let dLat = (spec.lats[1] - spec.lats[0]) / 2
            let dLon = (spec.lons[1] - spec.lons[0]) / 2
            var out: [MapCell] = []
            var id = 0
            for la in spec.lats {
                for lo in spec.lons {
                    let c = Coordinate(latitude: la, longitude: lo)
                    if let r = GlowScorer.score(field: field, at: c, time: event.peakTime, aod: aod) {
                        out.append(MapCell(id: id, center: c, corners: [
                            .init(latitude: la - dLat, longitude: lo - dLon),
                            .init(latitude: la - dLat, longitude: lo + dLon),
                            .init(latitude: la + dLat, longitude: lo + dLon),
                            .init(latitude: la + dLat, longitude: lo - dLon),
                        ], result: r))
                    }
                    id += 1
                }
            }
            cells = out
            loadedKey = key
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct GlowMapView: View {
    @Environment(ForecastStore.self) private var store
    @Environment(PlaceSelection.self) private var places
    @State private var mapStore = MapStore()
    @State private var selectedEventID: String?
    @State private var selectedCell: MapCell?
    @State private var position: MapCameraPosition = .automatic

    private var event: SkyEvent? {
        store.upcoming.first { $0.id == selectedEventID } ?? store.nextEvent
    }

    private var center: Coordinate? { places.selected?.coordinate }

    var body: some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $position) {
                    ForEach(mapStore.cells) { cell in
                        MapPolygon(coordinates: cell.corners)
                            .foregroundStyle(Theme.color(for: cell.score).opacity(0.18 + cell.score / 100 * 0.42))
                            .stroke(selectedCell == cell ? Color.white : Color.clear, lineWidth: 2)
                    }
                    if let c = center, let e = event {
                        MapPolyline(coordinates: [c.cl, c.moved(bearing: e.result.azimuth, distanceKm: 110).cl])
                            .stroke(Color(hex: 0xFFD27A), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                        Annotation(e.kind.sunTitle, coordinate: c.moved(bearing: e.result.azimuth, distanceKm: 115).cl) {
                            Image(systemName: e.kind.symbol)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color(hex: 0xFFD27A))
                                .padding(7)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                    }
                    if let c = center {
                        Annotation(places.selected?.name ?? "", coordinate: c.cl) {
                            ZStack {
                                Circle().fill(.white).frame(width: 18, height: 18)
                                Circle().fill(Theme.accent).frame(width: 12, height: 12)
                            }
                            .shadow(radius: 4)
                        }
                    }
                    if let b = mapStore.best, b.score >= 20 {
                        Annotation("最佳", coordinate: b.center.cl) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Theme.color(for: b.score), in: Circle())
                                .shadow(color: Theme.color(for: b.score), radius: 8)
                        }
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControls { MapCompass(); MapScaleView() }
                .onTapGesture { pt in
                    guard let coord = proxy.convert(pt, from: .local) else { return }
                    let c = Coordinate(latitude: coord.latitude, longitude: coord.longitude)
                    withAnimation(.spring) {
                        selectedCell = mapStore.cells.min { $0.center.distanceKm(to: c) < $1.center.distanceKm(to: c) }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                eventPicker
                if mapStore.isLoading {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("计算周边霞光…") }
                        .font(.rounded(13, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                if let err = mapStore.errorMessage {
                    Text(err).font(.rounded(12)).foregroundStyle(.white)
                        .padding(8).background(.red.opacity(0.5), in: Capsule())
                }
                Spacer()
                bottomCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .task(id: "\(center?.key ?? "")|\(event?.id ?? "")") { await reload() }
    }

    private var eventPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.upcoming.prefix(8)) { e in
                    let sel = e.id == event?.id
                    Button {
                        withAnimation { selectedEventID = e.id; selectedCell = nil }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: e.kind.symbol)
                            Text("\(relativeDayName(e.dayStart, tz: store.timeZone))\(e.kind.title)")
                            Text("\(Int(e.score))").monospacedDigit().fontWeight(.bold)
                        }
                        .font(.rounded(13, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(sel ? AnyShapeStyle(Theme.color(for: e.score).opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let cell = selectedCell ?? mapStore.best, let c = center {
                let isBest = selectedCell == nil || selectedCell == mapStore.best
                let dist = c.distanceKm(to: cell.center)
                HStack(alignment: .center, spacing: 14) {
                    ScoreRing(score: cell.score, size: 64, lineWidth: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isBest ? "周边最佳 · \(cell.result.level.title)" : "此处 · \(cell.result.level.title)")
                            .font(.rounded(17, .bold)).foregroundStyle(.white)
                        Text(dist < 8 ? "就在你附近" : "\(SolarCalculator.directionName(c.bearing(to: cell.center)))方向约 \(Int(dist)) km")
                            .font(.rounded(13, .medium)).foregroundStyle(Theme.secondaryText)
                        Text(cell.result.summary).font(.rounded(12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: cell.center.cl))
                        item.name = "霞光机位 \(Int(cell.score))"
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 20)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                }
            } else {
                Text("点击地图任意位置查看该处霞光指数").font(.rounded(14, .medium)).foregroundStyle(.white)
            }
            ScoreLegend()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private func reload() async {
        guard let c = center, let e = event else { return }
        position = .region(MKCoordinateRegion(center: c.cl, latitudinalMeters: 260_000, longitudinalMeters: 260_000))
        selectedCell = nil
        await mapStore.load(event: e, center: c, tz: store.timeZone, aod: e.result.aod)
    }
}
