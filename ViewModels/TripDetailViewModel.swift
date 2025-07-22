import Foundation
import Combine

class TripDetailViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var members: [Member] = []
    private let tripService = TripFirestoreService()
    private let memberService = MemberFirestoreService()
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
    func deleteExpense(_ expense: Expense) {
        tripService.deleteExpense(expense, from: tripId)
    }
    // Public API для управления участниками
    func addMember(name: String) {
        guard !name.trimmed.isEmpty else { return }
        let member = Member(name: name)
        memberService.addMember(member, to: tripId)
    }
    func deleteMember(_ member: Member) {
        memberService.deleteMember(member, from: tripId)
    }
} 