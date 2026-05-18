---
name: build-install
description: Build the app and install to the booted iOS simulator
user-invocable: true
---

# Build & Install

Build FirstCC (荡漾计然) and install to the booted simulator.

## Steps

1. Build:
```bash
xcodebuild -project FirstCC.xcodeproj -scheme 荡漾计然 -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath /tmp/firstcc-build -jobs 4 SWIFT_COMPILATION_MODE=wholemodule
```

2. If build succeeds, install and launch:
```bash
xcrun simctl install booted /tmp/firstcc-build/Build/Products/Debug-iphonesimulator/荡漾计然.app && xcrun simctl launch booted com.firstcc.app
```

3. If build fails, report the errors and do not attempt to install.
