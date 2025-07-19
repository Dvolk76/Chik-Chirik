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

    // Слушать расходы для поездки
    func listenExpenses(for tripId: String, onUpdate: @escaping ([Expense]) -> Void) {
        expensesListeners[tripId]?.remove()
        expensesListeners[tripId] = db.collection("trips").document(tripId).collection("expenses")
            .addSnapshotListener { snap, err in
                let expenses = snap?.documents.compactMap { TripFirestoreService.expenseFromFirestore(doc: $0) } ?? []
                onUpdate(expenses)
            }
    }

    // Добавить расход
    func addExpense(_ expense: Expense, to tripId: String, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
            "paidBy": expense.paidBy.id.uuidString,
            "date": expense.date.timeIntervalSince1970
        ]
        db.collection("trips").document(tripId).collection("expenses").addDocument(data: data) { err in
            completion?(err == nil)
        }
    }

    // Обновить расход
    func updateExpense(_ expense: Expense, in tripId: String, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
            "paidBy": expense.paidBy.id.uuidString,
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
              let ownerUid = d["ownerUid"] as? String
        else { return nil }
        // Пока без парсинга участников и расходов
        return Trip(
            name: name,
            currency: currency,
            created: Date(timeIntervalSince1970: created),
            members: [],
            expenses: [],
            closed: closed,
            ownerUid: ownerUid
        )
    }
    static func expenseFromFirestore(doc: QueryDocumentSnapshot) -> Expense? {
        let d = doc.data()
        guard let title = d["title"] as? String,
              let amount = d["amount"] as? Double,
              let paidBy = d["paidBy"] as? String,
              let date = d["date"] as? TimeInterval
        else { return nil }
        // paidBy и splits нужно парсить по твоей модели, здесь пример с пустыми значениями
        return Expense(
            title: title,
            amount: Decimal(amount),
            paidBy: Member(name: paidBy),
            splits: [],
            date: Date(timeIntervalSince1970: date)
        )
    }
} 