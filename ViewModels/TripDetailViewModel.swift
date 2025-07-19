import Foundation
import Combine

class TripDetailViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var members: [Member] = []
    private let tripService = TripFirestoreService()
    private let memberService = MemberFirestoreService()
    private var cancellables = Set<AnyCancellable>()
    private var tripId: String = ""

    func subscribe(tripId: String) {
        self.tripId = tripId
        tripService.listenExpenses(for: tripId) { [weak self] expenses in
            DispatchQueue.main.async {
                self?.expenses = expenses
            }
        }
        memberService.listenMembers(for: tripId)
        memberService.$members
            .receive(on: DispatchQueue.main)
            .assign(to: &$members)
    }

    func addExpense(_ expense: Expense) {
        tripService.addExpense(expense, to: tripId)
    }
    func deleteExpense(_ expense: Expense) {
        tripService.deleteExpense(expense, from: tripId)
    }
    func addMember(_ member: Member) {
        memberService.addMember(member, to: tripId)
    }
    func deleteMember(_ member: Member) {
        memberService.deleteMember(member, from: tripId)
    }
} 