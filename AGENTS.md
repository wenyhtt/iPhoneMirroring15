# Repository Guidelines

This repository contains a native macOS SwiftUI viewer for TrollVNC, including devices running iOS 15.

## Project Structure

- `Sources/iPhoneMirroring15/` holds the Swift application: `main.swift` configures the app and window, `ContentView.swift` contains the interface and screen input, `AppModel.swift` manages connection state and discovery, and `RFBConnection.swift` implements the VNC protocol.
- `Info.plist` contains app metadata and permissions. `Makefile` builds the app. `README.md` documents usage and compatibility.
- There is currently no test target or separate assets directory. Build products in `.build/` and `build/` are ignored.

## Build and Run

Requires macOS 14 or newer and Xcode Command Line Tools.

```sh
make app
open build/iPhoneMirroring15.app
make clean
```

`make app` compiles and signs the local app bundle; `make clean` removes generated build files. There is no automated test command at present.

## Style and Changes

Use four spaces for Swift indentation. Name types in `UpperCamelCase` and functions, properties, and enum cases in `lowerCamelCase`. Keep SwiftUI presentation in `ContentView.swift`, connection state in `AppModel.swift`, and RFB networking in `RFBConnection.swift`. Avoid adding dependencies for functionality available in AppKit, SwiftUI, or the existing implementation.

## Testing

For code changes, run `make app` and launch the app for a manual check. For connection changes, verify discovery and manual host/port connection when a TrollVNC device is available. Do not commit generated bundles or build caches.

## Commits and Pull Requests

This repository has no prior commit history to establish a message convention. Use a short imperative subject, such as `Fix VNC reconnect handling`. A pull request should summarize the change, include build results and manual verification steps, and attach a screenshot for visible interface changes.

## Security

VNC does not encrypt the screen stream. Keep connections on a trusted LAN or tunnel, store credentials through Keychain, and never commit real passwords or private device addresses.
