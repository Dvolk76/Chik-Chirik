import Foundation
import Combine

class SyncViewModel: ObservableObject {
    @Published var pendingLinks: [PendingLink] = []
    @Published var linkedDevices: [LinkedDevice] = []
    private let syncService = SyncService()
    private var cancellables = Set<AnyCancellable>()
    private var uid: String = ""
    private var deviceUid: String = ""

    func subscribePendingLinks(for uid: String) {
        self.uid = uid
        syncService.listenPendingLinks(for: uid)
        syncService.$pendingLinks
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingLinks)
    }
    func subscribeLinkedDevices(for deviceUid: String) {
        self.deviceUid = deviceUid
        syncService.listenLinkedDevices(for: deviceUid)
        syncService.$linkedDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$linkedDevices)
    }
    func sendLinkRequest(from requesterUid: String, to targetUid: String) {
        syncService.sendLinkRequest(from: requesterUid, to: targetUid)
    }
    func approvePendingLink(_ link: PendingLink) {
        syncService.approvePendingLink(link)
    }
    func reset() {
        pendingLinks = []
        linkedDevices = []
    }
} 