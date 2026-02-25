//
//  iStepsApp.swift
//  iSteps
//
//  Created by Данил Белов on 04.07.2023.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct iStepsApp: App {
    init() {
        FirebaseApp.configure()
        // 🔥 测试用：每次启动都清除登录状态
        try? Auth.auth().signOut()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
