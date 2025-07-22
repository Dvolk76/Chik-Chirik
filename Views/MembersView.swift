import SwiftUI

struct MembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var viewModel: TripDetailViewModel
    @State private var newName = ""
    @State private var newLogin = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Form {
            Section("Участники") {
                ForEach(viewModel.members) { member in
                    HStack {
                        Text(member.name)
                        Spacer()
                        Image(systemName: "circle.fill")
                            .foregroundColor(color(for: member.status))
                            .onTapGesture {
                                alertMessage = description(for: member.status)
                                showAlert = true
                            }
                    }
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
            }
            Section("Добавить участника") {
                VStack(alignment: .leading) {
                    TextField("Имя", text: $newName)
                        .focused($nameFieldFocused)
                    TextField("Логин (опционально)", text: $newLogin)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack {
                        Spacer()
                        Button("Добавить", action: addMember)
                            .disabled(newName.trimmed.isEmpty)
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MemberLoginNotFound"))) { note in
            if let info = note.userInfo, let name = info["name"] as? String {
                alertMessage = "Логин не найден. Участник \(name) будет добавлен без привязки к аккаунту. Позже это можно изменить."
                showAlert = true
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Ошибка"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func addMember() {
        let cleanName = newName.trimmed
        guard !cleanName.isEmpty else { return }
        let cleanLogin = newLogin.trimmed
        viewModel.addMember(name: cleanName, login: cleanLogin.isEmpty ? nil : cleanLogin)
        newName = ""
        newLogin = ""
        nameFieldFocused = true
    }

    // MARK: - Helpers
    private func color(for status: Member.MemberStatus) -> Color {
        switch status {
        case .pending: return .yellow
        case .accepted: return .green
        case .declined: return .red
        case .nolink: return .gray
        case .archived: return .orange
        case .deleted: return .black
        }
    }

    private func description(for status: Member.MemberStatus) -> String {
        switch status {
        case .pending: return "Участник ещё не принял и не отказался от приглашения."
        case .accepted: return "Участник принял приглашение."
        case .declined: return "Участник отклонил приглашение."
        case .nolink: return "Участник не подключён к аккаунту."
        case .archived: return "Участник переместил поездку в архив."
        case .deleted: return "Участник удалил поездку у себя."
        }
    }
}
