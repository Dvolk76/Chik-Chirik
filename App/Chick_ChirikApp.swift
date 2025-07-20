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
    var body: some View {
        switch authVM.screenState {
        case .auth:
            AuthView(authVM: authVM)
                .environmentObject(authVM)
        case .sync:
            AuthView(authVM: authVM)
                .environmentObject(authVM) // sync UI внутри AuthView
        case .trips:
            TripListView()
                .environmentObject(authVM)
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

