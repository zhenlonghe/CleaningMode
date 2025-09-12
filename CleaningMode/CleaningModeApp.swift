//
//  CleaningModeApp.swift
//  CleaningMode
//
//  Created by Zhenlong on 2025/9/9.
//

import SwiftUI

@main
struct CleaningModeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 420)
    }
}
