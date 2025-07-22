import SwiftUI

struct LoginWithLoginView: View {
    @ObservedObject var authVM: AuthViewModel
    var onClose: () -> Void

    @State private var login = ""
    @State private var error: String? = nil
    @State private var isLoading = false
    @FocusState private var focusField: Field?
    enum Field { case login }

    var body: some View {
        VStack(spacing: 24) {
            Text("Вход по логину")
                .font(.title2).bold()
            VStack(alignment: .leading, spacing: 16) {
                TextField("Логин", text: $login)
                    .textInputAutocapitalization(.none)
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
            Button(isLoading ? "Входим..." : "Войти") {
                loginAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button("Отмена") { onClose() }
                .padding(.top, 4)
        }
        .padding()
    }

    private func loginAction() {
        guard !login.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Введите логин"; return }
        isLoading = true
        authVM.loginWithLogin(login: login) { success, err in
            isLoading = false
            if success {
                onClose()
            } else {
                error = err ?? "Неверный логин или пароль"
            }
        }
    }
} 