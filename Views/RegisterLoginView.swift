import SwiftUI

struct RegisterLoginView: View {
    @ObservedObject var authVM: AuthViewModel
    var onClose: () -> Void

    @State private var login = ""
    @State private var error: String? = nil
    @State private var isLoading = false
    @FocusState private var focusField: Field?
    enum Field { case login }

    var body: some View {
        VStack(spacing: 24) {
            Text("Создание логина")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 16) {
                TextField("Логин (латиница, цифры)", text: $login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .focused($focusField, equals: .login)

                // no password
            }

            if let err = error {
                Text(err)
                    .foregroundColor(.red)
            }

            Button(isLoading ? "Создаём..." : "Создать логин") {
                register()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button("Отмена") {
                onClose()
            }
            .padding(.top, 4)
        }
        .padding()
    }

    private func register() {
        guard !login.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Введите логин"; return }
        isLoading = true
        authVM.registerLogin(login: login) { success, errMsg in
            isLoading = false
            if success {
                onClose()
            } else {
                error = errMsg ?? "Не удалось создать логин"
            }
        }
    }
} 