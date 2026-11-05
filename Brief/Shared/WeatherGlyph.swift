import Foundation

/// The hub sends weather as words ("Sunny", "Partly cloudy", "Light snow").
/// This picks an SF Symbol for them; anything unrecognised gets a thermometer
/// rather than a wrong sky.
enum WeatherGlyph {
    static func symbol(for summary: String) -> String {
        let s = summary.lowercased()
        if s.contains("thunder") || s.contains("storm") { return "cloud.bolt.rain.fill" }
        if s.contains("snow") || s.contains("flurr") || s.contains("sleet") { return "cloud.snow.fill" }
        if s.contains("rain") || s.contains("shower") || s.contains("drizzle") { return "cloud.rain.fill" }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") { return "cloud.fog.fill" }
        if s.contains("wind") { return "wind" }
        if s.contains("partly") || s.contains("mostly sunny") { return "cloud.sun.fill" }
        if s.contains("cloud") || s.contains("overcast") { return "cloud.fill" }
        if s.contains("clear") || s.contains("sun") { return "sun.max.fill" }
        return "thermometer.medium"
    }
}
