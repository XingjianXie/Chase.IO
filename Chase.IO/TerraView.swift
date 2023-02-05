//
//  TerraView.swift
//  Chase.IO
//
//  Created by 谢行健 on 05/02/2023.
//

import SwiftUI
import CoreBluetooth
import TerraRTiOS
import BetterSafariView

public struct TokenPayload: Decodable{
    let token: String
}

public func generateToken(devId: String, xAPIKey: String, userId: String) -> TokenPayload?{
    
    let url = URL(string: "https://ws.tryterra.co/auth/user?id=\(userId.lowercased())")
        
        guard let requestUrl = url else {fatalError()}
        var request = URLRequest(url: requestUrl)
        var result: TokenPayload? = nil
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "terra.token.generation")
        request.httpMethod = "POST"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue(devId, forHTTPHeaderField: "dev-id")
        request.setValue(xAPIKey, forHTTPHeaderField: "X-API-Key")
        
        let task = URLSession.shared.dataTask(with: request){(data, response, error) in
            print(response)
            if let data = data{
                let decoder = JSONDecoder()
                do{
                    result = try decoder.decode(TokenPayload.self, from: data)
                    group.leave()
                }
                catch{
                    print(error)
                    group.leave()
                }
            }
        }
        group.enter()
        queue.async(group: group) {
            task.resume()
        }
        group.wait()
        return result
}

struct Globals {
    static var shared = Globals()
    var shownDevices: [Device] = []
    let cornerradius : CGFloat = 10
    let smallpadding: CGFloat = 12
}

extension Color {
    public static var border : Color {
        Color.init(.sRGB, red: 226/255, green: 239/255, blue: 254/255, opacity: 1)
    }
    
    public static var background : Color {
        Color.init(.sRGB, red: 255/255, green: 255/255, blue: 255/255, opacity: 1)
    }
    
    public static var button : Color {
        Color.init(.sRGB, red: 96/255, green: 165/255, blue: 250/255, opacity: 1)
    }
    
    public static var accent: Color{
        Color.init(.sRGB, red: 42/255, green: 100/255, blue: 246/255, opacity: 1)
    }
}

struct WView: View {
    @Binding var connectFinished: Bool
    let refId: UUID
    
    struct TerraWidgetSessionCreateResponse:Decodable{
        var status: String = String()
        var url: String = String()
        var session_id: String = String()
    }
    //Generate Session ID -> URL (RECOMMENDED THAT THIS IS DONE ON THE BACKEND, THIS IS JUST FOR A DEMO)
    func getSessionId() -> String{
        let session_url = URL(string: "https://api.tryterra.co/v2/auth/generateWidgetSession")
        var url = ""
        var request = URLRequest(url: session_url!)
        let requestData = ["reference_id": refId.uuidString, "providers" : "GOOGLE", "language": "EN"]
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "widget.Terra")
        let jsonData = try? JSONSerialization.data(withJSONObject: requestData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DEVID, forHTTPHeaderField: "dev-id")
        request.setValue(XAPIKEY, forHTTPHeaderField: "X-API-Key")
        request.httpBody = jsonData
        let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
            if let data = data{
                let decoder = JSONDecoder()
                do{
                    let result = try decoder.decode(TerraWidgetSessionCreateResponse.self, from: data)
                    url = result.url
                    group.leave()
                }
                catch{
                    print(error)
                }
            }
        }
        group.enter()
        queue.async(group:group) {
            task.resume()
        }
        group.wait()
        print(url)
        return url
    }

    @State private var startingWebAuthenticationSession = false

     var body: some View {
        Button("Connect Terra") {
            self.startingWebAuthenticationSession = true
        }
        .webAuthenticationSession(isPresented: $startingWebAuthenticationSession) {
            WebAuthenticationSession(
                url: URL(string: getSessionId())!,
                callbackURLScheme: "tryterra"
            ) { callbackURL, error in
                if let callbackURL = callbackURL {
                    print(callbackURL.absoluteString)
                }
                if let error = error{
                    print(error)
                    connectFinished = true
                }
            }
        }.buttonStyle(.bordered)
     }
}

struct TerraView: View {
    
    let terraRT = TerraRT()
    let refId: UUID
    @Binding var userId: UUID
    @State var connectFinished: Bool = false
    init(uuid: UUID, userId: Binding<UUID>, bleSwitch: Binding<Bool>){
        terraRT.initConnection(type: .BLE)
        self._bleSwitch = bleSwitch
        self._userId = userId
        self.refId = uuid
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 24)]
    }
    
    @State private var showingWidget = false
    @Binding private var bleSwitch: Bool
    @State private var sensorSwitch = false

    var body: some View {
        VStack{
            if (connectFinished) {
                connection().padding([.leading, .trailing, .top, .bottom])
                    .overlay(
                        RoundedRectangle(cornerRadius: Globals.shared.cornerradius)
                            .stroke(Color.border, lineWidth: 1)
                    )
            } else {
                WView(connectFinished: $connectFinished, refId: refId)
            }
        }
    }
    
    private func connection() -> some View{
        HStack{
            Button(action: {
                showingWidget.toggle()
            }, label: {
                    Text("BLE")
                    .fontWeight(.bold)
                    .font(.system(size: 14))
                    .foregroundColor(.inverse)
                    .padding([.top, .bottom], Globals.shared.smallpadding)
                    .padding([.leading, .trailing])
                    .background(
                        Capsule()
                            .foregroundColor(.button)
                    )
            })
            .sheet(isPresented: $showingWidget){ terraRT.startBluetoothScan(type: .BLE, callback: {success in
                showingWidget.toggle()
                print(success)
            })}
            Toggle(isOn: $bleSwitch, label: {
                Text("Real Time").fontWeight(.bold)
                    .font(.system(size: 14))
                    .foregroundColor(.inverse)
                    .padding([.top, .bottom], Globals.shared.smallpadding)
                    .padding([.trailing])
            }).onChange(of: bleSwitch){bleSwitch in
                if (bleSwitch){
                    userId = userIdFromRefId(refID: refId)
                    terraRT.startRealtime(type: .BLE, token:generateToken(devId: DEVID, xAPIKey: XAPIKEY, userId:userId.uuidString)!.token, dataType: Set([.STEPS, .HEART_RATE]))
                }
                else {
                    terraRT.stopRealtime(type: .BLE)
                }
            }
        }

    }
}
