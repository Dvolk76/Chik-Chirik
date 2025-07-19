//
//  Chick_ChirikApp.swift
//  Chick-Chirik
//
//  Created by Dmitry Volkov on 15.07.25.
//

import SwiftUI
import SwiftData
import Firebase

struct RootView: View {
    @StateObject var authVM = AuthViewModel()
    // Удаляем groupVM, он больше не нужен

    var body: some View {
        SwiftUI.Group {
            if authVM.user == nil {
                AuthView(authVM: authVM)
                    .environmentObject(authVM)
            } else {
                TripListView()
                    .environmentObject(authVM)
            }
        }
    }
}

@main
struct ChickChirikApp: App {
    init() {
        FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: Trip.self)
        }
    }
}

