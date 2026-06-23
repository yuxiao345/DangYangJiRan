# 硬编码中文字符串分析与解决方案

## 现状

App 源语言为 zh-Hans，使用 `Localizable.xcstrings` (String Catalog) 管理本地化。当前有 **137+** 处硬编码中文，英文系统下大部分显示中文。

## 分类与修复策略

### 类型 A：`Text("中文")` 字面量但不在 catalog（~69 处）

**影响：** 英文系统下显示中文（SwiftUI 查 catalog 失败后 fallback 到原文）

**示例：** `"净资产"`、`"暂无交易记录"`、`"此操作不可撤销，确定要删除此交易吗？"`、`"CNY (人民币)"`

**修复：** 逐条加到 `Localizable.xcstrings`，配上英文翻译

**优先级：** 中 | **工作量：** 逐条翻译，每条约 1 分钟

---

### 类型 B：纯 `String` 变量用作错误/状态信息（~40 处）

**影响：** 英文系统下永远显示中文（不走 SwiftUI 本地化系统）

**示例：**

```swift
// AppContainer.swift
syncStatus = .error("接收开始")
syncStatus = .error("共享失败：\(error.localizedDescription)")

// BankOCRServiceImpl.swift
return "图片中未识别到文字，请确保截图清晰"

// AddEditAccountView.swift
errorMessage = "同名账户「\(name)」已存在"
```

**修复：** 改用 `String(localized:)` 或 `NSLocalizedString`，同时加到 catalog

**优先级：** 高 | **工作量：** 约 40 处，每处改代码 + 加翻译

---

### 类型 C：视图辅助函数的 `label: String` 参数（~15 处）

**影响：** `Text(label)` 不走本地化（只有 `Text("字面量")` 才会）

**示例：**

```swift
creditInfoRow(label: "总额度")
pickerRow(label: "分类")
budgetSpendingLine(label: "本期")
```

**修复：** 将参数类型从 `String` 改为 `LocalizedStringKey`，或调用时用 `Text("label")` 而非 `Text(label)`

**优先级：** 中 | **工作量：** 改函数签名，约 15 处

---

### 类型 D：日期格式字符串（~5 处）

**影响：** 英文系统下月份显示中文（如 "3月"）

**示例：** `"M月d日"`、`"yyyy年M月"`

**修复：** 使用 `Date.FormatStyle` 或 `date.formatted(date: .abbreviated, time: .omitted)` 替代硬编码格式

**优先级：** 低 | **工作量：** 改 DateFormatter 调用，约 5 处

---

### 类型 E：自定义函数中拼接中文（~15 处）

**影响：** 英文系统下显示中文

**示例：**

```swift
// ReportViewModel.swift
return "支出分类"
return "未分类"

// AccountRowView.swift
return "待还款"
return "借贷"

// ReportPeriod.label
"本月"、"近3月"、"近6月"、"近1年"、"近3年"
```

**修复：** 改为 `NSLocalizedString` 或 `String(localized:)`，加到 catalog

**优先级：** 中 | **工作量：** 约 15 处

---

## 建议实施顺序

1. **先修类型 B（高优先级）**——错误/状态信息，影响最大
2. **再修类型 A**——`Text` 字面量，逐条加 catalog
3. **修类型 C**——改函数签名
4. **修类型 E**——ViewModel/String 返回值
5. **最后修类型 D**——日期格式

## 预计总工时

| 类型 | 数量 | 预计工时 |
|------|------|---------|
| A: Text 字面量 | ~69 | ~2h |
| B: String 错误/状态 | ~40 | ~1.5h |
| C: 函数参数 | ~15 | ~1h |
| D: 日期格式 | ~5 | ~0.5h |
| E: 自定义拼接 | ~15 | ~0.5h |
| **合计** | **~144** | **~5.5h** |
