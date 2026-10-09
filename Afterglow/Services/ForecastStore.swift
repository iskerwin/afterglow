import Foundation
import SwiftData
import Observation

/// 一次日出 / 日落事件的预报
struct SkyEvent: Identifiable, Hashable {
    var id: String { "\(kind.rawValue)-\(Int(sunTime.timeIntervalSince1970))" }
    var kind: SkyEventKind
    var dayStart: Date
    var sunTime: Date               // 日出 / 日落时刻
    var peakTime: Date              // 霞光最佳时刻（日落后约 10 分钟 / 日出前约 10 分钟）
    var golden: DateInterval?
    var blue: DateInterval?
    var result: GlowResult

    var score: Double { result.score }
    var isPast: Bool { peakTime < .now }
}

@MainActor
@Observable
final class ForecastStore {
    static let pastDays = 21
    static let forecastDays = 7

    var place: PlaceRef?
    var events: [SkyEvent] = []
    var field: CloudField?
    var aod: AODSeries?
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    var timeZone: TimeZone { field?.timeZone ?? .current }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    var upcoming: [SkyEvent] { events.filter { !$0.isPast || $0.peakTime > Date.now.addingTimeInterval(-1800) } }

    /// 最近一个尚未结束的事件
    var nextEvent: SkyEvent? { upcoming.first }

    func refresh(place: PlaceRef, context: ModelContext) async {
        self.place = place
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let spec = OpenMeteoClient.GridSpec.around(place.coordinate, size: 5, spacingKm: 50)
            async let fieldTask = OpenMeteoClient.cloudField(spec, range: .relative(pastDays: Self.pastDays, forecastDays: Self.forecastDays))
            async let aodTask = OpenMeteoClient.aod(place.coordinate, pastDays: Self.pastDays, forecastDays: 5)
            let field = try await fieldTask
            let aod = await aodTask
            self.field = field
            self.aod = aod
            self.events = Self.buildEvents(field: field, at: place.coordinate, aod: aod)
            self.lastUpdated = .now
            persist(place: place, context: context)
            await NotificationScheduler.reschedule(events: events, placeName: place.name)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    nonisolated static func buildEvents(field: CloudField, at c: Coordinate, aod: AODSeries?) -> [SkyEvent] {
        guard let range = field.centerSeries.range else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = field.timeZone
        var day = cal.startOfDay(for: Date(timeIntervalSince1970: range.lowerBound))
        let end = Date(timeIntervalSince1970: range.upperBound)
        var out: [SkyEvent] = []
        while day < end {
            let sd = SolarCalculator.day(c, dayStart: day)
            if let rise = sd.sunrise {
                let peak = rise.addingTimeInterval(-10 * 60)
                if let r = GlowScorer.score(field: field, at: c, time: peak, aod: aod?.value(at: peak)) {
                    out.append(SkyEvent(kind: .sunrise, dayStart: day, sunTime: rise, peakTime: peak,
                                        golden: sd.morningGolden, blue: sd.morningBlue, result: r))
                }
            }
            if let set = sd.sunset {
                let peak = set.addingTimeInterval(10 * 60)
                if let r = GlowScorer.score(field: field, at: c, time: peak, aod: aod?.value(at: peak)) {
                    out.append(SkyEvent(kind: .sunset, dayStart: day, sunTime: set, peakTime: peak,
                                        golden: sd.eveningGolden, blue: sd.eveningBlue, result: r))
                }
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return out.sorted { $0.peakTime < $1.peakTime }
    }

    private func persist(place: PlaceRef, context: ModelContext) {
        let pk = place.coordinate.key
        for e in events {
            let key = "\(pk)|\(Int(e.dayStart.timeIntervalSince1970))|\(e.kind.rawValue)"
            let desc = FetchDescriptor<PredictionRecord>(predicate: #Predicate { $0.key == key })
            let rec: PredictionRecord
            if let existing = try? context.fetch(desc).first {
                rec = existing
            } else {
                rec = PredictionRecord(key: key, placeKey: pk, placeName: place.name, eventDate: e.peakTime, kind: e.kind)
                context.insert(rec)
            }
            if e.isPast { rec.hindcastScore = e.score } else { rec.forecastScore = e.score }
            rec.eventDate = e.peakTime
            rec.placeName = place.name
            rec.updatedAt = .now
        }
        try? context.save()
    }
}
