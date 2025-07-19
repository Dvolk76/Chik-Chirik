import SwiftUI
import FirebaseFirestore

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var profileVM = ProfileViewModel()
    @StateObject private var syncVM = SyncViewModel()
    @State private var showCopied = false
    @State private var showQR = false
    @State private var showLinkDevice = false
    @State private var linkInput = ""
    @State private var showQRScanner = false
    @State private var linkError: String? = nil
    @State private var linkRequestSent = false
    @State private var infoMessage: String?
    @State private var login = ""
    @State private var isLoading = false
    @State private var loginSet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Заголовок
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

                // UID и QR-код
                VStack(spacing: 16) {
                    Text("Ваш ID для синхронизации")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Ваш идентификатор для синхронизации")
                    HStack(spacing: 8) {
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
                        Button { showQR = true } label: {
                            Image(systemName: "qrcode")
                                .font(.title2)
                        }
                        .accessibilityLabel("Показать QR-код")
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

                // Логин для синхронизации
                if let login = profileVM.login {
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
                            profileVM.registerLogin(login)
                            isLoading = false
                            infoMessage = "Логин успешно сохранён!"
                            loginSet = true
                        }
                        .disabled(isLoading)
                    }
                    .padding(.top, 8)
                } else if loginSet {
                    Text("Логин успешно сохранён! Теперь вы можете использовать его для входа на других устройствах.")
                        .foregroundColor(.green)
                        .font(.subheadline)
                }

                // Синхронизация устройств (pending links)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Запросы на синхронизацию")
                        .font(.headline)
                    HStack {
                        Button("Перезапросить") {
                            if let uid = authVM.user?.uid {
                                syncVM.subscribePendingLinks(for: uid)
                            }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    if syncVM.pendingLinks.isEmpty {
                        Text("Нет новых запросов")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(syncVM.pendingLinks) { req in
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
                                    syncVM.approvePendingLink(req)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .padding(.top, 16)

                // --- СИНХРОНИЗАЦИЯ С РОДИТЕЛЬСКИМ УСТРОЙСТВОМ ---
                if authVM.linkedOwnerUid == nil {
                    VStack(spacing: 12) {
                        Text("Синхронизировать с другим устройством")
                            .font(.headline)
                        TextField("Логин или ID родителя", text: $linkInput)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                        if let err = linkError {
                            Text(err)
                                .foregroundColor(.red)
                        }
                        if linkRequestSent {
                            Text("Запрос отправлен! Подтвердите на родительском устройстве.")
                                .foregroundColor(.green)
                        }
                        Button(isLoading ? "Отправка..." : "Синхронизироваться") {
                            guard !linkInput.isEmpty else {
                                linkError = "Введите логин или ID родителя"
                                return
                            }
                            isLoading = true
                            linkError = nil
                            // resolveAndSendLinkRequest аналогично AuthView
                            let value = linkInput.trimmingCharacters(in: .whitespacesAndNewlines)
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
                                let db = Firestore.firestore()
                                db.collection("users").document(parsed.lowercased()).getDocument { doc, err in
                                    if let data = doc?.data(), let uid = data["uid"] as? String {
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
                        .disabled(isLoading)
                    }
                    .padding(.top, 8)
                } else {
                    VStack(spacing: 8) {
                        Text("Устройство связано с владельцем данных!")
                            .foregroundColor(.green)
                        if let owner = authVM.linkedOwnerUid {
                            Text("ID владельца: \(owner)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Кнопка выхода
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
            .padding(.horizontal, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let uid = authVM.user?.uid {
                profileVM.subscribe(uid: uid)
                syncVM.subscribePendingLinks(for: uid)
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
    @Binding var showQR: Bool
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
                Button { showQR = true } label: {
                    Image(systemName: "qrcode")
                        .font(.title2)
                }
                .accessibilityLabel("Показать QR-код")
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
    @Binding var showQRScanner: Bool
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
                Button(action: { showQRScanner = true }) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2)
                }
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
    @Binding var showQR: Bool
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
                if let img = generateQRCode(from: qrString) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 200, height: 200)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(radius: 8)
                }
                Text("Поделитесь этим кодом для синхронизации на другом устройстве")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Закрыть") { showQR = false }
        }
        .padding(32)
    }
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        if let outputImage = filter.outputImage,
           let cgimg = context.createCGImage(outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: outputImage.extent) {
            return UIImage(cgImage: cgimg)
        }
        return nil
    }
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
