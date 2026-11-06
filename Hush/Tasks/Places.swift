import SwiftUI
import CoreLocation
import UserNotifications

struct SavedPlace: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var symbol: String = "mappin"
    var latitude: Double
    var longitude: Double
}

/// Places you save once (Home, Work, Gym…) from your current location. Coordinates stay on this iPhone;
/// iOS watches for arrival or departure itself and shows the reminder.
@Observable
final class PlaceStore: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceStore()

    var places: [SavedPlace] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(places), forKey: "savedPlaces") } }
    var status: CLAuthorizationStatus = .notDetermined
    var locating = false
    var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pending: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        places = (UserDefaults.standard.data(forKey: "savedPlaces").flatMap { try? JSONDecoder().decode([SavedPlace].self, from: $0) }) ?? []
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = manager.authorizationStatus
    }

    func currentLocation(_ done: @escaping (CLLocationCoordinate2D?) -> Void) {
        pending = done
        lastError = nil
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            locating = true
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        status = m.authorizationStatus
        if pending != nil, status == .authorizedWhenInUse || status == .authorizedAlways {
            locating = true
            m.requestLocation()
        } else if status == .denied || status == .restricted {
            lastError = "Location access is off. Turn it on in iPhone Settings → Apps → Hush → Location."
            pending?(nil); pending = nil
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locating = false
        pending?(locations.last?.coordinate)
        pending = nil
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        locating = false
        lastError = "Couldn't get your location. Try again outside or near a window."
        pending?(nil)
        pending = nil
    }
}

extension Reminders {
    /// Arrive/leave reminders, using a region iOS monitors on-device.
    static func syncLocation(_ task: TaskItem) {
        let id = "task.\(task.id.uuidString).loc"
        cancel(id)
        guard task.locationRemind, !task.isDone, task.deletedAt == nil, task.latitude != 0 || task.longitude != 0 else { return }
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: task.latitude, longitude: task.longitude),
                                      radius: max(task.radius, 100), identifier: id)
        region.notifyOnEntry = task.locationOnArrive
        region.notifyOnExit = !task.locationOnArrive
        let content = UNMutableNotificationContent()
        content.title = hideText ? "Hush" : task.title
        content.body = hideText ? "You have a reminder." : (task.locationOnArrive ? "You're at \(task.locationName)." : "You left \(task.locationName).")
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNLocationNotificationTrigger(region: region, repeats: false))
        Task {
            guard await requestPermission() else { return }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

struct LocationReminderSection: View {
    @Bindable var task: TaskItem
    @State private var store = PlaceStore.shared
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Section {
            Toggle(isOn: $task.locationRemind) { Label("Remind Me at a Place", systemImage: "location") }
            if task.locationRemind {
                Picker("When I", selection: $task.locationOnArrive) {
                    Text("Arrive").tag(true)
                    Text("Leave").tag(false)
                }
                .pickerStyle(.segmented)
                ForEach(store.places) { p in
                    Button {
                        task.locationName = p.name; task.latitude = p.latitude; task.longitude = p.longitude
                    } label: {
                        HStack {
                            Label(p.name, systemImage: p.symbol).foregroundStyle(.primary)
                            Spacer()
                            if task.locationName == p.name && task.latitude == p.latitude { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
                .onDelete { store.places.remove(atOffsets: $0) }
                Button {
                    store.currentLocation { c in
                        guard let c else { return }
                        task.latitude = c.latitude; task.longitude = c.longitude
                        if task.locationName.isEmpty || store.places.contains(where: { $0.name == task.locationName }) { task.locationName = "this place" }
                        newName = ""
                        naming = true
                    }
                } label: {
                    HStack {
                        Label("Use My Current Location", systemImage: "location.fill")
                        if store.locating { Spacer(); ProgressView() }
                    }
                }
                Picker("Distance", selection: $task.radius) {
                    Text("Close (100 m)").tag(100.0)
                    Text("Nearby (150 m)").tag(150.0)
                    Text("Area (500 m)").tag(500.0)
                    Text("Wide (1 km)").tag(1000.0)
                }
                if let e = store.lastError { Text(e).font(.hush(.footnote)).foregroundStyle(.red) }
            }
        } header: {
            Text("Location")
        } footer: {
            if task.locationRemind {
                Text(task.latitude == 0 && task.longitude == 0 ? "Pick a saved place or use where you are now."
                     : "Reminds you when you \(task.locationOnArrive ? "arrive at" : "leave") \(task.locationName). Your location never leaves this iPhone.")
            }
        }
        .onChange(of: task.locationRemind) { _, on in if on { Task { await Reminders.requestPermission() } } }
        .alert("Save This Place?", isPresented: $naming) {
            TextField("Name (e.g. Home, Work, Gym)", text: $newName)
            Button("Save") {
                let name = newName.trimmed
                guard !name.isEmpty else { return }
                task.locationName = name
                let symbol = ["home": "house", "work": "briefcase", "gym": "dumbbell", "school": "graduationcap", "store": "cart"][name.lowercased()] ?? "mappin"
                store.places.append(SavedPlace(name: name, symbol: symbol, latitude: task.latitude, longitude: task.longitude))
            }
            Button("Just This Task", role: .cancel) {}
        }
    }
}
