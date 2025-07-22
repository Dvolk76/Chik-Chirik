import Foundation
import FirebaseFirestore
import Combine

class TripMembershipService: ObservableObject {
    @Published var memberships: [TripMembership] = []
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    // Listen for memberships for given user
    func listenMemberships(for memberUid: String) {
        listener?.remove()
        listener = db.collection("trip_memberships").whereField("memberUid", isEqualTo: memberUid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                if let docs = snap?.documents {
                    self.memberships = docs.compactMap { TripMembership.from(doc: $0) }
                }
            }
    }

    func createInvite(tripId: String, memberUid: String, memberId: String) {
        let docId = "\(tripId)_\(memberUid)"
        let data: [String: Any] = [
            "tripId": tripId,
            "memberUid": memberUid,
            "status": TripMembership.Status.pending.rawValue,
            "seen": false,
            "memberId": memberId,
            "timestamp": Date().timeIntervalSince1970
        ]
        db.collection("trip_memberships").document(docId).setData(data)
    }

    func updateStatus(_ membership: TripMembership, status: TripMembership.Status, seen: Bool? = nil) {
        var data: [String: Any] = [
            "status": status.rawValue
        ]
        if let seen = seen {
            data["seen"] = seen
        }
        let docRef = db.collection("trip_memberships").document(membership.id)
        docRef.updateData(data)
        // после обновления синхронизируем статус в trip.members
        docRef.getDocument { snap, _ in
            guard let d = snap?.data(),
                  let tripId = d["tripId"] as? String,
                  let memberId = d["memberId"] as? String,
                  let statusRaw = data["status"] as? String else { return }
            let tripDoc = self.db.collection("trips").document(tripId)
            tripDoc.collection("members").document(memberId).updateData(["status": statusRaw])
        }
    }
} 