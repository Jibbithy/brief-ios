import SwiftUI
import UIKit

// Brief's own Deck Cream pieces - what DeckCream.swift / DeckExtras.swift (the
// rack-os-design copies, never edited here) do not have.

// MARK: - Tab bar

/// The Brief · To-Do tab bar, drawn exactly like Rack Control's (its
/// DeckLocal.swift DeckChrome): a rail strip with the 3px ink edge facing the
/// page, mono labels, and the selected tab's label inverted.
///
/// UIKIT APPEARANCE because SwiftUI modifiers stop at the background colour.
/// It only reads as Deck because the app opts out of Liquid Glass
/// (UIDesignRequiresCompatibility in Brief/Info.plist); under glass the bar is
/// a floating capsule none of this reaches. Installed once, after the fonts.
enum DeckChrome {
    @MainActor
    static func install() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = ui(Deck.rail)
        // shadowColor alone is a one-pixel hairline; a template image tinted
        // by it is how the edge gets to be 3pt AND follow the appearance.
        tab.shadowColor = ui(Deck.line)
        tab.shadowImage = edge(Deck.borderWidthLarge)

        // Fixed size: a tab bar does not grow with Dynamic Type.
        let label = UIFont(name: Deck.MonoWeight.semibold.rawValue, size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)
        let item = UITabBarItemAppearance(style: .stacked)
        item.normal.iconColor = ui(Deck.muted)
        item.normal.titleTextAttributes = [.font: label, .foregroundColor: ui(Deck.muted)]
        item.selected.iconColor = ui(Deck.ink)
        item.selected.titleTextAttributes = [
            .font: label, .foregroundColor: ui(Deck.inkInverse), .backgroundColor: ui(Deck.ink),
        ]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    /// A Deck token as a DYNAMIC UIColor, so a bar built once at launch still
    /// flips with the appearance.
    static func ui(_ color: Color) -> UIColor {
        UIColor { traits in
            var env = EnvironmentValues()
            env.colorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(cgColor: color.resolve(in: env).cgColor)
        }
    }

    /// A 1pt-wide strip `height` tall, as a template: the bar tints it.
    private static func edge(_ height: CGFloat) -> UIImage {
        let size = CGSize(width: 1, height: height)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            ui(Deck.line).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        .withRenderingMode(.alwaysTemplate)
    }
}
