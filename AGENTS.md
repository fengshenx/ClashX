# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

ClashX is a macOS menu bar app that acts as a GUI for the [Clash](https://github.com/Dreamacro/clash) proxy core. It manages system proxy settings, provides a dashboard for connections, and supports rule-based traffic routing. The Clash core is written in Go and compiled into a C archive that the Swift app links against via cgo.

## Build Commands

```bash
# Install dependencies (Ruby gems + CocoaPods)
./install_dependency.sh

# Build the Go core (universal binary: arm64 + x86_64, requires Go 1.21+)
python3 ClashX/goClash/build_clash_universal.py

# Build the app (open workspace in Xcode)
open ClashX.xcworkspace
# Or from CLI:
xcodebuild -workspace ClashX.xcworkspace -scheme ClashX -configuration Debug build

# Lint check via Fastlane (used in CI for PRs)
bundle exec fastlane check
```

The project uses CocoaPods — always open `ClashX.xcworkspace`, not the `.xcodeproj`.

## Architecture

### Go-Swift Bridge

The most important architectural detail: the Clash proxy engine is Go code compiled to a static C archive (`goClash.a`). The bridge works as follows:

- **Go side**: `ClashX/goClash/main.go` exports ~14 C functions via cgo (`//export` directives) — `run()`, `initClashCore()`, `clashUpdateConfig()`, etc.
- **Swift side**: `ClashX-Bridging-Header.h` imports the generated `goClash.h`, making these functions callable from Swift.
- **Process info**: `ClashX/goClash/proccess.go` reads macOS kernel sysctls (`net.inet.tcp.pcblist_n`) to extract per-connection PID/port info.

### App Structure (MVC + RxSwift)

- **AppDelegate** (`ClashX/AppDelegate.swift`) — Central hub. Sets up the menu bar, manages app lifecycle, coordinates managers. This is the largest file (~950 lines) and the main entry point for understanding app flow.
- **Managers** (`ClashX/General/Managers/`) — Singletons handling system-level concerns:
  - `ConfigManager` — Reactive config state via RxSwift `BehaviorRelay`
  - `SystemProxyManager` — Toggles macOS system proxy via the privileged helper
  - `PrivilegedHelperManager` — XPC communication with `ProxyConfigHelper`
  - `RemoteConfigManager` — Auto-updating remote proxy configs
  - `MenuItemFactory` — Builds the status bar menu dynamically
- **ApiRequest** (`ClashX/General/ApiRequest.swift`) — HTTP (Alamofire) + WebSocket (Starscream) client for the Clash core's REST API (default port 8080). Handles traffic streaming, log streaming, proxy switching, config reload.
- **Models** (`ClashX/Models/`) — Codable structs: `ClashConfig`, `ClashProxy`, `ClashConnection`, `ClashProvider`, `ClashRule`
- **ProxyConfigHelper** (`ProxyConfigHelper/`) — Objective-C privileged helper daemon installed via SMJobBless. Handles actual system proxy configuration (HTTP, SOCKS, PAC) requiring elevated privileges.

### Key Dependencies

- **RxSwift/RxCocoa** — Reactive bindings throughout (config state, UI updates)
- **Alamofire** — HTTP client for Clash API
- **Starscream 3.1** — WebSocket for real-time traffic/log streams
- **Sparkle** — Auto-update framework
- **CocoaLumberjack** — Logging
- **SwiftyJSON** — JSON parsing

### macOS Compatibility

- Deployment target: macOS 10.14
- Dashboard/connections view requires macOS 10.15+ (`@available` checks)
- SMJobBless helper uses new authorization flow on macOS 13+, with legacy fallback

## Configuration Paths

- Default config dir: `~/.config/clash/`
- Main config: `config.yaml`
- GeoIP database: `Country.mmdb`
- Dashboard UI: bundled Yacd-meta web UI served locally

## No Tests

This project has no unit or integration test targets.
