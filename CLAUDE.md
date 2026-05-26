# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build (use -jobs 4 + wholemodule to avoid intermittent SwiftData @Model Identifiable issues)
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath /tmp/firstcc-build -jobs 4 SWIFT_COMPILATION_MODE=wholemodule

# Install to booted simulator
xcrun simctl install booted /tmp/firstcc-build/Build/Products/Debug-iphonesimulator/钱伲.app

# Launch
xcrun simctl launch booted com.qianey.app

# Reinstall + relaunch in one
xcrun simctl install booted /tmp/FirstCC-build/Build/Products/Debug-iphonesimulator/荡漾计然.app && xcrun simctl launch booted com.firstcc.app
```

Target: `荡漾计然`, scheme: `荡漾计然`, bundle ID: `com.firstcc.app`. No tests or linting configured yet.

## Architecture

**Stack:** SwiftUI (iOS 18+) + SwiftData + CloudKit (Phase 3). No third-party dependencies.

**DI pattern:** `AppContainer` is an `@ObservableObject` injected as `@EnvironmentObject` at the app root. It holds the `ModelContainer`, all service instances, and `@Published var currentLedger: Ledger?`. Views read `appContainer.currentLedger` to determine the active ledger.

**Service layer:** Protocol-based. Every domain has `XxxServiceProtocol` + `XxxServiceImpl`. Services are instantiated in `AppContainer.init()`. They operate on `ModelContext` (passed as parameter, never stored). Currently implemented: Ledger, Account, Transaction, Category, Template, Recurring, Member, Merchant, Project. Unimplemented (protocol only): Split, Budget, Lending, Installment, Currency, ExchangeRate, Sync, Export.

**MVVM:** Most screens have a ViewModel (`@StateObject`), but simpler list views use `@State` directly with service calls. ViewModels receive service instances and ledger from init.

**Data flow:**
- `AppContainer.currentLedger` is the single source of truth for "which ledger is active"
- Dashboard refreshes on `Notification.Name.transactionDidChange` and `onChange(of: currentLedger?.id)`
- LedgerSettingsView temporarily switches `currentLedger` on appear (so sub-views see the right data) and sheet's `onDismiss` restores it
- `UserDefaults.string(forKey: "currentLedgerID")` persists last-used ledger across restarts

## Key Design Decisions

**Signed amounts:** `Transaction.amount` is `Decimal`, positive for income, negative for expense. UI uses `abs(amount)` everywhere with color (green/red) to distinguish direction.

**Transfer model:** Two linked `Transaction` records with opposite signs, linked by `transferGroupId`.

**Refund model:** A new Transaction with `refundGroupId` pointing to original, optionally `refundAmount` for partial refunds.

**Reimbursement:** `Transaction.reimbursementStatusRaw` (none/pending/approved/reimbursed) + `reimbursedById` linking settlement income back to expenses. Reports filter out both reimbursable expenses and linked settlement income.

**Member vs Contact:** "联系人" (model `Member`) are tags for splitting/lending — they don't have accounts. Shared users (Phase 3 CKShare) are a separate concept.

**Settings structure:** Two-tier. SettingsView = app-level (ledger list, security, appearance). LedgerSettingsView = per-ledger config (accounts, categories, contacts, merchants, projects, templates, reimbursements).

## Patterns When Adding Features

**New management list view:** Follow the pattern in `AccountsManagementView` / `CategoryListView` — accept optional `ledger: Ledger?` with `effectiveLedger` computed property, use `onDismiss` on sheets to refresh, use `.task` for initial load.

**Sheet within a sheet:** Use `.task` not `.onAppear` for data loading — environment objects may not be ready in `.onAppear` for nested sheets. Call `loadData()` explicitly before setting picker sheet state to ensure data is available when picker appears.

**New service:** Add protocol in `Services/Protocols/`, implementation in `Services/Implementations/`, instantiate in `AppContainer.init()`.

**New model:** Add `@Model` class, update `AppContainer` schema, add to `project.pbxproj`.

## i18n

Source language: zh-Hans. `Localizable.xcstrings` (String Catalog, 249 entries) handles both Chinese and English. Enum `displayName` uses `NSLocalizedString(rawValue, comment: "")`. Stored strings (names, categories) use `Text(LocalizedStringKey(value))` for runtime lookup.
