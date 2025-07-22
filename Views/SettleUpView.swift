//
//  SettleUpView.swift
//  Chick-Chirik
//
//  Created by Dmitry Volkov on 16.07.25.
//

import SwiftUI
import SwiftData

// Вью рассчитывает долги на основе актуальных данных из TripDetailViewModel,
// а не из устаревшего snapshot'а Trip, переданного по ссылке.

struct SettleUpView: View {
    var trip: Trip
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var viewModel: TripDetailViewModel // актуальные members/expenses

    var activeUid: String? {
        authVM.linkedOwnerUid ?? authVM.user?.uid
    }

    var payments: [(from: Member, to: Member, amount: Decimal)] {
        let balances = computeBalances(members: viewModel.members, expenses: viewModel.expenses)
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

// MARK: - Локальный расчёт балансов
private func computeBalances(members: [Member], expenses: [Expense]) -> [Member: Decimal] {
    var net = Dictionary(uniqueKeysWithValues: members.map { ($0, Decimal(0)) })
    let memberById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
    for expense in expenses {
        if let payer = memberById[expense.paidById] {
            net[payer, default: 0] += expense.amount
        }
        for split in expense.splits {
            if let member = memberById[split.memberId] {
                net[member, default: 0] -= expense.amount * split.share
            }
        }
    }
    return net
}
