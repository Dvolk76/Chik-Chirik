import SwiftUI
import FirebaseFirestore

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var profileVM = ProfileViewModel()
    @StateObject private var syncVM = SyncViewModel()

    // MARK: - Local UI State
    @State private var showCopied = false
    // QR-код временно убран
    @State private var linkInput = ""
    @State private var linkError: String?
    @State private var linkRequestSent = false
    @State private var loginInput = ""
    @State private var infoMessage: String?
    @State private var isLoading = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                profileHeader
                idSection
                loginSection
                syncRequestsSection
                if authVM.linkedOwnerUid == nil {
                    linkDeviceSection
                } else {
                    linkedInfoSection
                }
                signOutSection
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            // QR-код отключён
            .overlay(alignment: .top) {
                if showCopied {
                    Text("ID скопирован!")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        .shadow(radius: 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .onAppear {
                if let uid = authVM.user?.uid {
                    profileVM.subscribe(uid: uid)
                    syncVM.subscribePendingLinks(for: uid)
                }
            }
            .onChange(of: authVM.linkedOwnerUid) { old, new in
                if old == nil && new != nil { dismiss() }
            }
        }
    }

    // MARK: - Sections
    private var profileHeader: some View {
        HStack {
            Spacer()
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 72, height: 72)
                .foregroundColor(.accentColor)
                .padding(.vertical, 8)
            Spacer()
        }
        .listRowInsets(EdgeInsets())
        .background(Color.clear)
    }

    private var idSection: some View {
        Section(header: Text("ID для синхронизации")) {
            HStack {
                Text(authVM.user?.uid ?? "—")
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button { copyUid() } label: { Image(systemName: "doc.on.doc") }
            }
            // Возвращаем только строку без текстового сообщения, чтобы layout не прыгал
        }
    }

    private var loginSection: some View {
        Section(header: Text("Логин для синхронизации")) {
            if let login = authVM.ownerLogin ?? profileVM.login {
                Text(login).font(.system(.footnote, design: .monospaced))
            } else {
                VStack(spacing: 8) {
                    TextField("Уникальный логин", text: $loginInput)
                        .autocapitalization(.none)
                    if let msg = infoMessage { Text(msg).foregroundColor(.red).font(.caption) }
                    Button(isLoading ? "Сохранение…" : "Сохранить") {
                        guard !loginInput.isEmpty else { infoMessage = "Введите логин"; return }
                        isLoading = true
                        profileVM.registerLogin(loginInput)
                        isLoading = false
                    }
                    .disabled(isLoading)
                }
            }
        }
    }

    private var syncRequestsSection: some View {
        Section(header: Text("Запросы на синхронизацию")) {
            if authVM.pendingLinks.isEmpty {
                Text("Нет новых запросов").foregroundColor(.secondary)
            } else {
                ForEach(authVM.pendingLinks) { req in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Новое устройство")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(req.requesterUid).font(.system(.footnote, design: .monospaced))
                        }
                        Spacer()
                        Button("Разрешить") { authVM.approvePendingLink(req) {_,_ in} }
                    }
                }
            }
        }
    }

    private var linkDeviceSection: some View {
        Section(header: Text("Синхронизировать с другим устройством")) {
            VStack(spacing: 8) {
                TextField("ID или логин родительского устройства", text: $linkInput)
                    .autocapitalization(.none)
                if let err = linkError { Text(err).foregroundColor(.red).font(.caption) }
                if linkRequestSent { Text("Запрос отправлен!").foregroundColor(.green).font(.caption) }
                Button(isLoading ? "Отправка…" : "Синхронизироваться") { sendLinkRequest() }
                    .disabled(isLoading)
            }
        }
    }

    private var linkedInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Устройство связано с владельцем данных!").foregroundColor(.green)
                if let owner = authVM.linkedOwnerUid {
                    Text("ID владельца: \(owner)").font(.system(.footnote, design: .monospaced))
                }
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) { authVM.signOut(); syncVM.reset() } label: {
                Text("Выйти из аккаунта").frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Helpers
    private func copyUid() {
        UIPasteboard.general.string = authVM.user?.uid
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        generator.prepare()
        withAnimation { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showCopied = false } }
    }

    // QR sheet и генерация удалены

    private func sendLinkRequest() {
        guard !linkInput.isEmpty else { linkError = "Введите ID или логин"; return }
        isLoading = true
        let value = linkInput.trimmingCharacters(in: .whitespaces)
        authVM.resolveUid(for: value) { uid in
            guard let uid = uid else { linkError = "Пользователь не найден"; isLoading = false; return }
            authVM.sendLinkRequest(to: uid) { success, error in
                isLoading = false
                if success { linkRequestSent = true; linkError = nil } else { linkError = error }
            }
        }
    }
}

// MARK: - UI Components
private struct ProfileHeaderView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
            }
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .accessibilityElement()
            .accessibilityLabel("Аватар пользователя")
            Text("Профиль")
                .font(.title.bold())
                .foregroundColor(.primary)
        }
        .padding(.top, 20)
    }
}

private struct UserIDSectionView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var userLogin: String?
    @Binding var showCopied: Bool
    // QR-код временно убран
    var body: some View {
        VStack(spacing: 8) { // уменьшил вертикальный отступ
            Text("Ваш ID для синхронизации")
                .font(.headline)
                .foregroundColor(.secondary)
                .accessibilityLabel("Ваш идентификатор для синхронизации")
            HStack(spacing: 8) { // уменьшил отступ между элементами
                Text(authVM.user?.uid ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .accessibilityLabel("Ваш уникальный идентификатор")
                    .accessibilityValue(authVM.user?.uid ?? "Неизвестно")
                Button {
                    UIPasteboard.general.string = authVM.user?.uid
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                }
                .accessibilityLabel("Скопировать ID")
                // QR-код отключён
            }
            if showCopied {
                Text("ID скопирован!")
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
                    .accessibilityLabel("Идентификатор скопирован")
            }
        }
        .padding(.top, 12)
    }
}

private struct PendingLinksSectionView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var pendingRequests: [PendingLink]
    @Binding var isLoadingLinks: Bool
    @Binding var approveMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Запросы на синхронизацию")
                .font(.headline)
            HStack {
                Button("Перезапросить") {
                    authVM.listenPendingLinks { links in
                        pendingRequests = links
                        isLoadingLinks = false
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                if isLoadingLinks {
                    ProgressView()
                }
            }
            if pendingRequests.isEmpty && !isLoadingLinks {
                Text("Нет новых запросов")
                    .foregroundColor(.secondary)
            } else {
                ForEach(pendingRequests) { req in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Новое устройство: ")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(req.requesterUid)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Button("Разрешить") {
                            authVM.approvePendingLink(req) { success, error in
                                if success {
                                    approveMessage = "Доступ разрешён! Теперь второе устройство увидит ваши данные."
                                } else {
                                    approveMessage = error ?? "Неизвестная ошибка при подтверждении."
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            if let msg = approveMessage {
                Text(msg)
                    .foregroundColor(.green)
            }
        }
        .padding(.top, 16)
    }
}

private struct UserLoginSectionView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var userLogin: String?
    @Binding var login: String
    @Binding var loginSet: Bool
    @Binding var infoMessage: String?
    @Binding var isLoading: Bool
    var body: some View {
        if let login = userLogin {
            VStack(alignment: .leading, spacing: 8) {
                Text("Логин для синхронизации")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(login)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }
        } else if !loginSet && (authVM.user?.isAnonymous ?? true) {
            VStack(spacing: 12) {
                Text("Добавьте логин для синхронизации между устройствами")
                    .font(.headline)
                TextField("Логин (уникальное имя)", text: $login)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                if let info = infoMessage {
                    Text(info)
                        .foregroundColor(.red)
                }
                Button(isLoading ? "Проверка..." : "Сохранить логин") {
                    guard !login.isEmpty else {
                        infoMessage = "Заполните поле логина"
                        return
                    }
                    isLoading = true
                    authVM.registerWithLogin(login: login, password: "nopass") { success, error in
                        isLoading = false
                        if success {
                            infoMessage = "Логин успешно сохранён!"
                            loginSet = true
                            userLogin = login
                            self.login = ""
                        } else {
                            infoMessage = error
                        }
                    }
                }
                .disabled(isLoading)
            }
            .padding(.top, 8)
        } else if loginSet {
            Text("Логин успешно сохранён! Теперь вы можете использовать его для входа на других устройствах.")
                .foregroundColor(.green)
                .font(.subheadline)
        }
    }
}

private struct SignOutButton: View {
    @ObservedObject var authVM: AuthViewModel
    var body: some View {
        Button(action: {
            authVM.signOut()
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Выйти из аккаунта")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red)
            )
            .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Выйти из аккаунта")
    }
}

private struct SyncDeviceButton: View {
    @Binding var showLinkDevice: Bool
    var body: some View {
        Button(action: { showLinkDevice = true }) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Синхронизировать с другим устройством")
            }
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
        .accessibilityLabel("Синхронизировать с другим устройством")
    }
}

private struct LinkDeviceSectionView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var linkInput: String
    // QR-код отключён
    @Binding var linkError: String?
    @Binding var linkRequestSent: Bool
    @Binding var isLoading: Bool
    @Binding var showLinkDevice: Bool
    var body: some View {
        VStack(spacing: 12) {
            Text("Введите ID, логин или отсканируйте QR-код основного устройства")
                .font(.headline)
            HStack {
                TextField("ID, логин или QR-код", text: $linkInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                // QRCodeScannerView должен быть реализован отдельно
            }
            if let err = linkError {
                Text(err)
                    .foregroundColor(.red)
            }
            if linkRequestSent {
                Text("Запрос отправлен! Подтвердите на основном устройстве.")
                    .foregroundColor(.green)
            }
            Button(isLoading ? "Отправка..." : "Отправить запрос") {
                guard !linkInput.isEmpty else {
                    linkError = "Введите идентификатор или отсканируйте QR-код"
                    return
                }
                isLoading = true
                linkError = nil
                resolveAndSendLinkRequest(linkInput)
            }
            .disabled(isLoading)
            .padding(.top, 8)
            Button("Назад") { showLinkDevice = false; linkInput = ""; linkRequestSent = false; linkError = nil }
                .padding(.top, 4)
        }
        .padding(.horizontal)
    }
    private func resolveAndSendLinkRequest(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: String
        if value.hasPrefix("chickchirik:uid:") {
            parsed = String(value.dropFirst("chickchirik:uid:".count))
        } else if value.hasPrefix("chickchirik:login:") {
            parsed = String(value.dropFirst("chickchirik:login:".count))
        } else {
            parsed = value
        }
        if parsed.count == 28 && parsed.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil {
            authVM.sendLinkRequest(to: parsed) { success, error in
                isLoading = false
                if success {
                    linkRequestSent = true
                    linkError = nil
                } else {
                    linkError = error ?? "Ошибка отправки запроса"
                }
            }
        } else {
            authVM.fetchUid(for: parsed) { uid in
                if let uid = uid {
                    authVM.sendLinkRequest(to: uid) { success, error in
                        isLoading = false
                        if success {
                            linkRequestSent = true
                            linkError = nil
                        } else {
                            linkError = error ?? "Ошибка отправки запроса"
                        }
                    }
                } else {
                    isLoading = false
                    linkError = "Пользователь не найден"
                }
            }
        }
    }
}

private struct NotAuthorizedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Вы не авторизованы")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Войдите в аккаунт, чтобы увидеть информацию профиля")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }
}

private struct QRSheetView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var userLogin: String?
    // QR-код отключён
    var body: some View {
        VStack(spacing: 24) {
            Text("QR-код для синхронизации")
                .font(.headline)
            if let uid = authVM.user?.uid {
                let qrString: String = {
                    if let login = userLogin, !login.isEmpty {
                        return "chickchirik:login:\(login)"
                    } else {
                        return "chickchirik:uid:\(uid)"
                    }
                }()
                // QR-код отключён
            }
            Button("Закрыть") { /* showQR = false */ }
        }
        .padding(32)
    }
    // QR sheet и генерация удалены
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

// Удаляю определение struct PendingLink из этого файла, использую только из AuthViewModel.swift

#Preview {
    ProfileView().environmentObject(AuthViewModel())
}
