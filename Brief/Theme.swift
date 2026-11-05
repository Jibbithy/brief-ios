import SwiftUI

/// Brief's own metrics on top of Deck Cream. Every colour is a `Deck.*` token
/// at the call site; there is no second palette here.
enum Theme {
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 24

    /// Width of the time column in the calendar and email rows, so the titles
    /// line up down the card.
    static let timeColumn: CGFloat = 64
}
