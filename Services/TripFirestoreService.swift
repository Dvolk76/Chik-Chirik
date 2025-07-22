import Foundation
import FirebaseFirestore
import Combine

class TripFirestoreService: ObservableObject {
    @Published var trips: [Trip] = []
    private var tripsListener: ListenerRegistration?
    private var expensesListeners: [String: ListenerRegistration] = [:]
    private let db = Firestore.firestore()

    // Слушать все поездки пользователя
    func listenTrips(for ownerUid: String) {
        print("TripFirestoreService.listenTrips: subscribing for ownerUid =", ownerUid)
        tripsListener?.remove()
        tripsListener = db.collection("trips").whereField("ownerUid", isEqualTo: ownerUid)
            .addSnapshotListener { [weak self] snap, err in
                print("Firestore snapshot for ownerUid =", ownerUid, "docs:", snap?.documents.count ?? 0)
                guard let self = self else { return }
                if let docs = snap?.documents {
                    self.trips = docs.compactMap { TripFirestoreService.tripFromFirestore(doc: $0) }
                }
            }
    }

    // Добавить поездку
    func addTrip(_ trip: Trip, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": trip.id.uuidString,
            "name": trip.name,
            "currency": trip.currency,
            "created": trip.created.timeIntervalSince1970,
            "closed": trip.closed,
            "ownerUid": trip.ownerUid
        ]
        db.collection("trips").document(trip.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Обновить поездку
    func updateTrip(_ trip: Trip, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": trip.id.uuidString,
            "name": trip.name,
            "currency": trip.currency,
            "created": trip.created.timeIntervalSince1970,
            "closed": trip.closed,
            "ownerUid": trip.ownerUid
        ]
        db.collection("trips").document(trip.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Удалить поездку
    func deleteTrip(_ trip: Trip, completion: ((Bool) -> Void)? = nil) {
        guard let id = trip.id.uuidString as String? else { completion?(false); return }
        db.collection("trips").document(id).delete { err in
            completion?(err == nil)
        }
    }

    // Загрузить участников поездки
    func fetchMembers(tripId: String, completion: @escaping ([Member]) -> Void) {
        db.collection("trips").document(tripId).collection("members").getDocuments { snap, err in
            guard let docs = snap?.documents else { completion([]); return }
            let members = docs.compactMap { doc -> Member? in
                let d = doc.data()
                guard let name = d["name"] as? String,
                      let idString = d["id"] as? String,
                      let id = UUID(uuidString: idString) else { return nil }
                let isOwner = d["isOwner"] as? Bool ?? false
                return Member(id: id, name: name, isOwner: isOwner)
            }
            completion(members)
        }
    }
    // Загрузить splits для расхода
    func fetchSplits(tripId: String, expenseId: String, completion: @escaping ([Split]) -> Void) {
        db.collection("trips").document(tripId).collection("expenses").document(expenseId).collection("splits").getDocuments { snap, err in
            guard let docs = snap?.documents else { completion([]); return }
            let splits = docs.compactMap { doc -> Split? in
                let d = doc.data()
                guard let memberIdStr = d["memberId"] as? String,
                      let memberId = UUID(uuidString: memberIdStr),
                      let share = d["share"] as? Double else { return nil }
                return Split(memberId: memberId, share: Decimal(share))
            }
            completion(splits)
        }
    }
    // Переписанный listenExpenses
    func listenExpenses(for tripId: String, onUpdate: @escaping ([Expense]) -> Void) {
        fetchMembers(tripId: tripId) { [weak self] members in
            guard let self = self else { return }
            self.db.collection("trips").document(tripId).collection("expenses")
                .addSnapshotListener { snap, err in
                    guard let docs = snap?.documents else { onUpdate([]); return }
                    var expenses: [Expense] = []
                    let group = DispatchGroup()
                    for doc in docs {
                        group.enter()
                        let d = doc.data()
                        guard let idString = d["id"] as? String,
                              let id = UUID(uuidString: idString),
                              let title = d["title"] as? String,
                              let amount = d["amount"] as? Double,
                              let paidByIdStr = d["paidBy"] as? String,
                              let paidById = UUID(uuidString: paidByIdStr),
                              let date = d["date"] as? TimeInterval else { group.leave(); continue }
                        self.fetchSplits(tripId: tripId, expenseId: doc.documentID) { splits in
                            let expense = Expense(
                                id: id,
                                title: title,
                                amount: Decimal(amount),
                                paidById: paidById,
                                splits: splits,
                                date: Date(timeIntervalSince1970: date)
                            )
                            expenses.append(expense)
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        onUpdate(expenses)
                    }
                }
        }
    }

    // Добавить расход
    func addExpense(_ expense: Expense, to tripId: String, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
            "paidBy": expense.paidById.uuidString, // исправлено
            "date": expense.date.timeIntervalSince1970
        ]
        db.collection("trips").document(tripId).collection("expenses").document(expense.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Обновить расход
    func updateExpense(_ expense: Expense, in tripId: String, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
            "paidBy": expense.paidById.uuidString, // исправлено
            "date": expense.date.timeIntervalSince1970
        ]
        db.collection("trips").document(tripId).collection("expenses").document(expense.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Удалить расход
    func deleteExpense(_ expense: Expense, from tripId: String, completion: ((Bool) -> Void)? = nil) {
        guard let id = expense.id.uuidString as String? else { completion?(false); return }
        db.collection("trips").document(tripId).collection("expenses").document(id).delete { err in
            completion?(err == nil)
        }
    }

    // MARK: - Firestore Mapping
    static func tripFromFirestore(doc: QueryDocumentSnapshot) -> Trip? {
        let d = doc.data()
        guard let name = d["name"] as? String,
              let currency = d["currency"] as? String,
              let created = d["created"] as? TimeInterval,
              let closed = d["closed"] as? Bool,
              let ownerUid = d["ownerUid"] as? String else { return nil }
        // id может быть сохранён полем или берём documentID
        let id: UUID = {
            if let idStr = d["id"] as? String, let uuid = UUID(uuidString: idStr) {
                return uuid
            } else if let uuid = UUID(uuidString: doc.documentID) {
                return uuid
            } else {
                return UUID()
            }
        }()
        return Trip(
            id: id,
            name: name,
            currency: currency,
            created: Date(timeIntervalSince1970: created),
            members: [],
            expenses: [],
            closed: closed,
            ownerUid: ownerUid
        )
    }
    // Обновить expenseFromFirestore для новых моделей (используется только для batch-загрузки, если нужно)
    static func expenseFromFirestore(doc: QueryDocumentSnapshot, members: [Member], splits: [Split]) -> Expense? {
        let d = doc.data()
        guard let idString = d["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = d["title"] as? String,
              let amount = d["amount"] as? Double,
              let paidByRaw = d["paidBy"],
              let date = d["date"] as? TimeInterval
        else { return nil }
        // Fallback: paidBy может быть строкой-именем (legacy) или UUID
        let paidById: UUID? = {
            if let paidByIdStr = paidByRaw as? String, let uuid = UUID(uuidString: paidByIdStr) {
                return uuid
            } else if let paidByName = paidByRaw as? String {
                return members.first(where: { $0.name == paidByName })?.id
            } else {
                return nil
            }
        }()
        guard let paidByIdUnwrapped = paidById else { return nil }
        // Fallback для splits: если memberId строка-имя, ищем id по имени
        let fixedSplits: [Split] = splits.map { split in
            if let memberId = split.memberId as UUID? {
                return split
            } else if let memberName = split.memberId as? String, let member = members.first(where: { $0.name == memberName }) {
                return Split(memberId: member.id, share: split.share)
            } else {
                return split // не удалось преобразовать, оставляем как есть
            }
        }
        return Expense(
            id: id,
            title: title,
            amount: Decimal(amount),
            paidById: paidByIdUnwrapped,
            splits: fixedSplits,
            date: Date(timeIntervalSince1970: date)
        )
    }
} 