import Foundation
import FirebaseFirestore
import Combine

class UserFirestoreService: ObservableObject {
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // Слушать профиль пользователя
    func listenUser(uid: String, onUpdate: @escaping (String?) -> Void) {
        listener?.remove()
        db.collection("users").whereField("uid", isEqualTo: uid)
            .addSnapshotListener { snap, _ in
                if let doc = snap?.documents.first {
                    let login = doc.data()["login"] as? String
                    onUpdate(login)
                } else {
                    onUpdate(nil)
                }
            }
    }

    // Обновить профиль пользователя
    func updateUser(uid: String, login: String?, completion: ((Bool) -> Void)? = nil) {
        guard let login = login else { completion?(false); return }
        db.collection("users").document(login.lowercased()).setData([
            "uid": uid,
            "login": login
        ], merge: true) { err in
            completion?(err == nil)
        }
    }

    // Зарегистрировать логин
    func registerLogin(uid: String, login: String, completion: ((Bool) -> Void)? = nil) {
        db.collection("users").document(login.lowercased()).setData([
            "uid": uid,
            "login": login
        ]) { err in
            completion?(err == nil)
        }
    }

    // Получить uid по логину
    func fetchUid(for login: String, completion: @escaping (String?) -> Void) {
        let loginLower = login.lowercased()
        db.collection("users").document(loginLower).getDocument { doc, _ in
            if let uid = doc?.data()? ["uid"] as? String {
                completion(uid)
            } else {
                completion(nil)
            }
        }
    }
} 