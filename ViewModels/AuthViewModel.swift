import Foundation
import FirebaseAuth
import Combine
import FirebaseFirestore
// CryptoKit no longer needed

class AuthViewModel: ObservableObject {
    enum ScreenState { case auth, sync, trips }
    @Published var screenState: ScreenState = .auth
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var linkedOwnerUid: String? = nil
    @Published var ownerLogin: String? = nil
    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    private var linkedListener: ListenerRegistration?
    private var pendingLinksListener: ListenerRegistration?
    @Published var pendingLinks: [PendingLink] = []

    private var ownerLoginListener: ListenerRegistration?

    init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            self.user = user
            self.listenForLinkedAccount()
            self.subscribeToPendingLinks()
            self.listenOwnerLogin()
        }
    }
    /// Гарантировать, что есть анонимный пользователь (вызывать из AuthView)
    func ensureAnonymousUser() {
        if Auth.auth().currentUser == nil {
            signInAnonymously()
        } else {
            self.user = Auth.auth().currentUser
            self.listenForLinkedAccount()
        }
    }
    deinit {
        if let handle = handle { Auth.auth().removeStateDidChangeListener(handle) }
        linkedListener?.remove()
        pendingLinksListener?.remove()
    }

    func signInAnonymously() {
        Auth.auth().signInAnonymously { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Firebase anonymous signIn error:", error)
                    self.errorMessage = error.localizedDescription
                } else {
                    self.user = result?.user
                }
            }
        }
    }
    
    func signOut() {
        try? Auth.auth().signOut()
        self.user = nil
        self.linkedOwnerUid = nil
        self.screenState = .auth
    }

    // MARK: - New simple login flow (no password)
    func registerLogin(login: String, completion: @escaping (Bool, String?) -> Void) {
        let loginLower = login.lowercased()
        checkLoginUnique(login: loginLower) { [weak self] isUnique in
            guard let self = self else { return }
            if !isUnique {
                completion(false, "Логин уже занят")
                return
            }
            guard let uid = Auth.auth().currentUser?.uid else {
                completion(false, "Пользователь не аутентифицирован")
                return
            }
            self.db.collection("users").document(loginLower).setData([
                "login": loginLower,
                "uid": uid
            ]) { err in
                completion(err == nil, err?.localizedDescription)
            }
        }
    }

    func loginWithLogin(login: String, completion: @escaping (Bool, String?) -> Void) {
        let loginLower = login.lowercased()
        db.collection("users").document(loginLower).getDocument { [weak self] doc, err in
            guard let self = self else { return }
            if let err = err { completion(false, err.localizedDescription); return }
            guard let data = doc?.data(), let uid = data["uid"] as? String else {
                completion(false, "Логин не найден")
                return
            }
            // Если это устройство ещё не анонимно авторизовано, войдём анонимно
            if Auth.auth().currentUser == nil {
                self.ensureAnonymousUser()
            }
            // Запускаем процесс синхронизации аналогично sendLinkRequest
            self.sendLinkRequest(to: uid) { success, msg in
                completion(success, msg)
            }
        }
    }

    func checkLoginUnique(login: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(login.lowercased()).getDocument { doc, _ in
            completion(!(doc?.exists ?? false))
        }
    }

    func sendLinkRequest(to targetUid: String, completion: @escaping (Bool, String?) -> Void) {
        guard let requesterUid = Auth.auth().currentUser?.uid, !requesterUid.isEmpty else {
            completion(false, "Ошибка: пользователь не аутентифицирован. Попробуйте войти или перезапустить приложение.")
            return
        }
        let requestId = UUID().uuidString
        let data: [String: Any] = [
            "targetUid": targetUid,
            "requestId": requestId,
            "requesterUid": requesterUid,
            "timestamp": Date().timeIntervalSince1970
        ]
        db.collection("pending_links").document(requestId).setData(data) { err in
            if let err = err {
                completion(false, "Ошибка Firestore: \(err.localizedDescription)")
            } else {
                completion(true, nil)
            }
        }
    }

    // hashPassword удалён — больше не нужен

    // --- Слушатель linked_devices для второго устройства ---
    func listenForLinkedAccount() {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        linkedListener?.remove()
        linkedListener = db.collection("linked_devices").whereField("deviceUid", isEqualTo: myUid)
            .addSnapshotListener { [weak self] snap, _ in
                print("linked_devices snapshot for deviceUid \(myUid):", snap?.documents.map { $0.data() } ?? [])
                guard let self = self else { return }
                if let doc = snap?.documents.first, let ownerUid = doc.data()["ownerUid"] as? String {
                    if self.linkedOwnerUid != ownerUid {
                        print("linkedOwnerUid updated to:", ownerUid)
                        self.linkedOwnerUid = ownerUid
                        self.screenState = .trips
                        self.subscribeToPendingLinks()
                        self.listenOwnerLogin()
                    }
                }
            }
    }

    func listenPendingLinksForCurrentOwner() {
        pendingLinksListener?.remove()
        let listenUid = linkedOwnerUid ?? user?.uid
        guard let listenUid = listenUid else { return }
        pendingLinksListener = db.collection("pending_links").whereField("targetUid", isEqualTo: listenUid)
            .addSnapshotListener { [weak self] snap, _ in
                let links = snap?.documents.compactMap { PendingLink.from(doc: $0) } ?? []
                self?.pendingLinks = links
            }
    }

    // Вызов подписки при изменении linkedOwnerUid или user
    private func subscribeToPendingLinks() {
        listenPendingLinksForCurrentOwner()
    }

    func listenOwnerLogin() {
        ownerLoginListener?.remove()
        let loginUid = linkedOwnerUid ?? user?.uid
        guard let loginUid = loginUid else { ownerLogin = nil; return }
        db.collection("users").whereField("uid", isEqualTo: loginUid)
            .addSnapshotListener { [weak self] snap, _ in
                if let doc = snap?.documents.first, let login = doc.data()["login"] as? String {
                    self?.ownerLogin = login
                } else {
                    self?.ownerLogin = nil
                }
            }
    }

    // Утилита: определить UID по введённому значению (uid или login)
    func resolveUid(for value: String, completion: @escaping (String?) -> Void) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 28 && trimmed.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil {
            completion(trimmed)
        } else {
            fetchUid(for: trimmed) { uid in
                completion(uid)
            }
        }
    }
}

// Удаляю дублирующее определение PendingLink, оставляю только одно:
struct PendingLink: Identifiable {
    let id: String
    let requestId: String
    let requesterUid: String
    let targetUid: String
    let timestamp: TimeInterval
    static func from(doc: QueryDocumentSnapshot) -> PendingLink? {
        let d = doc.data()
        guard let requesterUid = d["requesterUid"] as? String,
              let targetUid = d["targetUid"] as? String,
              let timestamp = d["timestamp"] as? TimeInterval else { return nil }
        return PendingLink(id: doc.documentID, requestId: doc.documentID, requesterUid: requesterUid, targetUid: targetUid, timestamp: timestamp)
    }
}

struct LinkedDevice: Identifiable {
    let id: String
    let ownerUid: String
    let deviceUid: String
    let timestamp: TimeInterval
    static func from(doc: QueryDocumentSnapshot) -> LinkedDevice? {
        let d = doc.data()
        guard let ownerUid = d["ownerUid"] as? String,
              let deviceUid = d["deviceUid"] as? String,
              let timestamp = d["timestamp"] as? TimeInterval else { return nil }
        return LinkedDevice(id: doc.documentID, ownerUid: ownerUid, deviceUid: deviceUid, timestamp: timestamp)
    }
}

extension AuthViewModel {
    func listenPendingLinks(onUpdate: @escaping ([PendingLink]) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("pending_links").whereField("targetUid", isEqualTo: uid)
            .addSnapshotListener { snap, _ in
                let links = snap?.documents.compactMap { doc -> PendingLink? in
                    return PendingLink.from(doc: doc)
                } ?? []
                onUpdate(links)
            }
    }
    func approvePendingLink(_ link: PendingLink, completion: @escaping (Bool, String?) -> Void) {
        // MVP: просто сохраняем разрешённый uid в коллекцию linked_devices
        let db = Firestore.firestore()
        let data: [String: Any] = [
            "ownerUid": link.targetUid,
            "deviceUid": link.requesterUid,
            "timestamp": Date().timeIntervalSince1970
        ]
        db.collection("linked_devices").addDocument(data: data) { err in
            if let err = err {
                completion(false, "Ошибка: \(err.localizedDescription)")
            } else {
                // Удаляем запрос
                db.collection("pending_links").document(link.requestId).delete()
                completion(true, nil)
            }
        }
    }

    /// Получить логин пользователя по UID
    func fetchUserLogin(for uid: String, completion: @escaping (String?) -> Void) {
        db.collection("users").whereField("uid", isEqualTo: uid).getDocuments { snap, _ in
            if let doc = snap?.documents.first, let l = doc.data()["login"] as? String {
                completion(l)
            } else {
                completion(nil)
            }
        }
    }
    /// Найти UID по логину
    func fetchUid(for login: String, completion: @escaping (String?) -> Void) {
        db.collection("users").document(login.lowercased()).getDocument { doc, _ in
            if let data = doc?.data(), let uid = data["uid"] as? String {
                completion(uid)
            } else {
                completion(nil)
            }
        }
    }
} 
