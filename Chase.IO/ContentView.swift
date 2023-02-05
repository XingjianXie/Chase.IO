//
//  ContentView.swift
//  Chase.IO
//
//  Created by 谢行健 on 04/02/2023.
//

import SwiftUI


struct ContentView: View {
    @State var bleSwitch: Bool = false
    @State var userId = UUID()
    let uuid =  UUID()
    var body: some View {
        
        TabView {
            TerraView(uuid: uuid, userId: $userId, bleSwitch: $bleSwitch).tabItem {
                Label("Link Device", systemImage: "star")
            }
            MapView(uuid: uuid, userId: $userId, bleSwitch: bleSwitch).tabItem {
                Label("Map", systemImage: "star")
            }
        }
    }
}
