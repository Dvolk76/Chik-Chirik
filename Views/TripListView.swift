import SwiftUI
import Combine

class NewTripMember: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var login: String
    init(name: String = "", login: String = "") {
        self.name = name
        self.login = login
    }
}

class TripCreationViewModel: ObservableObject {
    @Published var tripName: String = ""
    @Published var currency: String = "RUB"
    @Published var members: [NewTripMember] = [NewTripMember()]
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""

    private var cancellables: [AnyCancellable] = []

    init() {
        observeMembers()
    }

    func observeMembers() {
        cancellables = []
        for member in members {
            let c = member.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            cancellables.append(c)
        }
    }

    var canCreateTrip: Bool {
        !tripName.trimmed.isEmpty &&
        !currency.trimmed.isEmpty &&
        members.count > 0 &&
        members.allSatisfy { !$0.name.trimmed.isEmpty }
    }

    func addMember() {
        members.append(NewTripMember())
        observeMembers()
    }

    func removeMember(at offsets: IndexSet) {
        members.remove(atOffsets: offsets)
        observeMembers()
    }

    func reset() {
        tripName = ""
        currency = "RUB"
        members = [NewTripMember()]
        observeMembers()
    }
}

struct TripListView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var viewModel: TripListViewModel
    @State private var isSheetPresented = false
    @State private var showProfileSheet = false
    @StateObject private var creationVM = TripCreationViewModel()

    init(authVM: AuthViewModel? = nil) {
        if let authVM = authVM {
            _viewModel = StateObject(wrappedValue: TripListViewModel(authVM: authVM))
        } else {
            _viewModel = StateObject(wrappedValue: TripListViewModel(authVM: AuthViewModel()))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Sections: pinned, active, archived
                let pinnedTrips = viewModel.trips.filter { !$0.closed && $0.pinned }.sorted { $0.created > $1.created }
                let activeTrips = viewModel.trips.filter { !$0.closed && !$0.pinned }.sorted { $0.created > $1.created }
                let archivedTrips = viewModel.trips.filter { $0.closed }.sorted { $0.created > $1.created }

                // In body: after we compute pinnedTrips etc, also compute invited trips
                let invitedTrips = viewModel.membershipTrips

                if !invitedTrips.isEmpty {
                    Section("Приглашения") {
                        invitedTripRows(for: invitedTrips)
                    }
                }

                if !pinnedTrips.isEmpty {
                    Section("Закреплённые") {
                        tripRows(for: pinnedTrips)
                    }
                }

                if !activeTrips.isEmpty {
                    Section("Поездки") {
                        tripRows(for: activeTrips)
                    }
                }

                if !archivedTrips.isEmpty {
                    Section("Архив") {
                        tripRows(for: archivedTrips)
                    }
                }
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip).environmentObject(authVM)
            }
            .alert("Переместить в архив?", isPresented: $archiveAlertShown, presenting: archivingTrip) { trip in
                Button("Архивировать", role: .destructive) { viewModel.setArchived(trip, archived: true) }
                Button("Отмена", role: .cancel) {}
            } message: { _ in Text("Вы всегда сможете восстановить поездку из архива.") }
            // pin confirmation via secondary tap on swipe button (no alert)
            .navigationTitle("Поездки")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isSheetPresented = true }) {
                        Label("Добавить поездку", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showProfileSheet = true }) {
                        Label("Профиль", systemImage: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView().environmentObject(authVM)
            }
            .sheet(isPresented: $isSheetPresented) {
                NavigationStack {
                    Form {
                        Section("Название поездки") {
                            TextField("Введите имя", text: $creationVM.tripName)
                                .accessibilityIdentifier("tripNameField")
                                .accessibilityLabel(Text("Название поездки"))
                                .accessibilityHint(Text("Введите название новой поездки"))
                        }
                        Section("Валюта") {
                            TextField("Валюта", text: $creationVM.currency)
                                .accessibilityIdentifier("tripCurrencyField")
                                .accessibilityLabel(Text("Валюта поездки"))
                                .accessibilityHint(Text("Введите валюту для этой поездки"))
                        }
                        Section("Участники") {
                            List {
                                ForEach(creationVM.members) { member in
                                    if let nameBinding = bindingForMemberName(withId: member.id),
                                       let loginBinding = bindingForMemberLogin(withId: member.id) {
                                        VStack(alignment: .leading) {
                                            TextField("Имя участника", text: nameBinding)
                                                .accessibilityIdentifier("memberNameField_\(member.id)")
                                                .accessibilityLabel(Text("Имя участника"))
                                                .accessibilityHint(Text("Введите имя участника поездки"))
                                            TextField("Логин (опционально)", text: loginBinding)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled(true)
                                                .accessibilityIdentifier("memberLoginField_\(member.id)")
                                                .accessibilityLabel(Text("Логин участника"))
                                                .accessibilityHint(Text("Введите логин участника"))
                                        }
                                    }
                                }
                                .onDelete { idx in
                                    creationVM.removeMember(at: idx)
                                }
                            }
                            .frame(maxHeight: 250)
                            .accessibilityIdentifier("membersList")
                            Button {
                                creationVM.addMember()
                            } label: {
                                Label("Добавить участника", systemImage: "plus.circle")
                            }
                            .accessibilityIdentifier("addMemberButton")
                            .accessibilityLabel(Text("Добавить участника"))
                            .accessibilityHint(Text("Добавить нового участника в список"))
                        }
                    }
                    .navigationTitle("Новая поездка")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { isSheetPresented = false }
                                .accessibilityIdentifier("cancelButton")
                                .accessibilityLabel(Text("Отмена создания поездки"))
                                .accessibilityHint(Text("Закрыть форму создания поездки без сохранения"))
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Создать") {
                                print("TripListView: creating trip with members = \(creationVM.members.map { "\($0.name) [id: \($0.id)]" })")
                                guard creationVM.canCreateTrip, let ownerUid = authVM.linkedOwnerUid ?? authVM.user?.uid else { return }
                                let memberModels = creationVM.members.map { Member(name: $0.name, login: $0.login.trimmed.isEmpty ? nil : $0.login.trimmed) }
                                let trip = Trip(name: creationVM.tripName, currency: creationVM.currency, members: memberModels, ownerUid: ownerUid)
                                viewModel.addTrip(trip) {
                                    isSheetPresented = false
                                }
                            }
                            .disabled(!creationVM.canCreateTrip)
                            .accessibilityIdentifier("createTripButton")
                            .accessibilityLabel(Text("Создать поездку"))
                            .accessibilityHint(Text("Сохранить новую поездку со всеми участниками"))
                        }
                    }
                }
                .onDisappear {
                    creationVM.reset()
                }
            }
        }
        .onAppear {
            print("RENDER: TripListView")
            // Если viewModel был создан с пустым AuthViewModel, пересоздать с EnvironmentObject
            if viewModel.syncService !== authVM {
                // Необходимо пересоздать viewModel с актуальным authVM
                // Это возможно только через дополнительную логику, например, через .id(authVM.user?.uid)
            }
            subscribeTrips()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadTripsForLinkedOwner"))) { _ in
            print("TripListView: received ReloadTripsForLinkedOwner notification")
            subscribeTrips()
        }
    }
    private func subscribeTrips() {
        if let uid = authVM.linkedOwnerUid ?? authVM.user?.uid {
            viewModel.subscribeTrips(ownerUid: uid)
        }
    }

    // MARK: - Archive helpers
    @State private var archiveAlertShown = false
    @State private var archivingTrip: Trip?
    private func confirmArchive(_ trip: Trip) {
        archivingTrip = trip
        archiveAlertShown = true
    }

    // no pin alert needed; relies on button tap

    // MARK: - Helper to generate rows
    @ViewBuilder private func tripRows(for trips: [Trip]) -> some View {
        ForEach(trips) { trip in
            NavigationLink(destination: TripDetailView(trip: trip).environmentObject(authVM)) {
                HStack {
                    Text(trip.name)
                    if trip.closed {
                        Spacer()
                        Image(systemName: "archivebox")
                            .foregroundColor(.secondary)
                    } else if trip.pinned {
                        Spacer()
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
            // Swipe Actions
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if trip.pinned {
                    Button("Открепить") { viewModel.setPinned(trip, pinned: false) }.tint(.gray)
                } else if !trip.closed {
                    Button("Закрепить") { viewModel.setPinned(trip, pinned: true) }.tint(.orange)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if trip.closed {
                    Button("Восстановить") { viewModel.setArchived(trip, archived: false) }.tint(.blue)
                } else {
                    Button("Архив") { confirmArchive(trip) }.tint(.orange)
                }
            }
        }
    }

    // MARK: - Invited rows
    @ViewBuilder private func invitedTripRows(for trips: [Trip]) -> some View {
        ForEach(trips) { trip in
            NavigationLink(value: trip) {
                HStack {
                    Text(trip.name)
                        .fontWeight(.semibold)
                    Spacer()
                    if viewModel.membership(for: trip)?.status == .pending {
                        Text("NEW")
                            .font(.caption)
                            .padding(6)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @State private var navigationSelection: Trip?
}

extension String {
    var trim: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension TripListView {
    func bindingForMemberName(withId id: UUID) -> Binding<String>? {
        guard let index = creationVM.members.firstIndex(where: { $0.id == id }) else { return nil }
        return $creationVM.members[index].name
    }

    func bindingForMemberLogin(withId id: UUID) -> Binding<String>? {
        guard let index = creationVM.members.firstIndex(where: { $0.id == id }) else { return nil }
        return $creationVM.members[index].login
    }
}
