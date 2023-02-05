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
    let heartRate: Int
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

struct MapEntityExtended: Identifiable {
    let entity: any MapEntity
    let degree: Double
    var id: String {
        (entity.id as! UUID).uuidString + "-\(degree)"
    }
}

struct UpdateData: Codable {
    let pickups: [Pickup]
    let players: [Player]
    let secondsRemaining : Int
}

struct AnnotationView: View {
    @ObservedObject var viewModel: ContentViewModel
    let mapEntity: MapEntityExtended
    var body: some View {
        VStack(spacing: 0) {
            let color = viewModel.name == mapEntity.entity.username ? Color.blue : (mapEntity.entity.type == EntityType.pickup ? Color.orange : Color.red)
            if mapEntity.degree != -1 {
                let text = mapEntity.entity.radius > 20 ? "--" : "-"
                Text(text).font(.system(size: 40)).foregroundColor(color).frame(width: 40, height: 40).rotationEffect(Angle(degrees: mapEntity.degree))
            } else {
                VStack {
                    if (mapEntity.entity.type == .player) {
                        Text(mapEntity.entity.username)
                        if ((mapEntity.entity as! Player).heartRate != 0) {
                            Text("❤️ \((mapEntity.entity as! Player).heartRate)")
                        }
                    }
                    Text(String(mapEntity.entity.points))
                }.frame(width: 80, height: 40)
            }
        }
    }
}

/*
 let heartName = onFire ? "bolt.heart" : "heart"

Image(systemName: heartName)
    .resizable()
    .frame(width: 50, height: 50)
    .foregroundColor(.red)
    .overlay(Text ("\(heartRate)"), alignment: .center)

Image(systemName: "shield")
  .resizable()
  .frame(width: 50, height: 50)
  .foregroundColor(.white)

Image(systemName: "figure.fencing")
    .resizable()
    .frame(width: 50, height: 50)
    .foregroundColor(.white)

Image(systemName: "capsule")
    .resizable()
    .frame(width: 50, height: 50)
    .foregroundColor(.white)
    .overlay(Text ("\(points)"), alignment: .center)

HStack (spacing: 0) {
    Image(systemName: "capsule")
            .resizable()
            .frame(width: 50, height: 50)
            .foregroundColor(.white)
            .overlay(Text ("\(player.points)"), alignment: .center)
}
 */

extension BinaryFloatingPoint {
    var radians: Self {
        self * .pi / 180
    }
    var degree: Self {
        self / .pi * 180
    }
}

struct MapView: View {

    func computeOffset(from: CLLocationCoordinate2D, distance: Double, heading: Double) -> CLLocationCoordinate2D {
        let distance = distance / 6371009.0; //earth_radius = 6371009 # in meters
        let heading = heading.radians
        let fromLat = from.latitude.radians
        let fromLng = from.longitude.radians
        let cosDistance = cos(distance);
        let sinDistance = sin(distance);
        let sinFromLat = sin(fromLat);
        let cosFromLat = cos(fromLat);
        let sinLat = cosDistance * sinFromLat + sinDistance * cosFromLat * cos(heading);
        let dLng = atan2(sinDistance * cosFromLat * sin(heading), cosDistance - sinFromLat * sinLat);
        return CLLocationCoordinate2D(latitude: asin(sinLat).degree, longitude: (fromLng + dLng).degree);
    }

    func converted(_ entity: MapEntityExtended) -> CLLocationCoordinate2D {
        if (entity.degree != -1) {
            return computeOffset(from: entity.entity.coordinate, distance: entity.entity.radius, heading: entity.degree)
        } else {
            return entity.entity.coordinate
        }
    }

    func updateMap(updateData: UpdateData) {
        var tmp: [MapEntityExtended] = []
        var rangeList: [Int] = Array(stride(from: 0, to: 360, by: 30))
        rangeList.append(-1)
        tmp.append(contentsOf: updateData.players.flatMap{ entity in
            rangeList.map { i in
                MapEntityExtended(entity: entity, degree: Double(i))
            }
        })
        tmp.append(contentsOf: updateData.pickups.flatMap{ entity in
            rangeList.map { i in
                MapEntityExtended(entity: entity, degree: Double(i))
            }
        })
        
        DispatchQueue.main.sync {
            annotations = tmp
            
            var currentPlayer = updateData.players.first { p in p.username == viewModel.name }!
            
//            viewModel.region = MKCoordinateRegion(center: currentPlayer.coordinate, latitudinalMeters: currentPlayer.radius * 4, longitudinalMeters: currentPlayer.radius * 4)
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
                print(String(data: data, encoding: .utf8)!)
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
    
    @State var annotations: [MapEntityExtended] = []
    let uuid: UUID
    @Binding var userId: UUID
    let bleSwitch: Bool
    
    var body: some View {
        VStack {
            Map(coordinateRegion: $viewModel.region, annotationItems: annotations) { e in
                MapAnnotation(coordinate: converted(e)) {
                    AnnotationView(viewModel: viewModel, mapEntity: e)
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
//            else {
//                let minutes = updateData.secondsRemaining / 60
//                let seconds = updateData.secondsRemaining % 60
//                Text(String(minutes) + ":" + String(seconds))
//            }
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
        span: MKCoordinateSpan(latitudeDelta: 0.0008, longitudeDelta: 0.0008)
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
                center: locationManger.location!.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.0008, longitudeDelta: 0.0008))
        @unknown default:
            fatalError()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkAuth()
    }
}
