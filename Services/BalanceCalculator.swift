import Foundation

func computeBalances(for trip: Trip) -> [Member: Decimal] {
    var net = Dictionary(uniqueKeysWithValues: trip.members.map { ($0, Decimal(0)) })
    let memberById = Dictionary(uniqueKeysWithValues: trip.members.map { ($0.id, $0) })
    for expense in trip.expenses {
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

func simplify(_ balances: [Member: Decimal]) -> [(from: Member, to: Member, amount: Decimal)] {
    var debtors = balances.filter { $0.value < 0 }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }
    var creditors = balances.filter { $0.value > 0 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    var payments: [(Member, Member, Decimal)] = []
    
    while let debtor = debtors.first, let creditor = creditors.first {
        let amount = min(debtor.1, creditor.1)
        payments.append((debtor.0, creditor.0, amount))
        
        if debtor.1 > creditor.1 {
            debtors[0].1 -= amount
            creditors.removeFirst()
        } else if creditor.1 > debtor.1 {
            creditors[0].1 -= amount
            debtors.removeFirst()
        } else {
            debtors.removeFirst()
            creditors.removeFirst()
        }
    }
    
    return payments
}

// MARK: - Test Helpers
extension Array where Element == (from: Member, to: Member, amount: Decimal) {
    var totalAmount: Decimal {
        reduce(0) { $0 + $1.amount }  // Исправлено: $1 вместо $2
    }
    
    func paymentsFrom(_ member: Member) -> [Element] {
        filter { $0.from == member }
    }
    
    func paymentsTo(_ member: Member) -> [Element] {
        filter { $0.to == member }
    }
}
