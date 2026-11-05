import XCTest

@testable import Brief

final class BriefDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> Brief {
        try Brief.decode(Data(json.utf8))
    }

    func testFullContractDecodes() throws {
        let b = try decode(
            """
            { "version": 1, "generatedAt": "2026-09-26T14:00:03.512Z", "date": "2026-09-26",
              "headline": "Sunny and quiet.",
              "weather": { "location": "Anytown, US", "summary": "Sunny", "high": 78, "low": 52,
                           "precipChance": 10, "current": 61, "unit": "F" },
              "calendar": [ { "title": "Standup", "start": "2026-09-26T15:30:00Z",
                              "end": "2026-09-26T16:00:00Z", "allDay": false, "location": "Office" } ],
              "emails": [ { "from": "Sam Sender <s@example.com>", "subject": "Rate",
                            "why": "Needs a yes", "receivedAt": "2026-09-26T12:52:00Z" } ],
              "rack": { "down": ["iris"], "total": 7 },
              "errors": ["weather slow"] }
            """)
        XCTAssertEqual(b.version, 1)
        XCTAssertEqual(b.date, "2026-09-26")
        XCTAssertEqual(b.headline, "Sunny and quiet.")
        XCTAssertEqual(b.generatedAt, Date(timeIntervalSince1970: 1_790_431_203.512), accuracy: 0.001)
        XCTAssertEqual(b.weather?.high, 78)
        XCTAssertEqual(b.weather?.low, 52)
        XCTAssertEqual(b.weather?.current, 61)
        XCTAssertEqual(b.weather?.precipChance, 10)
        XCTAssertEqual(b.weather?.unit, "F")
        XCTAssertEqual(b.calendar.count, 1)
        XCTAssertEqual(b.calendar[0].start, Date(timeIntervalSince1970: 1_790_436_600))
        XCTAssertEqual(b.calendar[0].end, Date(timeIntervalSince1970: 1_790_438_400))
        XCTAssertEqual(b.calendar[0].location, "Office")
        XCTAssertEqual(b.emails[0].sender, "Sam Sender")
        XCTAssertEqual(b.emails[0].receivedAt, Date(timeIntervalSince1970: 1_790_427_120))
        XCTAssertEqual(b.rack, Brief.Rack(down: ["iris"], total: 7))
        XCTAssertFalse(b.rack!.allUp)
        XCTAssertEqual(b.errors, ["weather slow"])
    }

    func testNullWeatherAndRack() throws {
        let b = try decode(
            """
            { "version": 1, "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26",
              "headline": "h", "weather": null, "calendar": [], "emails": [], "rack": null, "errors": [] }
            """)
        XCTAssertNil(b.weather)
        XCTAssertNil(b.rack)
        XCTAssertTrue(b.calendar.isEmpty)
    }

    func testMissingArraysDefaultToEmpty() throws {
        let b = try decode(#"{ "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h" }"#)
        XCTAssertEqual(b.version, 1)
        XCTAssertTrue(b.calendar.isEmpty)
        XCTAssertTrue(b.emails.isEmpty)
        XCTAssertTrue(b.errors.isEmpty)
        XCTAssertNil(b.weather)
    }

    func testIsoWithAndWithoutFractionAndOffset() {
        XCTAssertEqual(Brief.parseDate("2026-09-26T14:00:00Z"), Date(timeIntervalSince1970: 1_790_431_200))
        XCTAssertEqual(Brief.parseDate("2026-09-26T14:00:00.000Z"), Date(timeIntervalSince1970: 1_790_431_200))
        XCTAssertEqual(Brief.parseDate("2026-09-26T08:00:00-06:00"), Date(timeIntervalSince1970: 1_790_431_200))
        XCTAssertNil(Brief.parseDate("yesterday"))
    }

    func testAllDayBareDateIsLocalMidnight() throws {
        let b = try decode(
            """
            { "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h",
              "calendar": [ { "title": "Holiday", "start": "2026-09-26", "end": "2026-09-27", "allDay": true, "location": null } ] }
            """)
        let e = b.calendar[0]
        XCTAssertTrue(e.allDay)
        XCTAssertNil(e.location)
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: e.start)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 9, 26, 0, 0])
    }

    func testFractionalWeatherNumbers() throws {
        let b = try decode(
            """
            { "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h",
              "weather": { "location": "Anytown, US", "summary": "Rain", "high": 71.6, "low": 49.4,
                           "precipChance": 60, "current": 55.2, "unit": "F" } }
            """)
        XCTAssertEqual(Brief.Weather.degrees(b.weather?.high), "72°")
        XCTAssertEqual(Brief.Weather.degrees(b.weather?.low), "49°")
        XCTAssertEqual(Brief.Weather.degrees(nil), "–")
    }

    func testBadDateFailsTheWholeBrief() {
        XCTAssertThrowsError(try decode(#"{ "generatedAt": "not a date", "date": "x", "headline": "h" }"#))
    }

    func testSenderParsing() {
        XCTAssertEqual(Brief.Email(from: "Jo <jo@example.com>", subject: "", why: "").sender, "Jo")
        XCTAssertEqual(Brief.Email(from: "\"Apple Dev\" <d@example.com>", subject: "", why: "").sender, "Apple Dev")
        XCTAssertEqual(Brief.Email(from: "<only@example.com>", subject: "", why: "").sender, "only@example.com")
        XCTAssertEqual(Brief.Email(from: "bare@example.com", subject: "", why: "").sender, "bare@example.com")
    }

    func testCacheRoundTripKeepsHubBytes() throws {
        // The cache stores the hub's bytes verbatim and re-decodes them; the
        // sample brief survives an encode/decode through the same decoder.
        let sample = Brief.sample(now: Date(timeIntervalSince1970: 1_790_431_200))
        let data = try Brief.encoder.encode(sample)
        let back = try Brief.decode(data)
        XCTAssertEqual(back.headline, sample.headline)
        XCTAssertEqual(back.calendar.count, sample.calendar.count)
        for (a, b) in zip(back.calendar, sample.calendar) {
            XCTAssertEqual(a.start.timeIntervalSince1970, b.start.timeIntervalSince1970, accuracy: 1)
        }
    }

    // MARK: - hub answers

    func testClassify200() {
        let json = #"{ "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h" }"#
        guard case .brief(let b, let data) = BriefAPI.classify(status: 200, data: Data(json.utf8)) else {
            return XCTFail("200 should be a brief")
        }
        XCTAssertEqual(b.headline, "h")
        XCTAssertEqual(data, Data(json.utf8))
    }

    func testClassify404IsNoBriefYet() {
        guard case .none = BriefAPI.classify(status: 404, data: Data(#"{"error":"no brief yet"}"#.utf8)) else {
            return XCTFail("404 should be .none")
        }
    }

    func testClassify401AndOthers() {
        guard case .unauthorized = BriefAPI.classify(status: 401, data: Data()) else { return XCTFail() }
        guard case .failed(let m) = BriefAPI.classify(status: 502, data: Data("bad gateway".utf8)) else {
            return XCTFail()
        }
        XCTAssertTrue(m.contains("502"))
        guard case .failed = BriefAPI.classify(status: 200, data: Data("{}".utf8)) else {
            return XCTFail("a 200 that does not decode is a failure, not a brief")
        }
    }

    func testPushPayloadKind() {
        XCTAssertTrue(PushRegistrar.isBrief(["kind": "brief", "date": "2026-09-26"]))
        XCTAssertFalse(PushRegistrar.isBrief(["kind": "turn"]))
        XCTAssertEqual(PushRegistrar.hex(Data([0x0a, 0xff, 0x00])), "0aff00")
    }
}

private func XCTAssertEqual(_ a: Date, _ b: Date, accuracy: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.timeIntervalSince1970, b.timeIntervalSince1970, accuracy: accuracy, file: file, line: line)
}
