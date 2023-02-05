//
//  ContentView.swift
//  Chase.IO
//
//  Created by 谢行健 on 04/02/2023.
//

import SwiftUI
import MapKit

extension CLLocationCoordinate2D : Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

extension CLLocationCoordinate2D : Decodable {
    public init(from decoder: Decoder) throws {
        let values = try! decoder.container(keyedBy: CodingKeys.self)
        self = .init(latitude: try! values.decode(Double.self, forKey: .latitude), longitude: try! values.decode(Double.self, forKey: .longitude))
    }
}

enum CodingKeys: String, CodingKey {
    case latitude
    case longitude
}

struct StartGameData: Encodable {
    let coordinate: CLLocationCoordinate2D
    let username: String
    let radius: Double
    let uuid: String
}

struct Pickup: Codable, MapEntity {
    let uuid: String
    var id: UUID {
        UUID(uuidString: uuid)!
    }
    let username: String = "Pickup"
    let points: Int
    let radius: Double
    let coordinate: CLLocationCoordinate2D
    let type = EntityType.pickup
}

struct Player: Codable, MapEntity {
    let uuid: String
    var id: UUID {
        UUID(uuidString: uuid)!
    }
    let username: String
    let points: Int
    let radius: Double
    let coordinate: CLLocationCoordinate2D
    let type = EntityType.player
}

enum EntityType: Codable {
    case player
    case pickup
}

protocol MapEntity: Identifiable {
    var username: String { get }
    var points: Int { get }
    var radius: Double { get }
    var coordinate:CLLocationCoordinate2D { get }
    var type: EntityType { get }
}

struct MapEntityT: Identifiable {
    let entity: any MapEntity
    var id: UUID {
        entity.id as! UUID
    }
}

struct UpdateData: Codable {
    let pickups: [Pickup]
    let players: [Player]
}

struct AnnotationView: View {
    @ObservedObject var viewModel: ContentViewModel
    let mapEntity: any MapEntity
    var body: some View {
        VStack(spacing: 0) {
            let color = viewModel.name == mapEntity.username ? Color.blue : (mapEntity.type == EntityType.pickup ? Color.orange : Color.red)
            let minSize = 10.0
            Circle().stroke(color, lineWidth: 4 + mapEntity.radius / 10)
            .frame(width: (minSize + mapEntity.radius) * 3, height: (minSize + mapEntity.radius) * 3, alignment: .center)
        }.overlay(
            VStack {
                if (mapEntity.type != EntityType.pickup) {
                    Text(mapEntity.username)
                    Text(String(mapEntity.points))
                } else {
                    Text(String(mapEntity.points))
                }
            }
        )
    }
}

struct MapView: View {
    func updateMap(updateData: UpdateData) {
        var tmp: [MapEntityT] = []
        tmp.append(contentsOf: updateData.players.map{MapEntityT(entity: $0)})
        tmp.append(contentsOf: updateData.pickups.map{MapEntityT(entity: $0)})
        
        DispatchQueue.main.sync {
            annotations = tmp
            
            var currentPlayer = updateData.players.first { p in p.username == viewModel.name }!
            
            viewModel.region = MKCoordinateRegion(center: currentPlayer.coordinate, latitudinalMeters: currentPlayer.radius * 4, longitudinalMeters: currentPlayer.radius * 4)
        }
    }
    
    func workThread() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            if !viewModel.started {
                return
            }
            
            let loc = viewModel.locationManger?.location?.coordinate
            guard let loc = loc else { print("Can't find location"); return }

            let info = StartGameData(coordinate: loc, username: viewModel.name, radius: 0, uuid: userId.uuidString.lowercased())
            
            sendRequest(api: "update_game", info: info) { data, response, error in
                guard let data = data else { print("Network error"); return }
                let updateData = try! JSONDecoder().decode(UpdateData.self, from: data)
                print(updateData)
                print("update successful")
                updateMap(updateData: updateData)
            }
        })
    }
    
    func sendRequest(api: String, info: Encodable, handler: @escaping (Data?, URLResponse?, Error?) -> Void) {
        let addr = URL(string: "http://146.169.227.250:4567/" + api)!
        
        var request = URLRequest(url: addr)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.httpBody = try! JSONEncoder().encode(info)
        let task = URLSession.shared.dataTask(with: request, completionHandler: handler)
        task.resume()
    }
    
    @StateObject private var viewModel = ContentViewModel()
    
    @State var annotations: [MapEntityT] = []
    let uuid: UUID
    @Binding var userId: UUID
    let bleSwitch: Bool
    
    var body: some View {
        VStack {
            Map(coordinateRegion: $viewModel.region, annotationItems: annotations) { e in
                MapAnnotation(coordinate: e.entity.coordinate) {
                    AnnotationView(viewModel: viewModel, mapEntity: e.entity)
                }
            }.alert(isPresented: $viewModel.alert) {
                Alert(title: Text("Location service not enabled"))
            }.ignoresSafeArea(.all).onAppear {
                viewModel.checkLocationEnabled()
                workThread()
            }
            if !viewModel.started {
                Group {
                    TextField("Name", text: $viewModel.name).padding()
                    Button("Start Game") {
                        var info = StartGameData(coordinate: viewModel.locationManger!.location!.coordinate, username: viewModel.name, radius: 20, uuid: userId.uuidString.lowercased())
                        
                        sendRequest(api: "start_game", info: info) { data, response, error in
                            guard let data = data else { print("Network error"); return }
                            let res = String(data: data, encoding: .utf8)
                            if (res == "200") {
                                viewModel.started = true;
                            }
                        }
                        
                    }.padding().buttonStyle(.bordered).disabled(viewModel.name == "")
                }
            }
        }
    }
}

final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    var locationManger: CLLocationManager?
    @Published var name: String = ""
    @Published var started: Bool = false
    @Published var alert: Bool = false
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.334_900,
                                       longitude: -122.009_020),
        latitudinalMeters: 750,
        longitudinalMeters: 750
    )
    
    func checkLocationEnabled() {
        if CLLocationManager.locationServicesEnabled() {
            locationManger = CLLocationManager()
            locationManger!.delegate = self
        } else {
            alert = true
        }
    }
    
    func checkAuth() {
        guard let locationManger = locationManger else { return }
        
        switch locationManger.authorizationStatus {
        case .notDetermined:
            locationManger.requestWhenInUseAuthorization()
        case .restricted, .denied:
            alert = true
        case .authorizedAlways, .authorizedWhenInUse:
            print(locationManger.location!.coordinate.latitude)
            print(locationManger.location!.coordinate.longitude)
            region = MKCoordinateRegion(
                center: locationManger.location!.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        @unknown default:
            fatalError()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkAuth()
    }
}
