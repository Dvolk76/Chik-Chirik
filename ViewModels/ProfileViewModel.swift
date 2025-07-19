import Foundation
import Combine

class ProfileViewModel: ObservableObject {
    @Published var login: String? = nil
    private let userService = UserFirestoreService()
    private var cancellables = Set<AnyCancellable>()
    private var uid: String = ""

    func subscribe(uid: String) {
        self.uid = uid
        userService.listenUser(uid: uid) { [weak self] login in
            DispatchQueue.main.async {
                self?.login = login
            }
        }
    }

    func updateLogin(_ login: String) {
        userService.updateUser(uid: uid, login: login)
    }
    func registerLogin(_ login: String) {
        userService.registerLogin(uid: uid, login: login)
    }
} 
