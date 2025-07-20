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
        Group {
            if authVM.user == nil || (authVM.user?.isAnonymous == true && !authVM.shouldShowTripsAfterAnonLogin && authVM.linkedOwnerUid == nil) {
                AuthView(authVM: authVM)
                    .environmentObject(authVM)
            } else {
                TripListView()
                    .environmentObject(authVM)
                    .onAppear {
                        if authVM.shouldShowTripsAfterAnonLogin {
                            authVM.shouldShowTripsAfterAnonLogin = false
                        }
                    }
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

