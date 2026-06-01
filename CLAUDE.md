# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Simulator build (use -jobs 4 + wholemodule for build stability)
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath /tmp/firstcc-build -jobs 4 SWIFT_COMPILATION_MODE=wholemodule

# Device build (replace DEVICE_ID)
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 -destination "id=<DEVICE_ID>" -derivedDataPath /tmp/firstcc-build-device -jobs 4 SWIFT_COMPILATION_MODE=wholemodule

# Install to booted simulator
xcrun simctl install booted /tmp/firstcc-build/Build/Products/Debug-iphonesimulator/钱伲.app

# Launch simulator
xcrun simctl launch booted com.qianey.app

# Install to real device
xcrun devicectl device install app /tmp/firstcc-build-device/Build/Products/Debug-iphoneos/钱伲.app --device <DEVICE_ID>

# Launch real device
xcrun devicectl device process launch --device <DEVICE_ID> com.qianey.app

# List connected devices
xcrun devicectl list devices
```

Target: `钱伲`, scheme: `钱伲`, bundle ID: `com.qianey.app`, container: `iCloud.com.qianey.v2`. No tests or linting configured yet.

## Architecture

**Stack:** SwiftUI (iOS 26+) + CoreData (`NSPersistentCloudKitContainer`) + CloudKit. No third-party dependencies.

**DI pattern:** `AppContainer` is an `ObservableObject` injected as `@EnvironmentObject` at the app root. It holds `CoreDataStack` (which owns `NSPersistentCloudKitContainer`), all service instances, and `@Published var currentLedger: Ledger?`. Views read `appContainer.currentLedger` to determine the active ledger.

**Service layer:** Protocol-based. Every domain has `XxxServiceProtocol` + `XxxServiceImpl`. Services are instantiated in `AppContainer.init()`. They operate on `NSManagedObjectContext` (passed as parameter, never stored). All services are implemented: Ledger, Account, Transaction, Category, Template, Recurring, Member, Merchant, Project, Split, Budget, BankOCR, CreditCardStatement, Reconciliation, Currency, ExchangeRate, Export, Sync.

**Models:** `NSManagedObject` subclasses in `Models/CoreData/`. CoreData schema in `FirstCC.xcdatamodeld`. To add a new entity: create the `NSManagedObject` subclass, add the entity to `xcdatamodeld` in Xcode, and update `project.pbxproj`.

**Data flow:**
- `AppContainer.currentLedger` is the single source of truth for "which ledger is active"
- Dashboard refreshes on `Notification.Name.transactionDidChange` and `onChange(of: currentLedger?.id)`
- `UserDefaults.string(forKey: "currentLedgerID")` persists last-used ledger across restarts

## Sharing (CKShare)

Sharing flow: owner taps Button → `createShareAndShow()` → `CoreDataStack.createShareForLedger()` → `CloudSharingView` (wraps `UICloudSharingController`).

`createShareForLedger` uses the standard approach:
```swift
container.share([ledger], to: nil)  // only pass root object, CoreData cascades to children
```
Do NOT use `CKShareTransferRepresentation` / `ShareLink` — that approach ties async share creation to the system share sheet lifecycle and is unreliable. Do NOT pre-create CKShare via raw CloudKit API — the two-step workaround was an over-engineering dead end.

30-second timeout via `withThrowingTaskGroup` protects against `container.share()` hangs (FB16908476).

`initializeCloudKitSchema()` is commented out in `loadStores()` — it caused iOS watchdog kills on DEV device builds. Only re-enable if schema changes in development and you need to push to CloudKit Development environment.

## Key Design Decisions

**Signed amounts:** `Transaction.amount` is `Decimal`, positive for income, negative for expense. UI uses `abs(amount)` with color (green/red) to distinguish direction.

**Transfer model:** Two linked `Transaction` records with opposite signs, linked by `transferGroupId`.

**Refund model:** A new Transaction with `refundGroupId` pointing to original, optionally `refundAmount` for partial refunds.

**Reimbursement:** `Transaction.reimbursementStatusRaw` (none/pending/approved/reimbursed) + `reimbursedById` linking settlement income back to expenses. Reports filter out both reimbursable expenses and linked settlement income.

**Member vs User:** "联系人" (model `Member`) are tags for splitting/lending — they don't have accounts. Shared users (CKShare participants) are a separate concept tracked via `User` entity.

**Settings structure:** Two-tier. SettingsView = app-level (ledger list, security, appearance). LedgerSettingsView = per-ledger config (accounts, categories, contacts, merchants, projects, templates, budgets, export).

## Patterns When Adding Features

**New management list view:** Follow the pattern in `AccountsManagementView` / `CategoryListView` — accept optional `ledger: Ledger?` with `effectiveLedger` computed property, use `onDismiss` on sheets to refresh, use `.task` for initial load.

**Sheet within a sheet:** Use `.task` not `.onAppear` for data loading — environment objects may not be ready in `.onAppear` for nested sheets. Call `loadData()` explicitly before setting picker sheet state.

**New service:** Add protocol in `Services/Protocols/`, implementation in `Services/Implementations/`, instantiate in `AppContainer.init()`.

**New model entity:** Add `NSManagedObject` subclass in `Models/CoreData/`, add entity to `FirstCC.xcdatamodeld` in Xcode, add files to `project.pbxproj`.

**Sharing changes:** Keep it simple. Use `container.share([rootObject], to: nil)`. Do not introduce raw CKShare APIs, `CKShareTransferRepresentation`, or multi-step workarounds unless proven necessary after exhausting all standard-API debugging (schema deployment, store state, actor isolation).

## i18n

Source language: zh-Hans. `Localizable.xcstrings` (String Catalog, 249 entries) handles both Chinese and English. Enum `displayName` uses `NSLocalizedString(rawValue, comment: "")`. Stored strings (names, categories) use `Text(LocalizedStringKey(value))` for runtime lookup.
