import XCTest

@testable import Brief

final class OrderingTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_431_200))
    private func at(_ h: Int, _ m: Int = 0) -> Date { day.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }

    private func brief(_ events: [Brief.Event]) -> Brief {
        Brief(generatedAt: at(8), date: "x", headline: "", weather: nil, calendar: events, emails: [], rack: nil)
    }

    func testAllDayFirstThenByStart() {
        let events = [
            Brief.Event(title: "Lunch", start: at(12), end: at(13)),
            Brief.Event(title: "Zed holiday", start: day, allDay: true),
            Brief.Event(title: "Standup", start: at(9, 30), end: at(10)),
            Brief.Event(title: "Alpha holiday", start: day, allDay: true),
            Brief.Event(title: "Early", start: at(7), end: at(7, 15)),
        ]
        XCTAssertEqual(
            brief(events).agenda.map(\.title),
            ["Alpha holiday", "Zed holiday", "Early", "Standup", "Lunch"])
    }

    func testSameStartBreaksTieByTitle() {
        let events = [
            Brief.Event(title: "b", start: at(9)),
            Brief.Event(title: "a", start: at(9)),
        ]
        XCTAssertEqual(Brief.ordered(events).map(\.title), ["a", "b"])
    }

    func testNextEventSkipsAllDayAndFinished() {
        let b = brief([
            Brief.Event(title: "Holiday", start: day, allDay: true),
            Brief.Event(title: "Done", start: at(8), end: at(9)),
            Brief.Event(title: "Standup", start: at(9, 30), end: at(10)),
            Brief.Event(title: "Lunch", start: at(12), end: at(13)),
        ])
        XCTAssertEqual(b.nextEvent(after: at(9, 5))?.title, "Standup")
        // In progress counts as "next" until it ends.
        XCTAssertEqual(b.nextEvent(after: at(9, 45))?.title, "Standup")
        XCTAssertEqual(b.nextEvent(after: at(10))?.title, "Lunch")
        XCTAssertNil(b.nextEvent(after: at(14)))
    }

    func testNextEventWithoutEndIsOverAtStart() {
        let b = brief([Brief.Event(title: "Ping", start: at(10))])
        XCTAssertEqual(b.nextEvent(after: at(9))?.title, "Ping")
        XCTAssertNil(b.nextEvent(after: at(10)))
    }

    func testEventBoundariesAreFutureSortedUnique() {
        let b = brief([
            Brief.Event(title: "A", start: at(9), end: at(10)),
            Brief.Event(title: "B", start: at(10), end: at(11)),
            Brief.Event(title: "Holiday", start: day, allDay: true),
        ])
        XCTAssertEqual(b.eventBoundaries(after: at(9, 30)), [at(10), at(11)])
    }

    func testIsForDay() {
        var b = brief([])
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        b.date = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        XCTAssertTrue(b.isForDay(of: at(12)))
        XCTAssertFalse(b.isForDay(of: at(36)))
    }

    func testSampleIsTodayAndOrdered() {
        let s = Brief.sample(now: at(8, 30))
        XCTAssertTrue(s.isForDay(of: at(8, 30)))
        XCTAssertTrue(s.agenda.first?.allDay == true)
        XCTAssertEqual(s.nextEvent(after: at(8, 30))?.title, "Team standup")
    }

    func testWeatherGlyph() {
        XCTAssertEqual(WeatherGlyph.symbol(for: "Sunny"), "sun.max.fill")
        XCTAssertEqual(WeatherGlyph.symbol(for: "Partly cloudy"), "cloud.sun.fill")
        XCTAssertEqual(WeatherGlyph.symbol(for: "Light rain showers"), "cloud.rain.fill")
        XCTAssertEqual(WeatherGlyph.symbol(for: "Thunderstorms"), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherGlyph.symbol(for: "???"), "thermometer.medium")
    }
}
