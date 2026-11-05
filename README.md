# Brief

A native iOS morning briefing app with a home screen widget. It brings important email, calendar events, weather and home server status into one daily summary, along with a to-do list.

Built with SwiftUI and WidgetKit. Includes 57 unit tests.

**This is a portfolio project.** The app gets its data from a personal backend that isn't in this repo, so it won't show live data without one.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cp signing.example.yml signing.yml
xcodegen generate
open Brief.xcodeproj
```

Set your own Apple team in `signing.yml` to run it on a device.

## Run the tests

```bash
xcodebuild test -scheme Brief \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Change the simulator name to one you have installed.

## License

[MIT](LICENSE)
