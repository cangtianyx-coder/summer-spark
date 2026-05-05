import SwiftUI
import MapKit

// MARK: - Map View

struct MapView: View {
    @State private var showGroupMembers: Bool = true
    @State private var selectedMapType: MapTypeOption = .standard
    @State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    var body: some View {
        ZStack {
            // 地图
            MapKitMapView(region: $mapRegion, showMembers: showGroupMembers)
                .ignoresSafeArea()

            // 顶部控制面板
            VStack {
                // 地图类型选择器
                HStack {
                    Spacer()

                    Menu {
                        ForEach(MapTypeOption.allCases, id: \.self) { option in
                            Button(action: {
                                selectedMapType = option
                            }) {
                                HStack {
                                    Image(systemName: option.icon)
                                    Text(option.title)
                                    if selectedMapType == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedMapType.icon)
                            Text(selectedMapType.title)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
                .padding()

                Spacer()

                // 底部控制面板
                VStack(spacing: 12) {
                    // 群组成员开关
                    Toggle(isOn: $showGroupMembers) {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.blue)
                            Text("Show Group Members")
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)

                    // 定位按钮
                    HStack(spacing: 16) {
                        Button(action: centerOnUser) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("My Location")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }

                        Button(action: zoomToFitAll) {
                            HStack {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text("Fit All")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            centerOnUser()
        }
    }

    private func centerOnUser() {
        if let location = LocationManager.shared.currentLocation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }

    private func zoomToFitAll() {
        // 实际应从 MeshService 获取真实位置
        var coordinates: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4180)
        ]

        if let userLocation = LocationManager.shared.currentLocation {
            coordinates.append(CLLocationCoordinate2D(latitude: userLocation.latitude, longitude: userLocation.longitude))
        }

        if !coordinates.isEmpty {
            let minLat = coordinates.map { $0.latitude }.min() ?? 0
            let maxLat = coordinates.map { $0.latitude }.max() ?? 0
            let minLon = coordinates.map { $0.longitude }.min() ?? 0
            let maxLon = coordinates.map { $0.longitude }.max() ?? 0

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
                longitudeDelta: (maxLon - minLon) * 1.5 + 0.01
            )

            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
    }
}

// MARK: - MapKit Map View (UIKit Wrapper)

struct MapKitMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var showMembers: Bool

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)

        // 移除旧的群组成员标注
        let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(oldAnnotations)

        // 添加群组成员标注
        if showMembers {
            // 模拟数据 - 实际应从 MeshService 获取
            let member1 = MKPointAnnotation()
            member1.coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            member1.title = "Alice"

            let member2 = MKPointAnnotation()
            member2.coordinate = CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4180)
            member2.title = "Bob"

            mapView.addAnnotations([member1, member2])
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitMapView

        init(_ parent: MapKitMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let identifier = "MemberPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
                annotationView?.markerTintColor = .systemBlue
            } else {
                annotationView?.annotation = annotation
            }

            return annotationView
        }
    }
}

// MARK: - Map Type Option

enum MapTypeOption: String, CaseIterable {
    case standard
    case satellite
    case hybrid

    var title: String {
        switch self {
        case .standard: return "Vector Map"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas"
        case .hybrid: return "square.stack.3d.up"
        }
    }
}

// MARK: - Preview

#Preview {
    MapView()
}
