import SwiftUI
import SwiftData
import MapKit

struct PlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LocationManager.self) private var location
    @Environment(PlaceSelection.self) private var places
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var saved: [SavedPlace]

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var locating = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        locating = true
                        Task {
                            if let p = await location.currentPlace() { places.selected = p; dismiss() }
                            locating = false
                        }
                    } label: {
                        HStack {
                            Label("使用当前位置", systemImage: "location.fill")
                            Spacer()
                            if locating { ProgressView() }
                        }
                    }
                    if location.isDenied {
                        Text("定位权限已关闭，可在「设置 › 霞光」中开启").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !results.isEmpty {
                    Section("搜索结果") {
                        ForEach(results, id: \.self) { item in
                            HStack {
                                Button { choose(item) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "未知地点").foregroundStyle(.primary)
                                        Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button { save(item) } label: { Image(systemName: "star") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("收藏的机位") {
                    if saved.isEmpty {
                        Text("搜索地点后点 ☆ 收藏，常去的机位一键切换").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(saved) { p in
                        Button {
                            places.selected = PlaceRef(name: p.name, coordinate: p.coordinate, isCurrentLocation: false)
                            dismiss()
                        } label: {
                            HStack {
                                Label(p.name, systemImage: "mappin.circle.fill")
                                Spacer()
                                if places.selected?.coordinate == p.coordinate {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(saved[i]) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("选择地点")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索城市、景点、山顶…")
            .onChange(of: query) { _, q in search(q) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }

    private func search(_ q: String) {
        searchTask?.cancel()
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            let resp = try? await MKLocalSearch(request: req).start()
            if !Task.isCancelled { results = resp?.mapItems ?? [] }
        }
    }

    private func ref(_ item: MKMapItem) -> PlaceRef {
        let c = item.placemark.coordinate
        return PlaceRef(name: item.name ?? "自定义地点", coordinate: Coordinate(latitude: c.latitude, longitude: c.longitude), isCurrentLocation: false)
    }

    private func choose(_ item: MKMapItem) {
        places.selected = ref(item)
        dismiss()
    }

    private func save(_ item: MKMapItem) {
        let r = ref(item)
        guard !saved.contains(where: { $0.coordinate.key == r.coordinate.key }) else { return }
        context.insert(SavedPlace(name: r.name, latitude: r.coordinate.latitude, longitude: r.coordinate.longitude))
        try? context.save()
    }
}
