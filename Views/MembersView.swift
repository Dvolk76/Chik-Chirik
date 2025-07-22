import SwiftUI

struct MembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var viewModel: TripDetailViewModel
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
            nameFieldFocused = false
        }
        .onReceive(viewModel.$members) { members in
            print("MembersView: members updated: count = \(members.count), names = \(members.map { $0.name })")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadTripsForLinkedOwner"))) { _ in
            // No longer needed as viewModel is EnvironmentObject
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Ошибка"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func addMember() {
        let cleanName = newName.trimmed
        guard !cleanName.isEmpty else { return }
        viewModel.addMember(name: cleanName)
        newName = ""
        nameFieldFocused = true
    }
}
