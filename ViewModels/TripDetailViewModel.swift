import Foundation
import FirebaseFirestore
import Combine

// MARK: - Trip Membership Model & Service (inlined to ensure compilation)

class TripDetailViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var members: [Member] = []
    private let tripService = TripFirestoreService()
    private let memberService = MemberFirestoreService()
    private let membershipService = TripMembershipService()
    private let userService = UserFirestoreService()
    private let syncService = SyncService()
    private var cancellables = Set<AnyCancellable>()
    private var tripId: String = ""

    init() {
        syncService.syncFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func subscribe(tripId: String) {
        print("TripDetailViewModel.subscribe called for tripId: \(tripId)")
        self.tripId = tripId
        tripService.listenExpenses(for: tripId) { [weak self] expenses in
            DispatchQueue.main.async {
                print("TripDetailViewModel: expenses updated: count = \(expenses.count)")
                self?.expenses = expenses
            }
        }
        memberService.listenMembers(for: tripId)
        let cancellable = memberService.$members
            .receive(on: DispatchQueue.main)
            .sink { [weak self] members in
                print("TripDetailViewModel: members updated: count = \(members.count), names = \(members.map { $0.name })")
                self?.members = members
            }
        cancellables.insert(cancellable)
    }

    func addExpense(_ expense: Expense) {
        tripService.addExpense(expense, to: tripId)
    }

    func updateExpense(_ expense: Expense) {
        tripService.updateExpense(expense, in: tripId)
    }
    func deleteExpense(_ expense: Expense) {
        tripService.deleteExpense(expense, from: tripId)
    }
    // Public API для управления участниками
    func addMember(name: String, login: String?) {
        guard !name.trimmed.isEmpty else { return }
        let cleanLogin = login?.trimmed
        let member = Member(name: name, login: cleanLogin?.isEmpty == true ? nil : cleanLogin, status: nil)
        memberService.addMember(member, to: tripId)
        // Если указан логин, пробуем найти uid и создать инвайт
        if let login = cleanLogin, !login.isEmpty {
            userService.fetchUid(for: login) { [weak self] uid in
                guard let self = self else { return }
                if let uid = uid {
                    // uid найден – создаём приглашение
                    self.membershipService.createInvite(tripId: self.tripId, memberUid: uid, memberId: member.id.uuidString)
                } else {
                    // uid не найден – можно показать алерт через Combine publisher
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("MemberLoginNotFound"), object: nil, userInfo: ["name": name])
                    }
                }
            }
        }
    }
    func deleteMember(_ member: Member) {
        memberService.deleteMember(member, from: tripId)
    }
} 