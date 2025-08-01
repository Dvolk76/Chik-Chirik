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
            "pinned": trip.pinned,
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
            "pinned": trip.pinned,
            "ownerUid": trip.ownerUid
        ]
        db.collection("trips").document(trip.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Удалить поездку
    func deleteTrip(_ trip: Trip, completion: ((Bool) -> Void)? = nil) {
        let id = trip.id.uuidString
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
                    for doc in docs {
                        let d = doc.data()
                        guard let idString = d["id"] as? String,
                              let id = UUID(uuidString: idString),
                              let title = d["title"] as? String,
                              let amount = d["amount"] as? Double,
                              let paidByIdStr = d["paidBy"] as? String,
                              let paidById = UUID(uuidString: paidByIdStr),
                              let date = d["date"] as? TimeInterval else { continue }
                        // Пробуем получить splits из поля
                        var splits: [Split] = []
                        if let splitsArr = d["splits"] as? [[String: Any]] {
                            splits = splitsArr.compactMap { dict in
                                guard let memberIdStr = dict["memberId"] as? String,
                                      let memberId = UUID(uuidString: memberIdStr),
                                      let share = dict["share"] as? Double else { return nil }
                                return Split(memberId: memberId, share: Decimal(share))
                            }
                        } else {
                            // Fallback – старый способ через подколлекцию
                            let group = DispatchGroup()
                            group.enter()
                            self.fetchSplits(tripId: tripId, expenseId: doc.documentID) { fetched in
                                splits = fetched
                                group.leave()
                            }
                            group.wait()
                        }
                        let expense = Expense(
                            id: id,
                            title: title,
                            amount: Decimal(amount),
                            paidById: paidById,
                            splits: splits,
                            date: Date(timeIntervalSince1970: date)
                        )
                        expenses.append(expense)
                    }
                    onUpdate(expenses)
                }
        }
    }

    // Добавить расход
    func addExpense(_ expense: Expense, to tripId: String, completion: ((Bool) -> Void)? = nil) {
        // Подготовка массива splits для встраивания в документ
        let splitsArr: [[String: Any]] = expense.splits.map { split in
            [
                "memberId": split.memberId.uuidString,
                "share": NSDecimalNumber(decimal: split.share).doubleValue
            ]
        }
        let data: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
            "paidBy": expense.paidById.uuidString,
            "date": expense.date.timeIntervalSince1970,
            "splits": splitsArr
        ]
        db.collection("trips").document(tripId).collection("expenses").document(expense.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Обновить расход
    func updateExpense(_ expense: Expense, in tripId: String, completion: ((Bool) -> Void)? = nil) {
        let splitsArr: [[String: Any]] = expense.splits.map { split in
            [
                "memberId": split.memberId.uuidString,
                "share": NSDecimalNumber(decimal: split.share).doubleValue
            ]
        }
        let data: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
            "paidBy": expense.paidById.uuidString,
            "date": expense.date.timeIntervalSince1970,
            "splits": splitsArr
        ]
        db.collection("trips").document(tripId).collection("expenses").document(expense.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Удалить расход
    func deleteExpense(_ expense: Expense, from tripId: String, completion: ((Bool) -> Void)? = nil) {
        let id = expense.id.uuidString
        db.collection("trips").document(tripId).collection("expenses").document(id).delete { err in
            completion?(err == nil)
        }
    }

    // Загрузить одну поездку по id (без слушателя)
    func fetchTrip(by tripId: String, completion: @escaping (Trip?) -> Void) {
        db.collection("trips").document(tripId).getDocument { doc, _ in
            if let doc = doc, doc.exists {
                completion(TripFirestoreService.tripFromDocSnapshot(doc: doc))
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Firestore Mapping
    // Вариант для QueryDocumentSnapshot (используется в слушателях)
    static func tripFromFirestore(doc: QueryDocumentSnapshot) -> Trip? {
        let d = doc.data()
        guard let name = d["name"] as? String,
              let currency = d["currency"] as? String,
              let created = d["created"] as? TimeInterval,
              let closed = d["closed"] as? Bool,
              let ownerUid = d["ownerUid"] as? String else { return nil }
        let pinned = d["pinned"] as? Bool ?? false
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
            pinned: pinned,
            ownerUid: ownerUid
        )
    }

    // Вариант для DocumentSnapshot (одиночный fetch)
    static func tripFromDocSnapshot(doc: DocumentSnapshot) -> Trip? {
        guard let d = doc.data() else { return nil }
        guard let name = d["name"] as? String,
              let currency = d["currency"] as? String,
              let created = d["created"] as? TimeInterval,
              let closed = d["closed"] as? Bool,
              let ownerUid = d["ownerUid"] as? String else { return nil }
        let pinned = d["pinned"] as? Bool ?? false
        let idStr = tripIdFrom(doc: doc)
        let id = UUID(uuidString: idStr) ?? UUID()
        return Trip(id: id, name: name, currency: currency, created: Date(timeIntervalSince1970: created), members: [], expenses: [], closed: closed, pinned: pinned, ownerUid: ownerUid)
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

    private static func tripIdFrom(doc: DocumentSnapshot) -> String {
        if let tripId = doc.data()? ["id"] as? String {
            return tripId
        }
        return doc.documentID
    }
} 