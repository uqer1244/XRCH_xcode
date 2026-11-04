import Combine
import CoreLocation
import MapKit
import SwiftUI

/// Independent of AI recommendations, authentication, and the Quest location bridge.
@MainActor
final class NearbyRestaurantStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase: Equatable {
        case idle, locating, searching, loaded, failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var places: [CompanionPOI] = []
    @Published private(set) var searchedRadius = 500

    private let manager = CLLocationManager()
    private var lastLoadedAt: Date?
    private var locationTimeout: Task<Void, Never>?
    private var search: MKLocalSearch?

    var isLoading: Bool { phase == .locating || phase == .searching }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func load(radius: Int, force: Bool = false) {
        guard !isLoading else { return }
        if !force, radius == searchedRadius, let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) < 300 { return }
        searchedRadius = min(1000, max(100, radius))
        phase = .locating
        locationTimeout?.cancel()
        locationTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.phase == .locating else { return }
            self.phase = .failed("위치 확인에 시간이 걸리고 있어요. 위치 권한과 GPS 상태를 확인한 뒤 다시 시도해 주세요.")
        }
        requestLocationIfAuthorized()
    }

    private func requestLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            fail("주변 음식점을 찾으려면 위치 접근을 허용해 주세요.")
        @unknown default:
            fail("위치를 사용할 수 없어요. iPhone 설정에서 위치 권한을 확인해 주세요.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard phase == .locating else { return }
        requestLocationIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .locating else { return }
        guard let origin = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120
        }) else {
            fail("최근 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return
        }
        locationTimeout?.cancel()
        phase = .searching
        let radius = searchedRadius
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "음식점"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: origin.coordinate,
            latitudinalMeters: Double(radius) * 2, longitudinalMeters: Double(radius) * 2)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
        if #available(iOS 18.0, *) { request.regionPriority = .required }
        let search = MKLocalSearch(request: request)
        self.search = search
        Task { [weak self] in
            do {
                let response = try await search.start()
                guard let self else { return }
                var seen: Set<String> = []
                let results = response.mapItems.compactMap { item -> CompanionPOI? in
                    let coordinate = item.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(coordinate), let name = item.name, !name.isEmpty else { return nil }
                    let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                    guard distance <= Double(radius) else { return nil }
                    let id = "mapkit:\(name):\(String(format: "%.6f", coordinate.latitude)):\(String(format: "%.6f", coordinate.longitude))"
                    guard seen.insert(id).inserted else { return nil }
                    return CompanionPOI(id: id, name: name, category: "음식점",
                        address: item.placemark.title ?? "주소 정보 없음",
                        summary: "Apple 지도에서 찾은 주변 음식점", latitude: coordinate.latitude,
                        longitude: coordinate.longitude, distanceMeters: Int(distance.rounded()), rating: 0)
                }
                .sorted {
                    $0.distanceMeters == $1.distanceMeters ? $0.name < $1.name : $0.distanceMeters < $1.distanceMeters
                }
                self.places = Array(results.prefix(7))
                self.lastLoadedAt = Date()
                self.phase = .loaded
                self.search = nil
            } catch {
                guard let self else { return }
                let failure = error as NSError
                #if DEBUG
                NSLog("Nearby MapKit result: %@ (%ld)", failure.domain, failure.code)
                #endif
                if failure.domain == MKErrorDomain && failure.code == MKError.Code.placemarkNotFound.rawValue {
                    self.places = []
                    self.lastLoadedAt = Date()
                    self.phase = .loaded
                    self.search = nil
                } else {
                    self.fail("음식점을 불러오지 못했어요. 네트워크 연결을 확인하고 다시 시도해 주세요.")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard phase == .locating else { return }
        fail("현재 위치를 확인하지 못했어요. 위치 권한과 GPS 상태를 확인해 주세요.")
    }

    private func fail(_ message: String) {
        locationTimeout?.cancel()
        phase = .failed(message)
        search = nil
    }
}

struct NearbyRestaurantsSection: View {
    @StateObject private var store = NearbyRestaurantStore()
    @EnvironmentObject private var model: CompanionAppModel
    @AppStorage("companionSearchRadius") private var radius = 500.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("지금 내 주변 음식점").font(.title3.bold())
                Spacer()
                Button {
                    store.load(radius: Int(radius), force: true)
                } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(store.isLoading)
                .accessibilityLabel("주변 음식점 새로고침")
            }
            Text("Apple 지도 · 반경 \(store.searchedRadius)m · 가까운 순 최대 7곳")
                .font(.caption).foregroundStyle(.secondary)

            if store.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(store.phase == .locating ? "현재 위치를 확인하는 중…" : "근처 음식점을 찾는 중…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            } else if case .failed(let message) = store.phase {
                VStack(alignment: .leading, spacing: 12) {
                    Label(message, systemImage: "location.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button("다시 시도") { store.load(radius: Int(radius), force: true) }
                            .buttonStyle(.bordered)
                        Link("위치 설정", destination: URL(string: UIApplication.openSettingsURLString)!)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }

            if store.phase == .loaded && store.places.isEmpty {
                Label("이 범위에서는 음식점을 찾지 못했어요. 지도 탭에서 검색 반경을 넓혀보세요.", systemImage: "fork.knife")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16)
            }
            ForEach(store.places) { poi in
                Button { model.selectedPOI = poi } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "fork.knife")
                            .font(.title3).foregroundStyle(.indigo)
                            .frame(width: 46, height: 46)
                            .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(poi.name).font(.headline).foregroundStyle(.primary)
                            Text(poi.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text("\(poi.distanceMeters)m").font(.subheadline.weight(.medium))
                            .foregroundStyle(.indigo).monospacedDigit()
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            if !store.places.isEmpty && store.searchedRadius != Int(radius) {
                Text("검색 반경이 바뀌었어요. 새로고침하면 반경 \(Int(radius))m로 다시 찾습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { store.load(radius: Int(radius)) }
        .onReceive(store.$places) { model.nearbyPOIs = $0 }
    }
}
