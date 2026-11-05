import Foundation

extension Brief {
    /// A fictional brief for `now`'s day, for demo mode and the widget preview.
    /// Every name, place and amount here is made up.
    static func sample(now: Date = Date(), calendar cal: Calendar = .current) -> Brief {
        let day = cal.startOfDay(for: now)
        func at(_ h: Int, _ m: Int = 0, day d: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: d, to: day)!)!
        }
        func ymd(_ d: Int) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: d, to: day)!)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        return Brief(
            generatedAt: at(8),
            date: ymd(0),
            headline: "Clear and cool in Anytown. Three meetings today, the first at 9:30, and one invoice to approve.",
            weather: Weather(
                location: "Anytown, US", summary: "Sunny", high: 78, low: 52,
                precipChance: 10, current: 61, unit: "F"),
            calendar: [
                Event(
                    title: "Team standup", start: at(9, 30), end: at(10), location: "Room 2",
                    notes: "Talking points:\n- Project Alpha status\n- Release checklist\n- Open questions",
                    calendarName: "Work", url: "https://meet.example.com/standup",
                    organizer: "manager@example.com", attendees: 6),
                Event(
                    title: "Quarterly Planning Day", start: day, end: at(24), allDay: true,
                    notes: "Bring your laptop.", calendarName: "Work"),
                Event(
                    title: "One on one with Sam: project review", start: at(13), end: at(13, 30),
                    calendarName: "Work", organizer: "sam@example.com", attendees: 2),
                Event(
                    title: "Pick up package, Main St", start: at(16, 15), end: at(17),
                    location: "100 Main St, Anytown", calendarName: "Home"),
            ],
            upcoming: [
                Event(
                    title: "Dentist", start: at(15, day: 1), end: at(16, day: 1),
                    location: "Anytown Dental Office", calendarName: "Home"),
                Event(title: "Book club", start: at(17, 30, day: 1), end: at(19, day: 1), calendarName: "Home"),
                Event(
                    title: "Weekend trip, Example Lake", start: at(0, day: 3), end: at(0, day: 5), allDay: true,
                    location: "100 Lake Road, Example Lake", calendarName: "Home"),
                Event(
                    title: "Quarterly review", start: at(10, day: 3), end: at(11, 30, day: 3),
                    notes: "Bring the Q3 summary notes.", calendarName: "Work",
                    url: "https://meet.example.com/q3", organizer: "ops@example.com", attendees: 3),
                Event(title: "Car service, Anytown", start: at(9, day: 6), end: at(10, day: 6), calendarName: "Home"),
            ],
            emails: [
                Email(
                    from: "Alex Example <alex@example.com>", subject: "Re: Invoice approval for the Q3 work",
                    why: "Needs your OK on a $1,250 charge before the end of the day.",
                    receivedAt: at(6, 52),
                    snippet: "Thanks for getting back to me. $1,250 all-in, billed Friday at 5 PM, payable on receipt."),
                Email(
                    from: "billing@example.com", subject: "Invoice 100200300 received",
                    why: "The vendor sent a revised total on a past-due invoice.",
                    receivedAt: at(7, 15),
                    snippet: "A revised total of $85 is due on invoice 100200300. Contact billing with questions."),
                Email(
                    from: "\"Example Membership\" <renewals@example.com>", subject: "Your membership renews in 30 days",
                    why: "Renewal is automatic; no action if the card is current.",
                    receivedAt: at(5, 3),
                    snippet: "Your Example Program membership renews soon, automatically."),
            ],
            subscriptions: [
                Subscription(name: "StreamCo", amount: 11.99, dueDate: ymd(1)),
                Subscription(name: "CloudBox", amount: 2.99, dueDate: ymd(4)),
                Subscription(name: "NewsDaily", amount: 7.99, dueDate: ymd(6)),
            ],
            rack: Rack(down: ["iris"], total: 7),
            errors: ["Weather data is 2 hours old; the 8 AM check timed out."]
        )
    }
}
