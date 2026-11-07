import Foundation
import SwiftData

/// Sample content used only when Hush is launched with `-demoSeed YES`
/// (the automated screenshot run). Never runs in normal use.
@MainActor
enum DemoData {
    static func seedIfRequested(_ ctx: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "demoSeed"),
              ((try? ctx.fetchCount(FetchDescriptor<Note>())) ?? 0) == 0 else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ n: Int, _ hour: Int = 9) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: n, to: today) ?? today) ?? today
        }

        let notes: [(String, String, [String], Bool, String)] = [
            ("Trip ideas", "Coast drive in spring\n☐ Book cabin\n☐ Check tide tables", ["travel"], true, "map"),
            ("Book list", "• The quiet hours\n• Field notes on rivers", ["reading"], true, ""),
            ("Meeting notes", "Agreed on the new schedule. Follow up Friday.", ["work"], false, ""),
            ("Recipe: lentil soup", "Onion, carrot, lentils, cumin, lemon.", ["cooking"], false, "fork.knife"),
        ]
        for (i, n) in notes.enumerated() {
            let note = Note()
            note.title = n.0; note.body = n.1; note.tags = n.2; note.isPinned = n.3; note.emoji = n.4
            note.updatedAt = day(-i, 10)
            ctx.insert(note)
        }

        let lab = Folder(name: "Homelab")
        ctx.insert(lab)
        let servers = Folder(name: "Servers", parentID: lab.id)
        ctx.insert(servers)
        let md = Note()
        md.title = "Homelab notes"
        md.emoji = "server.rack"
        md.folderID = lab.id
        md.tags = ["homelab"]
        md.body = """
        ## To do this weekend
        - [x] Update the NAS firmware
        - [ ] Test restoring last night's **backup**
        - [ ] Move *media server* to the new VLAN

        > [!WARNING] Before upgrading
        > Take a snapshot and check ==backups== first.

        <u>Owner</u>: me · ~~old NAS~~ retired

        See [[Trip ideas]] for the off-site backup drive plan.

        `docker compose pull && docker compose up -d`
        """
        md.body += """


        ```yaml
        services:
          jellyfin:
            image: jellyfin/jellyfin:latest   # media server
            ports:
              - "8096:8096"
            restart: unless-stopped
        ```

        | Host | IP | Role |
        |---|---|---|
        | pve-01 | 10.0.10.10 | Hypervisor |
        | truenas | 10.0.10.20 | Storage |
        """
        md.updatedAt = day(0, 11)
        ctx.insert(md)

        for (i, h) in [("Drink water", "drop", 8), ("Read", "book", 1), ("Stretch", "figure.yoga", 1), ("Vitamins", "pills", 1)].enumerated() {
            let habit = Habit(name: h.0)
            habit.emoji = h.1
            habit.target = h.2
            habit.sortIndex = i
            habit.createdAt = day(-20)
            var log: [String: Int] = [:]
            for d in 1...14 where (d + i) % 4 != 0 { log[Habit.key(day(-d))] = h.2 }
            if i == 1 { log[Habit.key(day(0))] = 1 }
            if i == 0 { log[Habit.key(day(0))] = 3 }
            habit.log = log
            ctx.insert(habit)
        }

        let water = Habit(name: "Weight")
        water.kindRaw = "measure"; water.unit = "kg"; water.goalDirection = "atMost"; water.goalValue = 78; water.sumEntries = false
        water.emoji = "scalemass"; water.sortIndex = 9; water.createdAt = day(-60)
        var vals: [String: Double] = [:]
        for d in 0..<45 where d % 2 == 0 { vals[Habit.key(day(-d))] = 80.5 - Double(45 - d) * 0.04 + Double(d % 5) * 0.1 }
        water.values = vals
        ctx.insert(water)

        let tasks: [(String, Int?, Int)] = [("Vitamins", 0, 0), ("Call the dentist", 0, 3), ("Water plants", 1, 1), ("Renew library card", 3, 2)]
        for t in tasks {
            let task = TaskItem(title: t.0)
            task.dueDate = t.1.map { day($0, 0) }
            task.priorityRaw = t.2
            ctx.insert(task)
        }

        let e1 = CalendarEvent(start: day(0, 15)); e1.title = "Coffee with Sam"; e1.location = "Corner café"
        let e2 = CalendarEvent(start: day(2, 18)); e2.title = "Yoga class"
        ctx.insert(e1); ctx.insert(e2)

        let j = JournalEntry(date: day(-1, 21)); j.title = "Quiet evening"; j.body = "Long walk, early night."; j.moodRaw = 4
        ctx.insert(j)

        for (title, url, tags) in [("Example", "https://example.com", ["reference"]), ("Weather", "https://example.org/weather", ["daily"])] {
            let b = Bookmark(); b.title = title; b.urlString = url; b.tags = tags
            ctx.insert(b)
        }

        let c = Contact(); c.firstName = "Alex"; c.lastName = "Rivera"; c.company = "Studio North"; c.isFavorite = true
        c.phones = [LabeledValue(label: "mobile", value: "555-0100")]
        ctx.insert(c)
        let c2 = Contact(); c2.firstName = "Jordan"; c2.lastName = "Lee"
        ctx.insert(c2)
        seedHomelab(ctx)
        ctx.insert(StoredFile(name: "network-plan.txt", typeIdentifier: "public.plain-text",
                              data: Data("VLAN 10 servers, VLAN 20 IoT, VLAN 30 guests.\nBackups nightly to the NAS.\n".utf8)))
        try? ctx.save()
    }

    private static func seedHomelab(_ ctx: ModelContext) {
        func dev(_ name: String, _ kind: DeviceKind, _ ip: String, _ watts: Double, host: LabDevice? = nil, os: String = "", model: String = "") -> LabDevice {
            let d = LabDevice(name: name, kind: kind)
            d.ip = ip; d.powerWatts = watts; d.hostID = host?.id; d.os = os; d.model = model
            ctx.insert(d)
            return d
        }
        let modem = dev("ISP Modem", .modem, "192.168.100.1", 8)
        let fw = dev("opnsense", .firewall, "10.0.10.1", 18, os: "OPNsense 25.1", model: "Protectli VP2420")
        let sw = dev("core-switch", .switchDevice, "10.0.10.2", 22, model: "8-port 2.5G")
        sw.portCount = 8
        let ap = dev("ap-living", .accessPoint, "10.0.10.3", 9)
        let pve = dev("pve-01", .hypervisor, "10.0.10.10", 65, os: "Proxmox VE 8", model: "Mini PC, 64 GB")
        let nas = dev("truenas", .nas, "10.0.10.20", 48, os: "TrueNAS SCALE", model: "4× 8 TB")
        pve.cores = 16; pve.memoryMB = 65536; pve.clusterName = "homelab"; pve.storagePool = "local-zfs"
        let pve2 = dev("pve-02", .hypervisor, "10.0.10.11", 35, os: "Proxmox VE 8", model: "Mini PC, 32 GB")
        pve2.cores = 8; pve2.memoryMB = 32768; pve2.clusterName = "homelab"
        let docker = dev("docker-vm", .vm, "10.0.10.30", 0, host: pve, os: "Debian 12")
        docker.vmid = 101; docker.cores = 4; docker.memoryMB = 8192; docker.diskGB = 64; docker.bridge = "vmbr0"; docker.onBoot = true
        let ha = dev("home-assistant", .vm, "10.0.20.40", 0, host: pve, os: "HAOS")
        ha.vmid = 102; ha.cores = 2; ha.memoryMB = 4096; ha.diskGB = 32; ha.bridge = "vmbr0"; ha.vlanTag = "20"; ha.onBoot = true
        let dns = dev("pihole", .lxc, "10.0.10.53", 0, host: pve2, os: "debian")
        dns.vmid = 200; dns.cores = 1; dns.memoryMB = 512; dns.diskGB = 8; dns.bridge = "vmbr0"; dns.onBoot = true
        let mon = dev("monitoring", .lxc, "10.0.10.60", 0, host: pve2, os: "debian")
        mon.vmid = 201; mon.cores = 2; mon.memoryMB = 2048; mon.diskGB = 16; mon.bridge = "vmbr0"
        let stack = ComposeStack(name: "monitoring")
        stack.hostID = mon.id
        stack.path = "/opt/stacks/monitoring"
        stack.lastDeployed = .now
        stack.updateMethod = "Watchtower"
        stack.yaml = """
        services:
          grafana:
            image: grafana/grafana:11.2.0
            container_name: grafana
            ports:
              - "3000:3000"
            volumes:
              - ./grafana:/var/lib/grafana
            environment:
              - GF_SECURITY_ADMIN_PASSWORD=***
            depends_on:
              - prometheus
            restart: unless-stopped
          prometheus:
            image: prom/prometheus:v2.54.1
            ports:
              - 9090:9090
            volumes:
              - ./prometheus.yml:/etc/prometheus/prometheus.yml
            restart: unless-stopped
        """
        ctx.insert(stack)
        _ = LabImport.sync(stack, in: ctx)
        let ups = dev("ups", .ups, "", 0, model: "1500 VA")
        ups.storage = ""
        let rack = LabRack(name: "Network Rack", units: 12)
        ctx.insert(rack)
        for (d, u, h) in [(fw, 11, 1), (sw, 10, 1), (pve, 7, 2), (nas, 3, 3), (ups, 1, 2)] { d.rackID = rack.id; d.rackU = u; d.heightU = h }

        for (name, cidr, vlan, color, purpose) in [("Main LAN", "10.0.10.0/24", 10, "blue", "Servers & trusted devices"),
                                                    ("IoT", "10.0.20.0/24", 20, "orange", "Smart home, isolated"),
                                                    ("Guest", "10.0.30.0/24", 30, "green", "Internet only")] {
            let sn = LabSubnet(name: name, cidr: cidr)
            sn.vlanID = vlan; sn.colorName = color; sn.purpose = purpose
            sn.gateway = cidr.replacingOccurrences(of: ".0/24", with: ".1")
            sn.dhcpStart = cidr.replacingOccurrences(of: ".0/24", with: ".100")
            sn.dhcpEnd = cidr.replacingOccurrences(of: ".0/24", with: ".199")
            ctx.insert(sn)
        }
        for (a, b, ap1, bp, speed) in [(modem, fw, "LAN", "WAN", "1G"), (fw, sw, "LAN", "1", "2.5G"), (sw, pve, "2", "nic0", "2.5G"),
                                       (sw, nas, "3", "eth0", "2.5G"), (sw, ap, "4", "PoE", "1G")] {
            let l = LabLink(from: a.id, to: b.id)
            l.fromPort = ap1; l.toPort = bp; l.speed = speed
            ctx.insert(l)
        }
        for (name, host, ports, sym, backed) in [("Jellyfin", docker, [8096], "play.rectangle", true), ("Pi-hole", docker, [53, 80], "shield", true),
                                                 ("Nextcloud", docker, [443], "cloud", false), ("Proxmox UI", pve, [8006], "square.stack.3d.up", true),
                                                 ("TrueNAS UI", nas, [443], "externaldrive", true)] {
            let svc = LabService(name: name)
            svc.hostID = host.id; svc.symbol = sym; svc.backedUp = backed
            svc.ports = ports.map { ServicePort(port: $0, purpose: CommonPorts.name($0) ?? "") }
            svc.url = "http://\(host.ip):\(ports[0])"
            ctx.insert(svc)
        }
        let rb = Runbook(title: RunbookStarters.maintenance.0, kind: "maintenance")
        rb.symbol = RunbookStarters.maintenance.1
        rb.steps = RunbookStarters.maintenance.2
        rb.repeatRaw = "monthly"
        rb.nextDue = Calendar.current.date(byAdding: .day, value: -1, to: .now)
        ctx.insert(rb)
        let board = Board(title: "Homelab Projects")
        BoardTemplates.apply(BoardTemplates.all.first { $0.id == "homelab" }!, to: board)
        board.colorName = "purple"
        ctx.insert(board)
        let cols = board.columns, labs = board.labels
        for (i, (title, col, label, color)) in [("Set up Tailscale", 0, 0, "none"), ("Add 10G NIC to NAS", 1, 3, "orange"),
                                                 ("Move cameras to IoT VLAN", 2, 0, "blue"), ("Grafana dashboard", 2, 2, "none"),
                                                 ("Test UPS shutdown script", 3, 3, "red"), ("Replace old switch", 4, 0, "green")].enumerated() {
            let c = BoardCard(boardID: board.id, columnID: cols[col].id, title: title)
            c.order = Double(i)
            c.labelIDs = [labs[label].id]
            c.colorName = color
            if i == 1 { c.checklist = [Subtask(title: "Order card", done: true), Subtask(title: "Install"), Subtask(title: "Set MTU 9000")] }
            if i == 2 { c.dueDate = Calendar.current.date(byAdding: .day, value: 2, to: .now) }
            if col == 4 { c.completedAt = .now }
            ctx.insert(c)
        }
        let diagram = LabDiagram(title: "Physical Layout", layer: "physical")
        let built = DiagramBuilder.build(layer: "physical", devices: [modem, fw, sw, ap, pve, nas, ups], links: (try? ctx.fetch(FetchDescriptor<LabLink>())) ?? [],
                                         services: [], subnets: [])
        diagram.nodes = built.0
        diagram.edges = built.1
        ctx.insert(diagram)
    }
}
