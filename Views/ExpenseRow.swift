import SwiftUI
import SwiftData

struct ExpenseRow: View {
    let expense: Expense
    let currency: String
    let members: [Member] // добавить массив участников для поиска по id

    var payerName: String {
        members.first(where: { $0.id == expense.paidById })?.name ?? "?"
    }
    var participantNames: String {
        let ids = expense.splits.map { $0.memberId }
        let names = members.filter { ids.contains($0.id) }.map { $0.name }
        return names.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expense.title)
                .font(.headline)
            HStack {
                Text("Сумма: \(expense.amount.description) \(currency)")
                    .font(.subheadline)
                Spacer()
                Text("Плательщик: \(payerName)")
                    .font(.subheadline)
            }
            if !expense.splits.isEmpty {
                Text("Участвуют: \(participantNames)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
