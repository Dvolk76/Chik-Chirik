import SwiftUI
import Combine

class NewTripMember: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    init(name: String) { self.name = name }
}

class TripCreationViewModel: ObservableObject {
    @Published var tripName: String = ""
    @Published var currency: String = "RUB"
    @Published var members: [NewTripMember] = [NewTripMember(name: "")]
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
        members.append(NewTripMember(name: ""))
        observeMembers()
    }

    func removeMember(at offsets: IndexSet) {
        members.remove(atOffsets: offsets)
        observeMembers()
    }

    func reset() {
        tripName = ""
        currency = "RUB"
        members = [NewTripMember(name: "")]
        observeMembers()
    }
}

struct TripListView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var viewModel = TripListViewModel()
    @State private var isSheetPresented = false
    @State private var showProfileSheet = false
    @StateObject private var creationVM = TripCreationViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.trips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip).environmentObject(authVM)) {
                        Text(trip.name)
                    }
                }
            }
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
                                ForEach($creationVM.members) { $member in
                                    TextField("Имя участника", text: $member.name)
                                        .accessibilityIdentifier("memberField_\(member.id)")
                                        .accessibilityLabel(Text("Имя участника"))
                                        .accessibilityHint(Text("Введите имя участника поездки"))
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
                                guard creationVM.canCreateTrip, let ownerUid = authVM.linkedOwnerUid ?? authVM.user?.uid else { return }
                                let memberModels = creationVM.members.map { Member(name: $0.name) }
                                let trip = Trip(name: creationVM.tripName, currency: creationVM.currency, members: memberModels, ownerUid: ownerUid)
                                viewModel.addTrip(trip)
                                isSheetPresented = false
                                creationVM.reset()
                            }
                            .disabled(!creationVM.canCreateTrip)
                            .accessibilityIdentifier("createTripButton")
                            .accessibilityLabel(Text("Создать поездку"))
                            .accessibilityHint(Text("Сохранить новую поездку со всеми участниками"))
                        }
                    }
                }
            }
        }
        .onAppear {
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
}

extension String {
    var trim: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
