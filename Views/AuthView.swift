import SwiftUI
import FirebaseFirestore
import AVFoundation

struct AuthView: View {
    @ObservedObject var authVM: AuthViewModel
    @State private var showRegister = false
    @State private var showLogin = false
    @State private var showLinkDevice = false
    @State private var isLoading = false
    @State private var infoMessage: String?
    @State private var linkInput = ""
    @State private var linkRequestSent = false
    @State private var linkError: String? = nil
    @State private var showQRScanner = false
    @State private var showSyncSuccess = false
    @State private var syncBannerOpacity = 0.0
    @State private var showLoading = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.questionmark")
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
                if !showRegister && !showLogin && !showLinkDevice {
                    if showLoading {
                        ProgressView("Создаём гостевой профиль...")
                            .padding()
                    }
                    Button(action: {
                        if let user = authVM.user, user.isAnonymous {
                            // Уже анонимный — просто переход
                            authVM.screenState = .trips
                        } else {
                            showLoading = true
                            let start = Date()
                            authVM.ensureAnonymousUser()
                            // Следим за появлением user
                            func check() {
                                if authVM.user != nil {
                                    let elapsed = Date().timeIntervalSince(start)
                                    let delay = max(1.0 - elapsed, 0)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                        showLoading = false
                                        authVM.screenState = .trips
                                    }
                                } else {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
                                }
                            }
                            check()
                        }
                    }) {
                        Text("Войти анонимно")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(showLoading)
                    Button("Синхронизировать с другим устройством") {
                        if authVM.user == nil {
                            authVM.ensureAnonymousUser()
                        }
                        authVM.screenState = .sync
                    }
                    .padding(.top, 8)
                    .disabled(showLoading)
                    if let error = authVM.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
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
                Text("Ваши данные будут синхронизированы между устройствами по уникальному ID, логину или QR-коду. Для доступа с другого устройства требуется подтверждение на основном устройстве.")
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
            let db = Firestore.firestore()
            // Удалить блок, связанный с логином и паролем
        }
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
