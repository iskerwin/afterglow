import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var continuation: CheckedContinuation<CLLocation?, Never>?

    var authorization: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// 获取一次当前位置并反查地名
    func currentPlace() async -> PlaceRef? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // 等待用户授权
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if manager.authorizationStatus != .notDetermined { break }
            }
        }
        authorization = manager.authorizationStatus
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { return nil }

        let loc: CLLocation? = await withCheckedContinuation { cont in
            continuation?.resume(returning: nil)
            continuation = cont
            manager.requestLocation()
        }
        guard let loc else { return nil }
        let name = await Self.placeName(for: loc) ?? "当前位置"
        return PlaceRef(name: name,
                        coordinate: Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude),
                        isCurrentLocation: true)
    }

    static func placeName(for loc: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "zh_CN"))
        guard let p = marks?.first else { return nil }
        return p.subLocality ?? p.locality ?? p.administrativeArea ?? p.name
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in
            self.continuation?.resume(returning: loc)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}
