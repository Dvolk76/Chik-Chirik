import Foundation
import Combine

class TripListViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    let tripService = TripFirestoreService()
    let syncService = SyncService()
    private var cancellables = Set<AnyCancellable>()
    
    init(authVM: AuthViewModel) {
        syncService.syncFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        authVM.$linkedOwnerUid
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak authVM] newOwnerUid in
                guard let self = self, let authVM = authVM else { return }
                let ownerUid = newOwnerUid ?? authVM.user?.uid
                if let ownerUid = ownerUid {
                    self.subscribeTrips(ownerUid: ownerUid)
                }
            }
            .store(in: &cancellables)
    }

    func subscribeTrips(ownerUid: String) {
        print("TripListViewModel.subscribeTrips called with ownerUid:", ownerUid)
        tripService.listenTrips(for: ownerUid)
        tripService.$trips
            .receive(on: DispatchQueue.main)
            .assign(to: &$trips)
    }

    func addTrip(_ trip: Trip, completion: (() -> Void)? = nil) {
        tripService.addTrip(trip) { [weak self] _ in
            // Добавить участников в коллекцию members и дождаться завершения
            let memberService = MemberFirestoreService()
            let group = DispatchGroup()
            for member in trip.members {
                group.enter()
                memberService.addMember(member, to: trip.id.uuidString) { _ in
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                // После добавления участников — пересоздать подписку
                self?.subscribeTrips(ownerUid: trip.ownerUid)
                // Синхронизировать локальный trip.members не нужно, данные приходят из Firestore
                completion?()
            }
        }
    }

    func setArchived(_ trip: Trip, archived: Bool) {
        var updated = trip
        updated.closed = archived
        tripService.updateTrip(updated)
        if archived {
            // локально обновим массив для мгновенного отклика
            if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[idx].closed = true
            }
        } else {
            if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[idx].closed = false
            }
        }
    }
    func deleteTrip(_ trip: Trip) {
        tripService.deleteTrip(trip)
    }

    func setPinned(_ trip: Trip, pinned: Bool) {
        var updated = trip
        updated.pinned = pinned
        tripService.updateTrip(updated)
        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx].pinned = pinned
        }
    }
} 