import Foundation
import SwiftData

/// 收藏的机位 / 地点
@Model
final class SavedPlace {
    var name: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = .now
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// 每次刷新都会把每个日出/日落事件的指数写入这里，形成历史档案
/// - forecastScore：事件发生前最后一次的预测值
/// - hindcastScore：事件发生后用实况分析数据回算的值
@Model
final class PredictionRecord {
    @Attribute(.unique) var key: String
    var placeKey: String
    var placeName: String
    var eventDate: Date
    var kindRaw: String
    var forecastScore: Double?
    var hindcastScore: Double?
    var updatedAt: Date

    init(key: String, placeKey: String, placeName: String, eventDate: Date, kind: SkyEventKind) {
        self.key = key
        self.placeKey = placeKey
        self.placeName = placeName
        self.eventDate = eventDate
        self.kindRaw = kind.rawValue
        self.updatedAt = .now
    }

    var kind: SkyEventKind { SkyEventKind(rawValue: kindRaw) ?? .sunset }
    var bestScore: Double? { hindcastScore ?? forecastScore }
}

/// 用户的实拍打卡
@Model
final class SkyObservation {
    var date: Date
    var kindRaw: String
    var placeName: String
    var rating: Int            // 0–5 星
    var note: String
    var predictedScore: Double?
    @Attribute(.externalStorage) var photo: Data?

    init(date: Date, kind: SkyEventKind, placeName: String, rating: Int, note: String, predictedScore: Double?, photo: Data?) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.placeName = placeName
        self.rating = rating
        self.note = note
        self.predictedScore = predictedScore
        self.photo = photo
    }

    var kind: SkyEventKind { SkyEventKind(rawValue: kindRaw) ?? .sunset }
}
