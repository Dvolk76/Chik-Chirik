import Foundation
import Combine

class TripListViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    private let tripService = TripFirestoreService()
    private var cancellables = Set<AnyCancellable>()

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