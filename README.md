<img width="298" height="35" alt="Bildschirmfoto 2026-03-12 um 16 21 26" src="https://github.com/user-attachments/assets/8a9871b4-ed79-4b9f-9c6a-d3e516d33037" />
# BatteryPercent

BatteryPercent is a tiny macOS menu bar app that shows your MacBook’s battery level as a clean number in the status bar.

- Lightweight
- Right‑click menu with:
  - Launch at Login toggle
  - About / Website link
  - Uninstall
  - Quit


## Features

- **Minimal UI** – just the battery percentage in the menu bar.
- **Launch at Login** – optional toggle to start automatically when you log in (macOS 13+).
- **Open‑source** – written in Swift + SwiftUI, using `NSStatusItem` and `IOKit`.

## Requirements

- macOS 13.0 or later (for Launch at Login via `SMAppService`)
- Apple Silicon or Intel Mac

## Installation (DMG)

1. Download the latest `BatteryPercent.dmg` from the
   [Releases](https://github.com/ukuw/BatteryPercent/releases) page.
2. Open the DMG.
3. Drag **BatteryPercent.app** to your **Applications** folder.
4. Launch **BatteryPercent** from Applications.
5. The battery percentage will appear in the menu bar.

If macOS warns about an unidentified developer, open **System Settings → Privacy & Security** and allow the app to run.

## Building from source

1. Clone the repository:

   ```bash
   git clone https://github.com/ukuw/BatteryPercent.git
   cd BatteryPercent
