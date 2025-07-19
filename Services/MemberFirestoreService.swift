import Foundation
import FirebaseFirestore
import Combine

class MemberFirestoreService: ObservableObject {
    @Published var members: [Member] = []
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    // Слушать участников поездки
    func listenMembers(for tripId: String) {
        listener?.remove()
        listener = db.collection("trips").document(tripId).collection("members")
            .addSnapshotListener { [weak self] snap, err in
                guard let self = self else { return }
                if let docs = snap?.documents {
                    self.members = docs.compactMap { MemberFirestoreService.memberFromFirestore(doc: $0) }
                }
            }
    }

    // Добавить участника
    func addMember(_ member: Member, to tripId: String, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "id": member.id.uuidString,
            "name": member.name,
            "isOwner": member.isOwner
        ]
        db.collection("trips").document(tripId).collection("members").addDocument(data: data) { err in
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
        guard let name = d["name"] as? String,
              let idString = d["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        let isOwner = d["isOwner"] as? Bool ?? false
        return Member(id: id, name: name, isOwner: isOwner)
    }
} 