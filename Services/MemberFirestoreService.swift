import Foundation
import FirebaseFirestore
import Combine

class MemberFirestoreService: ObservableObject {
    @Published var members: [Member] = []
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    // Слушать участников поездки
    func listenMembers(for tripId: String) {
        print("MemberFirestoreService.listenMembers for tripId: \(tripId)")
        listener?.remove()
        listener = db.collection("trips").document(tripId).collection("members")
            .addSnapshotListener { [weak self] snap, err in
                print("MemberFirestoreService: snapshot for tripId: \(tripId), docs: \(snap?.documents.count ?? 0)")
                guard let self = self else { return }
                if let docs = snap?.documents {
                    self.members = docs.compactMap { MemberFirestoreService.memberFromFirestore(doc: $0) }
                    print("MemberFirestoreService: parsed members: \(self.members.map { $0.name })")
                }
            }
    }

    // Добавить участника
    func addMember(_ member: Member, to tripId: String, completion: ((Bool) -> Void)? = nil) {
        print("MemberFirestoreService.addMember: \(member.name) to tripId: \(tripId)")
        let data: [String: Any] = [
            "id": member.id.uuidString,
            "name": member.name,
            "isOwner": member.isOwner
        ]
        db.collection("trips").document(tripId).collection("members").document(member.id.uuidString).setData(data) { err in
            print("MemberFirestoreService.addMember: setData finished for \(member.name), error: \(err?.localizedDescription ?? "nil")")
            completion?(err == nil)
        }
    }

    // Обновить участника
    func updateMember(_ member: Member, in tripId: String, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": member.id.uuidString,
            "name": member.name,
            "isOwner": member.isOwner
        ]
        db.collection("trips").document(tripId).collection("members").document(member.id.uuidString).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Удалить участника
    func deleteMember(_ member: Member, from tripId: String, completion: ((Bool) -> Void)? = nil) {
        guard let id = member.id.uuidString as String? else { completion?(false); return }
        db.collection("trips").document(tripId).collection("members").document(id).delete { err in
            completion?(err == nil)
        }
    }

    // MARK: - Firestore Mapping
    static func memberFromFirestore(doc: QueryDocumentSnapshot) -> Member? {
        let d = doc.data()
        print("memberFromFirestore: doc = \(d)")
        guard let name = d["name"] as? String,
              let idString = d["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        let isOwner = d["isOwner"] as? Bool ?? false
        return Member(id: id, name: name, isOwner: isOwner)
    }
} 