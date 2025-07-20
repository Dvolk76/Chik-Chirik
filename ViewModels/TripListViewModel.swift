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

    func addTrip(_ trip: Trip) {
        tripService.addTrip(trip) { [weak self] _ in
            // После добавления — пересоздать подписку
            self?.subscribeTrips(ownerUid: trip.ownerUid)
        }
    }

    func deleteTrip(_ trip: Trip) {
        tripService.deleteTrip(trip)
    }
} 