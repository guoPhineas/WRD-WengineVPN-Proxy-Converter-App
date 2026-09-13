//
//  WRDWebVPN_ConvertApp.swift
//  WRDWebVPN-Convert
//
//  Created by Phineas Guo on 2026/9/13.
//

import SwiftUI

@main
struct WRDWebVPN_ConvertApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 680)
        #endif
    }
}
