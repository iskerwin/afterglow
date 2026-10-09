import SwiftUI
import SwiftData

@main
struct AfterglowApp: App {
    @State private var store = ForecastStore()
    @State private var location = LocationManager()
    @State private var places = PlaceSelection()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(places)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [SavedPlace.self, PredictionRecord.self, SkyObservation.self])
    }
}

/// 当前选中的地点（持久化到 UserDefaults）
@MainActor
@Observable
final class PlaceSelection {
    private static let key = "selectedPlace"

    var selected: PlaceRef? {
        didSet {
            if let s = selected, let data = try? JSONEncoder().encode(s) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(PlaceRef.self, from: data) {
            selected = p
        }
    }
}

struct RootView: View {
    @Environment(ForecastStore.self) private var store
    @Environment(LocationManager.self) private var location
    @Environment(PlaceSelection.self) private var places
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("霞光", systemImage: "sun.horizon.fill") }
            GlowMapView()
                .tabItem { Label("地图", systemImage: "map.fill") }
            HistoryView()
                .tabItem { Label("记录", systemImage: "calendar") }
        }
        .tint(Theme.accent)
        .task { await bootstrap() }
        .onChange(of: places.selected) { _, new in
            guard let new else { return }
            Task { await store.refresh(place: new, context: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let p = places.selected,
                  let last = store.lastUpdated, Date.now.timeIntervalSince(last) > 1800 else { return }
            Task { await store.refresh(place: p, context: context) }
        }
    }

    private func bootstrap() async {
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.5)
        if let p = places.selected, !p.isCurrentLocation {
            await store.refresh(place: p, context: context)
            return
        }
        if let here = await location.currentPlace() {
            if places.selected == here { await store.refresh(place: here, context: context) }
            else { places.selected = here }
        } else if let p = places.selected {
            await store.refresh(place: p, context: context)
        } else {
            // 定位不可用时默认广州
            places.selected = PlaceRef(name: "广州", coordinate: Coordinate(latitude: 23.129, longitude: 113.264), isCurrentLocation: false)
        }
    }
}
