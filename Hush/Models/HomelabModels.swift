import SwiftUI
import SwiftData

// MARK: - Shared value types

struct ServicePort: Codable, Hashable, Identifiable {
    var id = UUID()
    var port: Int
    var proto: String = "TCP"     // TCP, UDP, TCP/UDP
    var purpose: String = ""
}

struct DiagramNode: Codable, Hashable, Identifiable {
    var id = UUID()
    var deviceID: UUID? = nil
    var label: String
    var symbol: String = "circle"
    var x: Double
    var y: Double
    var colorName: String = "none"
}

struct DiagramEdge: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var label: String = ""
    var style: String = "solid"   // solid, dashed, wireless
}

struct RunbookStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var command: String = ""
    var done: Bool = false
}

struct RunbookRun: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var completed: Int
    var total: Int
    var note: String = ""
}

enum DeviceKind: String, CaseIterable, Identifiable, Codable {
    case router, firewall, switchDevice = "switch", accessPoint, server, nas, hypervisor, vm, container, sbc, desktop, laptop, ups, pdu, modem, camera, iot, other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .router: "Router"
        case .firewall: "Firewall"
        case .switchDevice: "Switch"
        case .accessPoint: "Access Point"
        case .server: "Server"
        case .nas: "NAS"
        case .hypervisor: "Hypervisor"
        case .vm: "Virtual Machine"
        case .container: "Container"
        case .sbc: "Single-Board Computer"
        case .desktop: "Desktop"
        case .laptop: "Laptop"
        case .ups: "UPS"
        case .pdu: "PDU"
        case .modem: "Modem / ONT"
        case .camera: "Camera"
        case .iot: "Smart Device"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .router: "wifi.router"
        case .firewall: "shield.lefthalf.filled"
        case .switchDevice: "rectangle.connected.to.line.below"
        case .accessPoint: "antenna.radiowaves.left.and.right"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .hypervisor: "square.stack.3d.up"
        case .vm: "macwindow"
        case .container: "shippingbox"
        case .sbc: "cpu"
        case .desktop: "desktopcomputer"
        case .laptop: "laptopcomputer"
        case .ups: "battery.100.bolt"
        case .pdu: "powerplug"
        case .modem: "globe"
        case .camera: "video"
        case .iot: "lightbulb"
        case .other: "shippingbox.circle"
        }
    }
    /// Rough order from the internet down, used to lay out auto diagrams.
    var tier: Int {
        switch self {
        case .modem: 0
        case .router, .firewall: 1
        case .switchDevice: 2
        case .accessPoint, .server, .nas, .hypervisor, .ups, .pdu: 3
        case .vm, .container: 4
        default: 4
        }
    }
    var isVirtual: Bool { self == .vm || self == .container }
}

enum DeviceStatus: String, CaseIterable, Identifiable {
    case active, planned, spare, retired
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .active: .green
        case .planned: .blue
        case .spare: .orange
        case .retired: .gray
        }
    }
}

// MARK: - Devices

@Model
final class LabDevice {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = DeviceKind.server.rawValue
    var statusRaw: String = DeviceStatus.active.rawValue
    var hostname: String = ""
    var ip: String = ""
    var mac: String = ""
    var vlan: String = ""
    var os: String = ""
    var cpu: String = ""
    var ram: String = ""
    var storage: String = ""
    var manufacturer: String = ""
    var model: String = ""
    var serial: String = ""
    var location: String = ""
    var rackID: UUID? = nil
    var rackU: Int = 0
    var heightU: Int = 1
    var portCount: Int = 0
    var powerWatts: Double = 0
    var purchaseDate: Date? = nil
    var warrantyUntil: Date? = nil
    var price: Double = 0
    var hostID: UUID? = nil
    var vaultItemID: UUID? = nil
    var notes: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String = "", kind: DeviceKind = .server) {
        self.name = name
        self.kindRaw = kind.rawValue
        spaceID = Spaces.newItemSpace
    }

    var kind: DeviceKind {
        get { DeviceKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
    var status: DeviceStatus {
        get { DeviceStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? (hostname.isEmpty ? kind.label : hostname) : name }
    var warrantyExpiringSoon: Bool {
        guard let w = warrantyUntil else { return false }
        return w > .now && w < Date().addingTimeInterval(90 * 86400)
    }
}

// MARK: - Services

@Model
final class LabService {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "app.connected.to.app.below.fill"
    var hostID: UUID? = nil
    var portsData: Data = Data()
    var url: String = ""
    var image: String = ""
    var version: String = ""
    var dataPath: String = ""
    var config: String = ""
    var backedUp: Bool = false
    var exposedPublicly: Bool = false
    var dependsOnData: Data = Data()
    var vaultItemID: UUID? = nil
    var notes: String = ""
    var tags: [String] = []
    var lastUpdated: Date? = nil
    var createdAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String = "") {
        self.name = name
        spaceID = Spaces.newItemSpace
    }

    var ports: [ServicePort] {
        get { JSONField.decode(portsData, as: [ServicePort].self) ?? [] }
        set { portsData = JSONField.encode(newValue) }
    }
    var dependsOn: [UUID] {
        get { JSONField.decode(dependsOnData, as: [UUID].self) ?? [] }
        set { dependsOnData = JSONField.encode(newValue) }
    }
    var portSummary: String { ports.map { "\($0.port)/\($0.proto.lowercased())" }.joined(separator: ", ") }
}

// MARK: - Subnets / VLANs

@Model
final class LabSubnet {
    var id: UUID = UUID()
    var name: String = ""
    var cidr: String = "192.168.1.0/24"
    var vlanID: Int = 0
    var gateway: String = ""
    var dhcpStart: String = ""
    var dhcpEnd: String = ""
    var dns: String = ""
    var domain: String = ""
    var purpose: String = ""
    var colorName: String = "blue"
    var notes: String = ""
    var createdAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String = "", cidr: String = "192.168.1.0/24") {
        self.name = name
        self.cidr = cidr
        spaceID = Spaces.newItemSpace
    }

    var color: Color { NoteColor(rawValue: colorName)?.color ?? .blue }
}

// MARK: - Racks

@Model
final class LabRack {
    var id: UUID = UUID()
    var name: String = "Rack"
    var units: Int = 12
    var location: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String = "Rack", units: Int = 12) {
        self.name = name
        self.units = units
        spaceID = Spaces.newItemSpace
    }
}

// MARK: - Cables / links

@Model
final class LabLink {
    var id: UUID = UUID()
    var fromID: UUID = UUID()
    var fromPort: String = ""
    var toID: UUID = UUID()
    var toPort: String = ""
    var kindRaw: String = "ethernet"   // ethernet, fiber, dac, wifi, power, virtual, usb
    var speed: String = ""
    var label: String = ""
    var colorName: String = "none"
    var length: String = ""
    var vlan: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(from: UUID, to: UUID) {
        fromID = from
        toID = to
        spaceID = Spaces.newItemSpace
    }

    static let kinds: [(String, String)] = [("ethernet", "Ethernet"), ("fiber", "Fiber"), ("dac", "DAC"), ("wifi", "Wi-Fi"),
                                            ("power", "Power"), ("usb", "USB"), ("virtual", "Virtual")]
    var kindLabel: String { Self.kinds.first { $0.0 == kindRaw }?.1 ?? kindRaw.capitalized }
}

// MARK: - Diagrams

@Model
final class LabDiagram {
    var id: UUID = UUID()
    var title: String = "Diagram"
    var layer: String = "custom"     // physical, network, services, custom, text
    var nodesData: Data = Data()
    var edgesData: Data = Data()
    var source: String = ""          // diagram-as-text
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(title: String = "Diagram", layer: String = "custom") {
        self.title = title
        self.layer = layer
        spaceID = Spaces.newItemSpace
    }

    var nodes: [DiagramNode] {
        get { JSONField.decode(nodesData, as: [DiagramNode].self) ?? [] }
        set { nodesData = JSONField.encode(newValue); updatedAt = .now }
    }
    var edges: [DiagramEdge] {
        get { JSONField.decode(edgesData, as: [DiagramEdge].self) ?? [] }
        set { edgesData = JSONField.encode(newValue); updatedAt = .now }
    }
}

// MARK: - Runbooks & maintenance

@Model
final class Runbook {
    var id: UUID = UUID()
    var title: String = ""
    var symbol: String = "list.bullet.clipboard"
    var kindRaw: String = "runbook"   // runbook, maintenance, recovery
    var stepsData: Data = Data()
    var repeatRaw: String = "none"    // none, weekly, monthly, quarterly, yearly
    var nextDue: Date? = nil
    var remind: Bool = false
    var runsData: Data = Data()
    var deviceIDsData: Data = Data()
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(title: String = "", kind: String = "runbook") {
        self.title = title
        self.kindRaw = kind
        spaceID = Spaces.newItemSpace
    }

    var steps: [RunbookStep] {
        get { JSONField.decode(stepsData, as: [RunbookStep].self) ?? [] }
        set { stepsData = JSONField.encode(newValue); updatedAt = .now }
    }
    var runs: [RunbookRun] {
        get { JSONField.decode(runsData, as: [RunbookRun].self) ?? [] }
        set { runsData = JSONField.encode(newValue) }
    }
    var deviceIDs: [UUID] {
        get { JSONField.decode(deviceIDsData, as: [UUID].self) ?? [] }
        set { deviceIDsData = JSONField.encode(newValue) }
    }

    static let repeats: [(String, String)] = [("none", "Never"), ("weekly", "Weekly"), ("monthly", "Monthly"),
                                              ("quarterly", "Every 3 Months"), ("yearly", "Yearly")]
    static let kinds: [(String, String, String)] = [("runbook", "Runbook", "list.bullet.clipboard"),
                                                    ("maintenance", "Maintenance", "wrench.and.screwdriver"),
                                                    ("recovery", "Disaster Recovery", "lifepreserver")]

    func nextDate(after date: Date) -> Date? {
        let cal = Calendar.current
        switch repeatRaw {
        case "weekly": return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case "monthly": return cal.date(byAdding: .month, value: 1, to: date)
        case "quarterly": return cal.date(byAdding: .month, value: 3, to: date)
        case "yearly": return cal.date(byAdding: .year, value: 1, to: date)
        default: return nil
        }
    }
    var isDue: Bool { nextDue.map { $0 <= Date() } ?? false }
}

extension LabDevice: HushItem {}
extension LabService: HushItem {}
extension LabSubnet: HushItem {}
extension LabRack: HushItem {}
extension LabLink: HushItem {}
extension LabDiagram: HushItem {}
extension Runbook: HushItem {}

enum HomelabModels {
    static let all: [any PersistentModel.Type] = [
        LabDevice.self, LabService.self, LabSubnet.self, LabRack.self, LabLink.self, LabDiagram.self, Runbook.self,
    ]
}
