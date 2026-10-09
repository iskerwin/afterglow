import SwiftUI
import SwiftData
import PhotosUI

struct ObservationEditor: View {
    var observation: Observation?
    var defaultKind: SkyEventKind

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ForecastStore.self) private var store
    @Environment(PlaceSelection.self) private var places

    @State private var date = Date.now
    @State private var kind: SkyEventKind = .sunset
    @State private var rating = 3
    @State private var note = ""
    @State private var photo: Data?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack {
                            if let d = photo, let ui = UIImage(data: d) {
                                Image(uiImage: ui).resizable().scaledToFill()
                            } else {
                                LinearGradient(colors: Theme.sky(for: Double(rating) * 20, kind: kind), startPoint: .top, endPoint: .bottom)
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.badge.plus").font(.system(size: 28))
                                    Text("添加照片").font(.rounded(13, .medium))
                                }
                                .foregroundStyle(.white)
                            }
                        }
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                }

                Section("实际效果") {
                    Picker("类型", selection: $kind) {
                        ForEach(SkyEventKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                withAnimation(.spring) { rating = i }
                            } label: {
                                Image(systemName: i <= rating ? "star.fill" : "star")
                                    .font(.system(size: 28))
                                    .foregroundStyle(i <= rating ? Theme.color(for: Double(i) * 20) : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text(["", "几乎没颜色", "淡淡的霞", "小烧", "中烧", "大烧！"][rating])
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    DatePicker("时间", selection: $date)
                }

                Section("备注") {
                    TextField("机位、参数、心情…", text: $note, axis: .vertical).lineLimit(2...5)
                }

                if let p = predicted {
                    Section {
                        HStack {
                            Text("当时预测")
                            Spacer()
                            ScoreChip(score: p)
                        }
                    }
                }
            }
            .navigationTitle(observation == nil ? "实拍打卡" : "编辑打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.bold() }
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photo = Self.downscale(data)
                }
            }
            .onAppear(perform: load)
        }
        .tint(Theme.accent)
    }

    /// 在同一天同类型的预测记录中找出当时的分数
    private var predicted: Double? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = store.timeZone
        if let e = store.events.first(where: { $0.kind == kind && cal.isDate($0.dayStart, inSameDayAs: date) }) {
            return e.score
        }
        return observation?.predictedScore
    }

    private func load() {
        if let o = observation {
            date = o.date; kind = o.kind; rating = o.rating; note = o.note; photo = o.photo
        } else {
            kind = defaultKind
            if let e = store.events.last(where: { $0.kind == defaultKind && $0.isPast }) { date = e.peakTime }
        }
    }

    private func save() {
        if let o = observation {
            o.date = date; o.kindRaw = kind.rawValue; o.rating = rating; o.note = note; o.photo = photo
            o.predictedScore = predicted
        } else {
            context.insert(Observation(date: date, kind: kind, placeName: places.selected?.name ?? "",
                                       rating: rating, note: note, predictedScore: predicted, photo: photo))
        }
        try? context.save()
        dismiss()
    }

    private static func downscale(_ data: Data) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let out = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.82) ?? data
    }
}
