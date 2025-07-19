import SwiftData
import Foundation

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var name: String
    var currency: String = "RUB"
    var created: Date = Date()
    var closed: Bool
    var ownerUid: String // <--- добавлено для фильтрации по владельцу
    @Relationship var members: [Member]
    @Relationship var expenses: [Expense]
    
    init(
        name: String,
        currency: String = "RUB",
        created: Date = Date(),
        members: [Member] = [],
        expenses: [Expense] = [],
        closed: Bool = false,
        ownerUid: String // <--- добавлено
    ) {
        self.id = UUID()
        self.name = name
        self.currency = currency
        self.created = created
        self.members = members
        self.expenses = expenses
        self.closed = closed
        self.ownerUid = ownerUid // <--- добавлено
    }
    
    // MARK: - Test Helpers
    var totalExpenses: Decimal {
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    func membersWithExpenses() -> [Member] {
        let expenseMembers = expenses.flatMap { $0.splits.map { $0.member } }
        return Array(Set(expenseMembers))
    }
}

@Model
final class Member: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var name: String
    var isOwner: Bool
    
    init(name: String, isOwner: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isOwner = isOwner
    }
    // Новый инициализатор для поддержки парсинга из Firestore
    init(id: UUID, name: String, isOwner: Bool = false) {
        self.id = id
        self.name = name
        self.isOwner = isOwner
    }
    
    static func == (lhs: Member, rhs: Member) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var title: String
    var amount: Decimal
    var paidBy: Member
    @Relationship var splits: [Split]
    var date: Date
    
    init(
        title: String,
        amount: Decimal,
        paidBy: Member,
        splits: [Split] = [],
        date: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.paidBy = paidBy
        self.splits = splits
        self.date = date
    }
    
    // MARK: - Test Helpers
    var totalSplitShares: Decimal {
        splits.reduce(0) { $0 + $1.share }
    }
    
    func amountForMember(_ member: Member) -> Decimal {
        guard let split = splits.first(where: { $0.member == member }) else { return 0 }
        return amount * split.share
    }
}

@Model
final class Split {
    var member: Member
    var share: Decimal
    
    init(member: Member, share: Decimal) {
        self.member = member
        self.share = share
    }
}
