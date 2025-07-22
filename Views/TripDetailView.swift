import SwiftUI


struct TripDetailView: View {
    @Bindable var trip: Trip
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = TripDetailViewModel()
    @State private var showingAddExpense = false
    @Environment(\.dismiss) var dismiss
    @State private var confirmDelete = false

    var body: some View {
        VStack {
            if let membership = membership, membership.status == .pending {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.open.badge.person.crop")
                            .font(.title2)
                        Text("Приглашение в поездку")
                            .font(.headline)
                    }
                    Text("Посмотрите детали и подтвердите участие")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    HStack(spacing: 20) {
                        Button {
                            acceptInvite()
                        } label: {
                            Label("Принять", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showDeclineAlert = true
                        } label: {
                            Label("Отказать", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor.opacity(0.1))
                )
                .padding(.horizontal)
            }

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
            listenMembership()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadTripsForLinkedOwner"))) { _ in
            subscribeDetail()
        }
        .onReceive(membershipService.$memberships) { list in
            membership = list.first { $0.tripId == trip.id.uuidString }
        }
        .alert("Отклонить приглашение?", isPresented: $showDeclineAlert) {
            Button("Отклонить", role: .destructive) { declineInvite() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы не увидите эту поездку и не сможете её редактировать.")
        }
    }

    // MARK: - Invite handling
    @StateObject private var membershipService = TripMembershipService()
    @State private var membership: TripMembership? = nil
    @State private var showDeclineAlert = false

    private func acceptInvite() {
        guard let membership = membership else { return }
        membershipService.updateStatus(membership, status: .accepted, seen: true)
    }

    private func declineInvite() {
        guard let membership = membership else { return }
        membershipService.updateStatus(membership, status: .declined, seen: true)
    }

    private func listenMembership() {
        guard let uid = authVM.user?.uid else { return }
        membershipService.listenMemberships(for: uid)
    }

    init(trip: Trip) {
        self.trip = trip
        // Call to setup membership listening is done in onAppear
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
