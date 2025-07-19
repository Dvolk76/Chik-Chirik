import Foundation
import FirebaseFirestore
import Combine

class SyncService: ObservableObject {
    @Published var pendingLinks: [PendingLink] = []
    @Published var linkedDevices: [LinkedDevice] = []
    private var pendingLinksListener: ListenerRegistration?
    private var linkedDevicesListener: ListenerRegistration?
    private let db = Firestore.firestore()

    // Слушать pending links для пользователя
    func listenPendingLinks(for uid: String) {
        pendingLinksListener?.remove()
        pendingLinksListener = db.collection("pending_links").whereField("targetUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                if let docs = snap?.documents {
                    self.pendingLinks = docs.compactMap { PendingLink.from(doc: $0) }
                }
            }
    }

    // Отправить запрос на синхронизацию
    func sendLinkRequest(from requesterUid: String, to targetUid: String, completion: ((Bool) -> Void)? = nil) {
        let requestId = UUID().uuidString
        let data: [String: Any] = [
            "targetUid": targetUid,
            "requestId": requestId,
            "requesterUid": requesterUid,
            "timestamp": Date().timeIntervalSince1970
        ]
        db.collection("pending_links").document(requestId).setData(data) { err in
            completion?(err == nil)
        }
    }

    // Подтвердить запрос на синхронизацию
    func approvePendingLink(_ link: PendingLink, completion: ((Bool) -> Void)? = nil) {
        let data: [String: Any] = [
            "ownerUid": link.targetUid,
            "deviceUid": link.requesterUid,
            "timestamp": Date().timeIntervalSince1970
        ]
        db.collection("linked_devices").addDocument(data: data) { err in
            if err != nil {
                completion?(false)
            } else {
                self.db.collection("pending_links").document(link.requestId).delete()
                completion?(true)
            }
        }
    }

    // Слушать linked devices для устройства
    func listenLinkedDevices(for deviceUid: String) {
        linkedDevicesListener?.remove()
        linkedDevicesListener = db.collection("linked_devices").whereField("deviceUid", isEqualTo: deviceUid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                if let docs = snap?.documents {
                    self.linkedDevices = docs.compactMap { LinkedDevice.from(doc: $0) }
                }
            }
    }
} 
