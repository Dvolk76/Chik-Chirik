import SwiftUI


struct TripDetailView: View {
    @Bindable var trip: Trip
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = TripDetailViewModel()
    @State private var showingAddExpense = false
    @Environment(\.dismiss) var dismiss
    @State private var confirmDelete = false

    var body: some View {
        List {
            // --- СЕКЦИЯ: Переход к участникам ---
            Section {
                NavigationLink("Участники") {
                    MembersView()
                        .environmentObject(authVM)
                        .environmentObject(viewModel)
                }
            }
            // --- СЕКЦИЯ: Список расходов ---
            Section(header: Text("Расходы")) {
                if viewModel.expenses.isEmpty {
                    Text("Пока нет расходов")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.expenses) { expense in
                        NavigationLink {
                            EditExpenseView(expense: expense, trip: trip)
                                .environmentObject(authVM)
                                .environmentObject(viewModel)
                        } label: {
                            ExpenseRow(expense: expense, currency: trip.currency, members: viewModel.members)
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { idx in
                            let expense = viewModel.expenses[idx]
                            viewModel.deleteExpense(expense)
                        }
                    }
                }
            }
            // --- СЕКЦИЯ: Переход к расчету долгов ---
            Section {
                NavigationLink("Посчитать долги") {
                    SettleUpView(trip: trip)
                        .environmentObject(authVM)
                        .environmentObject(viewModel)
                }
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if trip.closed {
                    Menu {
                        Button("Восстановить") { restoreTrip() }
                        Button("Удалить", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    Button(action: { showingAddExpense = true }) {
                        Label("Добавить расход", systemImage: "plus")
                    }
                }
            }
        }
        .alert("Удалить поездку безвозвратно?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { deleteTrip() }
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(trip: trip)
                .environmentObject(authVM)
        }
        .onAppear {
            subscribeDetail()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadTripsForLinkedOwner"))) { _ in
            subscribeDetail()
        }
    }
    private func subscribeDetail() {
        viewModel.subscribe(tripId: trip.id.uuidString)
    }

    private func restoreTrip() {
        let listVM = TripListViewModel(authVM: authVM)
        listVM.setArchived(trip, archived: false)
        dismiss()
    }
    private func deleteTrip() {
        let listVM = TripListViewModel(authVM: authVM)
        listVM.deleteTrip(trip)
        dismiss()
    }
}
