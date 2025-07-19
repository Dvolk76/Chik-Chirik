import SwiftUI
import SwiftData

struct ExpenseRow: View {
    let expense: Expense
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expense.title)
                .font(.headline)
            HStack {
                Text("Сумма: \(expense.amount.description) \(currency)")
                    .font(.subheadline)
                Spacer()
                Text("Плательщик: \(expense.paidBy.name)")
                    .font(.subheadline)
            }
            if !expense.splits.isEmpty {
                Text("Участвуют: \(expense.splits.map { $0.member.name }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
