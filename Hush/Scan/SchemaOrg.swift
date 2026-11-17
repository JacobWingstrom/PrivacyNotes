import Foundation

/// Reads schema.org JSON-LD that airlines, hotels, shops and ticket sites put in their emails
/// (the same data Gmail and Apple Mail use for "Add to calendar").
enum SchemaOrg {
    enum Item {
        case event(FoundEvent)
        case task(FoundTask)
    }

    static func extract(_ html: String) -> [Item] {
        var out: [Item] = []
        for obj in jsonObjects(html) {
            if let item = convert(obj) { out.append(item) }
        }
        return out
    }

    private static func jsonObjects(_ html: String) -> [[String: Any]] {
        guard let re = try? NSRegularExpression(pattern: "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var out: [[String: Any]] = []
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let json = MIME.decodeEntities(ns.substring(with: m.range(at: 1))).trimmed
            guard let data = json.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) else { continue }
            flatten(parsed, into: &out)
        }
        return out
    }

    private static func flatten(_ value: Any, into out: inout [[String: Any]]) {
        if let arr = value as? [Any] { for v in arr { flatten(v, into: &out) } }
        else if let dict = value as? [String: Any] {
            if let graph = dict["@graph"] { flatten(graph, into: &out) } else { out.append(dict) }
        }
    }

    private static func types(_ o: [String: Any]) -> [String] {
        if let t = o["@type"] as? String { return [t] }
        return (o["@type"] as? [String]) ?? []
    }

    private static func str(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmed }
        if let n = v as? NSNumber { return n.stringValue }
        if let d = v as? [String: Any] { return str(d["name"] ?? d["@id"]) }
        return ""
    }

    private static func obj(_ v: Any?) -> [String: Any] {
        if let d = v as? [String: Any] { return d }
        if let a = v as? [Any], let d = a.first as? [String: Any] { return d }
        return [:]
    }

    static func date(_ v: Any?) -> (Date, Bool)? {
        let s = str(v)
        guard !s.isEmpty else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: s) { return (d, true) }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return (d, true) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return (d, true) }
        }
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(s.prefix(10))) { return (d, false) }
        return nil
    }

    private static func address(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmed }
        let a = obj(v)
        let line2 = [str(a["postalCode"]), str(a["addressLocality"])].filter { !$0.isEmpty }.joined(separator: " ")
        return [str(a["streetAddress"]), line2, str(a["addressCountry"])].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func place(_ v: Any?) -> String {
        let p = obj(v)
        if p.isEmpty { return str(v) }
        let name = str(p["name"])
        let addr = address(p["address"])
        if let iata = p["iataCode"] as? String, !iata.isEmpty { return name.isEmpty ? iata : "\(name) (\(iata))" }
        return [name, addr].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func convert(_ o: [String: Any]) -> Item? {
        let t = types(o).first ?? ""
        let reservationNumber = str(o["reservationNumber"])
        let notesBase = reservationNumber.isEmpty ? "" : "Booking reference: \(reservationNumber)"
        let target = obj(o["reservationFor"])
        switch t {
        case "FlightReservation":
            let airline = obj(target["airline"])
            let code = str(airline["iataCode"]) + str(target["flightNumber"])
            let from = obj(target["departureAirport"]), to = obj(target["arrivalAirport"])
            guard let found_dep = date(target["departureTime"]) else { return nil }
            let (dep, _) = found_dep
            let arr = date(target["arrivalTime"])?.0 ?? dep.addingTimeInterval(7200)
            var e = FoundEvent()
            e.title = "Flight \(code.isEmpty ? "" : code + " ")\(str(from["iataCode"])) → \(str(to["iataCode"]))".replacingOccurrences(of: "  ", with: " ")
            e.start = dep; e.end = arr
            e.location = place(target["departureAirport"])
            e.notes = [notesBase, str(airline["name"]), "Seat: \(str(obj(o["reservedTicket"])["ticketedSeat"]))"].filter { !$0.isEmpty && $0 != "Seat: " }.joined(separator: "\n")
            return .event(e)
        case "LodgingReservation":
            guard let found_checkin = date(o["checkinTime"] ?? o["checkinDate"]) else { return nil }
            let (checkin, hasTime) = found_checkin
            let checkout = date(o["checkoutTime"] ?? o["checkoutDate"])?.0 ?? checkin.addingTimeInterval(86400)
            var e = FoundEvent()
            e.title = "Stay: \(str(target["name"]))"
            e.start = hasTime ? checkin : Calendar.current.startOfDay(for: checkin)
            e.end = checkout
            e.allDay = !hasTime
            e.location = place(target)
            e.notes = notesBase
            return .event(e)
        case "FoodEstablishmentReservation":
            guard let found_start = date(o["startTime"] ?? o["startDate"]) else { return nil }
            let (start, _) = found_start
            var e = FoundEvent()
            e.title = "Reservation: \(str(target["name"]))"
            e.start = start
            e.end = date(o["endTime"])?.0 ?? start.addingTimeInterval(7200)
            e.location = place(target)
            let size = str(o["partySize"])
            e.notes = [notesBase, size.isEmpty ? "" : "Party of \(size)"].filter { !$0.isEmpty }.joined(separator: "\n")
            return .event(e)
        case "EventReservation", "Event", "MusicEvent", "SportsEvent", "TheaterEvent", "BusinessEvent", "SocialEvent":
            let ev = t == "EventReservation" ? target : o
            guard let found_start = date(ev["startDate"]) else { return nil }
            let (start, hasTime) = found_start
            var e = FoundEvent()
            e.title = str(ev["name"]).isEmpty ? "Event" : str(ev["name"])
            e.start = start
            e.allDay = !hasTime
            e.end = date(ev["endDate"])?.0 ?? (hasTime ? start.addingTimeInterval(7200) : start.addingTimeInterval(86399))
            e.location = place(ev["location"])
            e.notes = notesBase
            return .event(e)
        case "RentalCarReservation":
            guard let found_start = date(o["pickupTime"]) else { return nil }
            let (start, _) = found_start
            var e = FoundEvent()
            e.title = "Car rental: \(str(obj(target["rentalCompany"])["name"]).isEmpty ? str(target["name"]) : str(obj(target["rentalCompany"])["name"]))"
            e.start = start
            e.end = date(o["dropoffTime"])?.0 ?? start.addingTimeInterval(3600)
            e.location = place(o["pickupLocation"])
            e.notes = notesBase
            return .event(e)
        case "TrainReservation", "BusReservation", "BoatReservation":
            guard let found_dep = date(target["departureTime"]) else { return nil }
            let (dep, _) = found_dep
            let fromName = place(target["departureStation"] ?? target["departureBusStop"] ?? target["departureBoatTerminal"])
            let toName = place(target["arrivalStation"] ?? target["arrivalBusStop"] ?? target["arrivalBoatTerminal"])
            var e = FoundEvent()
            let kind = t == "TrainReservation" ? "Train" : (t == "BusReservation" ? "Bus" : "Ferry")
            let number = str(target["trainNumber"] ?? target["busNumber"])
            e.title = "\(kind) \(number) \(fromName) → \(toName)".replacingOccurrences(of: "  ", with: " ")
            e.start = dep
            e.end = date(target["arrivalTime"])?.0 ?? dep.addingTimeInterval(3600)
            e.location = fromName
            e.notes = notesBase
            return .event(e)
        case "ParcelDelivery":
            let when = date(o["expectedArrivalUntil"]) ?? date(o["expectedArrivalFrom"])
            var task = FoundTask()
            let carrier = str(obj(o["carrier"])["name"]).isEmpty ? str(o["provider"]) : str(obj(o["carrier"])["name"])
            let item = str(obj(o["itemShipped"])["name"])
            task.title = "Package arriving" + (item.isEmpty ? "" : ": \(item)") + (carrier.isEmpty ? "" : " (\(carrier))")
            task.due = when?.0
            task.hasTime = false
            task.notes = [str(o["trackingNumber"]).isEmpty ? "" : "Tracking: \(str(o["trackingNumber"]))", str(o["trackingUrl"])].filter { !$0.isEmpty }.joined(separator: "\n")
            return .task(task)
        case "Invoice":
            guard let due = date(o["paymentDueDate"] ?? o["paymentDue"]) else { return nil }
            var task = FoundTask()
            let total = obj(o["totalPaymentDue"])
            let amount = [str(total["price"] ?? total["value"]), str(total["priceCurrency"] ?? total["currency"])].filter { !$0.isEmpty }.joined(separator: " ")
            let provider = str(obj(o["provider"])["name"])
            task.title = "Pay \(provider.isEmpty ? "invoice" : provider)" + (amount.isEmpty ? "" : " – \(amount)")
            task.due = due.0
            task.hasTime = false
            task.priority = 2
            return .task(task)
        default:
            return nil
        }
    }
}
