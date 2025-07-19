//
//  SettleUpView.swift
//  Chick-Chirik
//
//  Created by Dmitry Volkov on 16.07.25.
//

import SwiftUI
import SwiftData

struct SettleUpView: View {
    var trip: Trip
    @EnvironmentObject var authVM: AuthViewModel

    var activeUid: String? {
        authVM.linkedOwnerUid ?? authVM.user?.uid
    }

    var payments: [(from: Member, to: Member, amount: Decimal)] {
        let balances = computeBalances(for: trip)
        return simplify(balances)
    }

    var body: some View {
        List {
            if payments.isEmpty {
                Text("Никто никому не должен 🎉")
            } else {
                ForEach(Array(payments.enumerated()), id: \.offset) { _, payment in
                    Text("\(payment.from.name) → \(payment.to.name): \(String(format: "%.2f", NSDecimalNumber(decimal: payment.amount).doubleValue)) \(trip.currency)")
                }
            }
        }
        .navigationTitle("Итоговые долги")
    }
}
