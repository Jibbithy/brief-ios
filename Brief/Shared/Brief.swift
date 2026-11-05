import Foundation

/// One morning briefing, exactly as `GET /api/brief` returns it.
///
/// COMPILED INTO THE APP AND THE WIDGET. Everything the widget draws comes
/// from this type, so nothing in here may touch UIKit or the app's state.
///
/// LENIENT WHERE THE HUB MIGHT BE: the arrays default to empty when absent,
/// every weather number is optional and accepts a fraction, and dates accept
/// ISO-8601 with or without fractional seconds, or a bare `YYYY-MM-DD` for an
/// all-day event. One odd field should cost that field, not the whole brief.
struct Brief: Codable, Equatable, Sendable {
    var version: Int
    var generatedAt: Date
    /// The day this brief is about, `YYYY-MM-DD`, in the hub's local time.
    var date: String
    var headline: String
    var weather: Weather?
    /// TODAY's events. The name predates the week view.
    var calendar: [Event]
    /// Events starting in the seven days after today. Absent from a brief
    /// written before the week view, which decodes as empty.
    var upcoming: [Event]
    var emails: [Email]
    /// Subscription payments due within the week (from Ledger).
    var subscriptions: [Subscription]
    var rack: Rack?
    var errors: [String]

    struct Weather: Codable, Equatable, Sendable {
        var location: String
        var summary: String
        var high: Double?
        var low: Double?
        var precipChance: Double?
        var current: Double?
        var unit: String

        init(
            location: String, summary: String, high: Double?, low: Double?,
            precipChance: Double?, current: Double?, unit: String = "F"
        ) {
            self.location = location
            self.summary = summary
            self.high = high
            self.low = low
            self.precipChance = precipChance
            self.current = current
            self.unit = unit
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
            summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
            high = try c.decodeIfPresent(Double.self, forKey: .high)
            low = try c.decodeIfPresent(Double.self, forKey: .low)
            precipChance = try c.decodeIfPresent(Double.self, forKey: .precipChance)
            current = try c.decodeIfPresent(Double.self, forKey: .current)
            unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "F"
        }
    }

    struct Event: Codable, Equatable, Sendable, Identifiable {
        var title: String
        var start: Date
        var end: Date?
        var allDay: Bool
        var location: String?
        // The details an expanded row shows. All optional: the hub added them
        // after the first release, and a wrong type costs only that field.
        /// Multi-line description, line breaks kept.
        var notes: String?
        /// Which calendar it is on (the JSON key is `calendar`).
        var calendarName: String?
        /// A join link or similar, as sent. Use `link`, which only ever
        /// answers with a web URL.
        var url: String?
        /// The organizer's email address.
        var organizer: String?
        /// How many invitees; 0 for a private event.
        var attendees: Int?

        var id: String { "\(start.timeIntervalSince1970)|\(title)" }

        enum CodingKeys: String, CodingKey {
            case title, start, end, allDay, location, notes, url, organizer, attendees
            case calendarName = "calendar"
        }

        init(
            title: String, start: Date, end: Date? = nil, allDay: Bool = false, location: String? = nil,
            notes: String? = nil, calendarName: String? = nil, url: String? = nil,
            organizer: String? = nil, attendees: Int? = nil
        ) {
            self.title = title
            self.start = start
            self.end = end
            self.allDay = allDay
            self.location = location
            self.notes = notes
            self.calendarName = calendarName
            self.url = url
            self.organizer = organizer
            self.attendees = attendees
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? "(untitled)"
            start = try c.decode(Date.self, forKey: .start)
            end = try c.decodeIfPresent(Date.self, forKey: .end)
            allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
            location = try c.decodeIfPresent(String.self, forKey: .location)
            notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil
            calendarName = (try? c.decodeIfPresent(String.self, forKey: .calendarName)) ?? nil
            url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? nil
            organizer = (try? c.decodeIfPresent(String.self, forKey: .organizer)) ?? nil
            attendees = (try? c.decodeIfPresent(Int.self, forKey: .attendees)) ?? nil
        }

        /// `url` as a tappable link, only when it is http or https. The text
        /// comes from calendar invites, which other people write.
        var link: URL? {
            guard let url, let u = URL(string: url), let scheme = u.scheme?.lowercased(),
                scheme == "http" || scheme == "https", u.host != nil
            else { return nil }
            return u
        }

        /// "All day", "3 days", "30 min", "1 hr 45 min"; nil for a timed
        /// event with no end.
        var durationText: String? {
            if allDay {
                guard let end else { return "All day" }
                let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
                return days > 1 ? "\(days) days" : "All day"
            }
            guard let end, end > start else { return nil }
            let mins = Int((end.timeIntervalSince(start) / 60).rounded())
            let h = mins / 60, m = mins % 60
            if h == 0 { return "\(m) min" }
            return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
        }
    }

    /// A subscription payment due soon. `dueDate` is the hub's calendar day,
    /// `YYYY-MM-DD`, kept as a string so no time zone can move it.
    struct Subscription: Codable, Equatable, Sendable, Identifiable {
        var name: String
        var amount: Double
        var currency: String
        var dueDate: String
        var source: String

        var id: String { "\(dueDate)|\(name)" }

        init(name: String, amount: Double, currency: String = "USD", dueDate: String, source: String = "ledger") {
            self.name = name
            self.amount = amount
            self.currency = currency
            self.dueDate = dueDate
            self.source = source
        }

        /// Local midnight of the due day.
        var due: Date? { Brief.parseDate(dueDate) }

        var amountText: String {
            amount.formatted(.currency(code: currency).locale(Locale(identifier: "en_US")))
        }
    }

    struct Email: Codable, Equatable, Sendable, Identifiable {
        /// `Name <addr>`, or a bare address.
        var from: String
        var subject: String
        var why: String
        var receivedAt: Date?
        /// The start of the body, one line, for the expanded row.
        var snippet: String?

        var id: String { "\(from)|\(subject)|\(receivedAt?.timeIntervalSince1970 ?? 0)" }

        init(from: String, subject: String, why: String, receivedAt: Date? = nil, snippet: String? = nil) {
            self.from = from
            self.subject = subject
            self.why = why
            self.receivedAt = receivedAt
            self.snippet = snippet
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
            subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? "(no subject)"
            why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
            receivedAt = try? c.decodeIfPresent(Date.self, forKey: .receivedAt)
            snippet = (try? c.decodeIfPresent(String.self, forKey: .snippet)) ?? nil
        }

        /// The display name out of `Name <addr>`; the address when there is no
        /// name; the raw string when it is neither.
        var sender: String {
            let s = from.trimmingCharacters(in: .whitespaces)
            if let lt = s.firstIndex(of: "<") {
                let name = s[..<lt].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !name.isEmpty { return name }
                let rest = s[s.index(after: lt)...]
                return String(rest.prefix { $0 != ">" })
            }
            return s
        }
    }

    struct Rack: Codable, Equatable, Sendable {
        var down: [String]
        var total: Int

        init(down: [String], total: Int) {
            self.down = down
            self.total = total
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            down = try c.decodeIfPresent([String].self, forKey: .down) ?? []
            total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        }

        var allUp: Bool { down.isEmpty }
    }

    init(
        version: Int = 1, generatedAt: Date, date: String, headline: String,
        weather: Weather?, calendar: [Event], upcoming: [Event] = [], emails: [Email],
        subscriptions: [Subscription] = [], rack: Rack?, errors: [String] = []
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.date = date
        self.headline = headline
        self.weather = weather
        self.calendar = calendar
        self.upcoming = upcoming
        self.emails = emails
        self.subscriptions = subscriptions
        self.rack = rack
        self.errors = errors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        weather = try c.decodeIfPresent(Weather.self, forKey: .weather)
        calendar = try c.decodeIfPresent([Event].self, forKey: .calendar) ?? []
        upcoming = try c.decodeIfPresent([Event].self, forKey: .upcoming) ?? []
        emails = try c.decodeIfPresent([Email].self, forKey: .emails) ?? []
        // Lossy: one malformed payment is dropped, not the whole brief.
        subscriptions = (try? c.decodeIfPresent([Lossy<Subscription>].self, forKey: .subscriptions))?
            .compactMap(\.value) ?? []
        rack = try c.decodeIfPresent(Rack.self, forKey: .rack)
        errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
    }
}

// MARK: - Decoding

/// One array element that decodes to nil instead of failing the array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension Brief {
    /// The ONE decoder for hub JSON and for the cache, which stores the hub's
    /// bytes verbatim.
    static func decode(_ data: Data) throws -> Brief {
        try decoder.decode(Brief.self, from: data)
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an ISO-8601 date: \(s)")
            }
            return date
        }
        return d
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(date.formatted(.iso8601))
        }
        return e
    }

    /// ISO-8601 with fractional seconds (what JS `toISOString()` writes), then
    /// without, then a bare `YYYY-MM-DD` read as local midnight - the shape a
    /// calendar gives an all-day event.
    static func parseDate(_ s: String) -> Date? {
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle()) { return d }
        let parts = s.split(separator: "-")
        if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
        }
        return nil
    }
}

// MARK: - Ordering

extension Brief {
    /// Today's calendar as it is shown: all-day events first (by title), then
    /// timed events by start time, ties by title. Stable whatever order the
    /// hub sent.
    var agenda: [Event] { Self.ordered(calendar) }

    static func ordered(_ events: [Event]) -> [Event] {
        events.sorted { a, b in
            if a.allDay != b.allDay { return a.allDay }
            if !a.allDay, a.start != b.start { return a.start < b.start }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// The next seven days, one group per local day, each read like today
    /// (all-day first, then by time).
    var upcomingDays: [(day: Date, events: [Event])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { ($0, Self.ordered(groups[$0]!)) }
    }

    /// Payments due, soonest first, ties by name.
    var dueSubscriptions: [Subscription] {
        subscriptions.sorted {
            $0.dueDate != $1.dueDate ? $0.dueDate < $1.dueDate
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The timed event that is on now or next, for the widget. An event is
    /// over once its end has passed (its start, when it has no end). All-day
    /// events never count: they are not "next" at any particular time.
    func nextEvent(after now: Date) -> Event? {
        agenda.first { !$0.allDay && ($0.end ?? $0.start) > now }
    }

    /// True when the brief's `date` is `now`'s calendar day - false for
    /// yesterday's brief still sitting in the cache.
    func isForDay(of now: Date, calendar cal: Calendar = .current) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return date == String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The moments at which `nextEvent(after:)` changes answer, for the
    /// widget's timeline: every timed event's start and end after `now`.
    func eventBoundaries(after now: Date) -> [Date] {
        let all = calendar.filter { !$0.allDay }.flatMap { [$0.start, $0.end].compactMap { $0 } }
        return Array(Set(all.filter { $0 > now })).sorted()
    }
}

// MARK: - Formatting shared by app and widget

extension Brief.Weather {
    static func degrees(_ v: Double?) -> String {
        guard let v else { return "–" }
        return "\(Int(v.rounded()))°"
    }
}
