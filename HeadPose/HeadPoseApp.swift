//
//  HeadPoseApp.swift
//  HeadPose
//
//  Created by Luo Lab on 7/17/25.
//

import SwiftUI
import UIKit

// 1️⃣ Define an AppDelegate that locks orientation:
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Change this to .portrait, .landscape, or whichever mask you prefer
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct HeadPoseApp: App {
    // 2️⃣ Hook your AppDelegate into the SwiftUI lifecycle:
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
