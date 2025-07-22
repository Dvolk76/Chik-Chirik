import SwiftUI
import FirebaseFirestore
import AVFoundation

struct AuthView: View {
    @ObservedObject var authVM: AuthViewModel
    enum FlowState { case initial, createLogin, enterLogin, waiting }
    @State private var flow: FlowState = .initial
    @State private var showLinkDevice = false // sync flow kept for future
    @State private var isLoading = false
    @State private var infoMessage: String?
    @State private var linkInput = ""
    @State private var linkRequestSent = false
    @State private var linkError: String? = nil
    @State private var showQRScanner = false
    @State private var showSyncSuccess = false
    @State private var syncBannerOpacity = 0.0
    @State private var showLoading = false
    @State private var showInfoPopover = false
    @State private var loginInput = ""
    
    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: (authVM.user != nil && !(authVM.user?.isAnonymous ?? true)) ? "person.crop.circle" : "person.crop.circle.badge.questionmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 8)
                Text("Chick-Chirik")
                    .font(.largeTitle).fontWeight(.bold)
                    .padding(.bottom, 2)
                Text("Быстрый учёт расходов в поездках — без регистрации!")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                switch flow {
                case .initial:
                    initialButtons
                case .createLogin:
                    createLoginSection
                case .enterLogin:
                    enterLoginSection
                case .waiting:
                    waitingSection
                }
                if authVM.screenState == .sync {
                    VStack(spacing: 12) {
                        Text("Введите ID, логин или отсканируйте QR-код основного устройства")
                            .font(.headline)
                        if let user = authVM.user {
                            HStack(spacing: 8) {
                                Text(user.uid)
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
                                Button {
                                    UIPasteboard.general.string = user.uid
                                    infoMessage = "ID скопирован!"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        infoMessage = nil
                                    }
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.title2)
                                }
                            }
                        }
                        HStack {
                            TextField("ID, логин или QR-код", text: $linkInput)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { showQRScanner = true }) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                            }
                            .sheet(isPresented: $showQRScanner) {
                                QRCodeScannerView { result in
                                    showQRScanner = false
                                    if let code = result {
                                        linkInput = code
                                    }
                                }
                            }
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
                        Button("Назад") { authVM.screenState = .auth; linkInput = ""; linkRequestSent = false; linkError = nil }
                            .padding(.top, 4)
                        if let info = infoMessage {
                            Text(info)
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal)
                }
                if let user = authVM.user, user.isAnonymous {
                    // Кнопка регистрации логина теперь только в профиле
                }
                Spacer()
                Text("Уникальный логин — без персональных данных. Это ваш ключ к синхронизации поездок между устройствами.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // --- Баннер синхронизации ---
            if showSyncSuccess {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Синхронизация завершена!")
                                .font(.title3).bold()
                            Text("Ваши данные теперь доступны на этом устройстве.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(BlurView(style: .systemMaterial))
                    .cornerRadius(18)
                    .padding(.horizontal, 24)
                    .opacity(syncBannerOpacity)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.5), value: syncBannerOpacity)
            }
        }
        .onChange(of: authVM.linkedOwnerUid) { oldValue, newValue in
            print("onChange linkedOwnerUid: \(String(describing: oldValue)) -> \(String(describing: newValue))")
            if newValue != nil {
                // RootView сам переключит экран на TripListView
                showLinkDevice = false
                linkInput = ""
                linkRequestSent = false
                linkError = nil
            }
        }

        .onAppear {
            print("RENDER: AuthView")
            authVM.ensureAnonymousUser()
        }
    }
    // MARK: - Subviews

    private var initialButtons: some View {
        VStack(spacing: 16) {
            Button {
                flow = .createLogin
            } label: {
                HStack {
                    Spacer()
                    Text("Новый логин")
                        .font(.headline)
                    Image(systemName: "info.circle")
                    Spacer()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .popover(isPresented: $showInfoPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Зачем логин?").font(.title3).bold()
                    Text("Никаких персональных данных — нужен только уникальный логин для синхронизации ваших поездок между устройствами.")
                    Button("Понятно") { showInfoPopover = false }
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .frame(width: 260)
            }

            Button {
                flow = .enterLogin
            } label: {
                HStack {
                    Spacer()
                    Text("Уже есть логин")
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            // Placeholder block (invisible) для резервирования места под форму
            VStack(spacing: 12) {
                TextField("", text: .constant(""))
                    .padding()
                    .frame(height:48)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                Button(" ") {}
                    .buttonStyle(PrimaryButtonStyle())
            }
            .opacity(0)
        }
        .padding(.horizontal)
    }

    // Registration
    private var createLoginSection: some View {
        VStack(spacing: 12) {
            TextField("Придумайте логин", text: $loginInput)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .frame(height:48)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            if let error = authVM.errorMessage {
                Text(error).foregroundColor(.red)
            }
            Button(isLoading ? "Проверка…" : "Создать логин") {
                guard !loginInput.isEmpty else { authVM.errorMessage = "Введите логин"; return }
                if authVM.user == nil {
                    authVM.ensureAnonymousUser()
                }
                isLoading = true
                authVM.registerLogin(login: loginInput) { success, msg in
                    isLoading = false
                    if success {
                        authVM.errorMessage = nil
                        authVM.screenState = .trips
                    } else {
                        authVM.errorMessage = msg ?? "Логин уже занят"
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading)

            Button("Назад") { flow = .initial }
                .padding(.top,4)
        }
        .padding(.horizontal)
    }

    // Login existing
    private var enterLoginSection: some View {
        VStack(spacing: 12) {
            TextField("Введите логин владельца", text: $loginInput)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .frame(height:48)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            if let error = authVM.errorMessage { Text(error).foregroundColor(.red) }
            Button(isLoading ? "Запрос…" : "Войти") {
                guard !loginInput.isEmpty else { authVM.errorMessage = "Введите логин"; return }
                isLoading = true
                authVM.loginWithLogin(login: loginInput) { success, msg in
                    if success {
                        flow = .waiting
                        authVM.errorMessage = nil
                    } else {
                        isLoading = false
                        authVM.errorMessage = msg
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading)

            Button("Назад") { flow = .initial }
                .padding(.top,4)
        }
        .padding(.horizontal)
    }

    private var waitingSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .rotationEffect(.degrees(isLoading ? 360 : 0))
                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
            Text("Ожидаем подтверждения на основном устройстве…")
                .multilineTextAlignment(.center)
            Button("Отмена") {
                isLoading = false
                flow = .initial
            }
        }
        .padding()
        .onAppear { isLoading = true }
    }
    // --- Логика определения идентификатора и отправки запроса ---
    func resolveAndSendLinkRequest(_ input: String) {
        // Если это QR-код, парсим его
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: String
        if value.hasPrefix("chickchirik:uid:") {
            parsed = String(value.dropFirst("chickchirik:uid:".count))
        } else if value.hasPrefix("chickchirik:login:") {
            parsed = String(value.dropFirst("chickchirik:login:".count))
        } else {
            parsed = value
        }
        // Если это UID (длина 28, только буквы/цифры), используем напрямую
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
            // Иначе считаем, что это логин — ищем UID по логину
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
}

// --- QR-код сканер (минимальный MVP) ---
struct QRCodeScannerView: UIViewControllerRepresentable {
    var completion: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = ScannerController()
        controller.completion = completion
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    class Coordinator: NSObject, ScannerControllerDelegate {
        let parent: QRCodeScannerView
        init(parent: QRCodeScannerView) { self.parent = parent }
        func didScan(result: String?) { parent.completion(result) }
    }
}
protocol ScannerControllerDelegate: AnyObject { func didScan(result: String?) }
class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerControllerDelegate?
    var completion: ((String?) -> Void)?
    private let session = AVCaptureSession()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            completion?(nil); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.startRunning()
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let str = obj.stringValue {
            session.stopRunning()
            completion?(str)
            delegate?.didScan(result: str)
            dismiss(animated: true)
        }
    }
}

// --- BlurView для баннера ---
import UIKit
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterial
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
} 

// --- Добавить функцию reloadTripsForLinkedOwner ---
func reloadTripsForLinkedOwner() {
    // Можно реализовать через NotificationCenter, Combine, или напрямую вызвать обновление данных
    // Например, отправить Notification:
    NotificationCenter.default.post(name: Notification.Name("ReloadTripsForLinkedOwner"), object: nil)
} 
