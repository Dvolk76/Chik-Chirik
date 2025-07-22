import Foundation
import FirebaseFirestore

struct TripMembership: Identifiable, Hashable {
    enum Status: String {
        case pending
        case accepted
        case declined
    }

    var id: String // Firestore document ID
    var tripId: String
    var memberUid: String
    var status: Status
    var seen: Bool

    static func from(doc: QueryDocumentSnapshot) -> TripMembership? {
        let d = doc.data()
        guard let tripId = d["tripId"] as? String,
              let memberUid = d["memberUid"] as? String,
              let statusRaw = d["status"] as? String,
              let status = Status(rawValue: statusRaw) else { return nil }
        let seen = d["seen"] as? Bool ?? false
        return TripMembership(id: doc.documentID, tripId: tripId, memberUid: memberUid, status: status, seen: seen)
    }

    func toFirestoreData() -> [String: Any] {
        [
            "tripId": tripId,
            "memberUid": memberUid,
            "status": status.rawValue,
            "seen": seen
        ]
    }
} 