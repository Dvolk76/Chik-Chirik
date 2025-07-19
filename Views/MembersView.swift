import SwiftUI

struct MembersView: View {
    @Bindable var trip: Trip
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = TripDetailViewModel()
    @State private var newName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Form {
            Section("Участники") {
                ForEach(viewModel.members) { member in
                    Text(member.name)
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
            }
            Section("Добавить участника") {
                HStack {
                    TextField("Имя", text: $newName)
                        .focused($nameFieldFocused)
                    Button("Добавить", action: addMember)
                        .disabled(newName.trimmed.isEmpty)
                }
            }
        }
        .navigationTitle("Участники")
        .onAppear {
            subscribeMembers()
            nameFieldFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadTripsForLinkedOwner"))) { _ in
            subscribeMembers()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Ошибка"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func subscribeMembers() {
        viewModel.subscribe(tripId: trip.id.uuidString)
    }

    private func addMember() {
        let cleanName = newName.trimmed
        guard !cleanName.isEmpty else { return }
        let member = Member(name: cleanName)
        viewModel.addMember(member)
        newName = ""
        nameFieldFocused = true
    }
}
