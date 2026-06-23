# Mac 版 UI/UX 设计规范

> 基于 Apple macOS Human Interface Guidelines、WWDC 2026 (macOS 27 Golden Gate) 更新，以及优秀 Mac 软件（Things 3、Bear、Ulysses）的实践。
> 最后更新：2026-06-23

---

## 一、设计原则

| 原则 | 说明 |
|------|------|
| **内容密度优先** | macOS 比 iOS 信息密度高，控件更紧凑。正文 13pt vs iOS 17pt |
| **留白分隔，非卡片嵌套** | macOS 惯例用空白分隔区块，减少卡片堆叠 |
| **Hover 状态必须** | 鼠标悬停反馈是 macOS 基本交互，iOS 无此需求 |
| **键盘可达** | 所有控件必须支持 Tab 导航和全键盘操作 |
| **右对齐表单标签** | 标签右对齐 + 尾部冒号，字段左对齐统宽 |
| **Liquid Glass 2.0** | 系统级透明度滑块，零代码适配，Xcode 27 重编译即更新 |
| **Dynamic Type 不支持** | macOS 无动态字体缩放，所有 token 用 `fixedSize` |

---

## 二、字体系统

### 字体族

| 用途 | 字体 | 与 iOS 一致 |
|------|------|:--:|
| UI 文本（正文/标题/标签） | **Space Grotesk** | ✅ |
| 数据展示（金额/标签/数字） | **JetBrains Mono** | ✅ |
| SF Symbols 图标 | San Francisco (系统) | ✅ |

### 字号层级 — Space Grotesk（UI）

| Token | Mac 字号 | iOS 字号 | 用途 |
|-------|:------:|:------:|------|
| `designDisplay` | 32pt Bold | 48pt Bold | 仪表盘大数字（极少用） |
| `designHeadlineLarge` | 22pt SemiBold | 40pt SemiBold | 页面主标题 |
| `designHeadlineMedium` | 16pt SemiBold | 24pt SemiBold | 区块标题 / sheet 标题 |
| `designBodyLarge` | 15pt Regular | 18pt Regular | 强调正文 |
| **`designBodyMedium`** | **13pt Regular** | 16pt Regular | 🔑 **标准正文（macOS HIG 基准）** |
| `designBodySmall` | 12pt Regular | 14pt Regular | 辅助信息 / Toggle 标签 |
| `designBodyCaption` | 11pt Regular | 12pt Regular | 元数据 / 脚注 / 芯片文字 |

### 字号层级 — JetBrains Mono（数据）

| Token | Mac 字号 | iOS 字号 | 用途 |
|-------|:------:|:------:|------|
| `designLabel` | 11pt Bold | 12pt Bold | 区块标签（"模板"、"分类"等） |
| `designLabelSmall` | 10pt Bold | 10pt Bold | 小标签（不变） |
| `designMonoData` | 13pt Medium | 14pt Medium | 内联金额 |
| `designMonoDataSmall` | 12pt Medium | 12pt Medium | 列表金额 |
| `designMonoDataCompact` | 10pt Medium | 11pt Medium | 密集数据 / 图表行 |

### 特殊尺寸（不通过 token 管理）

| 元素 | 字号 | 字体 |
|------|:--:|------|
| 金额输入数字 | 24pt | JetBrainsMono-Medium |
| 金额输入符号 | 20pt | JetBrainsMono-Medium |
| SF Symbol 芯片图标 | 14pt | 系统 SF Symbol |

### 关键规则

- **全部使用 `fixedSize`** — macOS 不支持 Dynamic Type，`.relativeTo` 无效
- 不要使用 `.system(size:)` 硬编码非 SF Symbol 的文字 — 用 token
- 不要使用 `.headline` / `.body` 等语义字体 — 用 token

---

## 三、间距系统

### 8pt 网格

所有间距为 8 的倍数（最小 4pt 用于紧密场合）。

| Token | 值 | 用途 |
|-------|:--:|------|
| `tight` | 4pt | 图标+标签紧贴 |
| `standard` | 8pt | 表单行间距、按钮组间距 |
| `group` | 16pt | 表单区块间 |
| `section` | 24pt | 功能区段间 |
| `window-margin` | 20pt | 窗口内容边缘留白 |

### 表单行间距

- 标签到字段：8pt
- 行到行：12-16pt
- 区块标题到第一个控件：8pt
- 区块间：24pt

---

## 四、控件尺寸

| 控件 | 高度 | 说明 |
|------|:--:|------|
| 标准控件（TextField、Button、Picker） | **22pt** | macOS 标准 |
| 大号按钮（主要操作） | **28pt** | 保存/确认等 |
| 小型控件（Toggle、Checkbox） | 14pt | 选项开关 |
| 最小可点击区域 | **24×24pt** | （对比 iOS 44×44pt） |

---

## 五、表单布局

### 标准模式：右对齐标签

```
         标签名：[_______________]
    更长的标签名：[_______________]
       简短标签：[_______________]
```

- 标签右对齐 + 尾部冒号
- 输入区左对齐、统一宽度
- SwiftUI 可用 `LabeledContent` 实现

### 分组

- **用留白，不是卡片** — 24pt 垂直间距分隔功能组
- 避免玻璃卡片嵌套玻璃卡片
- 如需边框，用细分隔线或 `.grouped` FormStyle

### Sheet / 弹出窗口

- 最小宽度：460pt
- 标准 sheet：500×350pt
- 设置面板：580×450pt

---

## 六、颜色与状态

### Liquid Glass

- 使用现有 `.glassCard()` 修饰符
- Xcode 27 重编译后自动获得 Liquid Glass 2.0 外观
- 用户可通过系统滑块调整透明度强度
- 对比度必须足够 — 按钮和内容层之间区隔清晰

### Hover 状态（macOS 必需）

```
- 按钮 hover：微调背景亮度或加描边
- 列表行 hover：浅色高亮
- 可点击元素：hover 时切换光标为 pointer
```

### 焦点环

- Tab 导航切换焦点时，控件周围显示 3px accent 色描边
- 默认由 SwiftUI 处理

---

## 七、窗口规范

| 窗口类型 | 默认 (w×h) | 最小 (w×h) |
|----------|:--:|:--:|
| 主内容（三栏） | 900×650 | 800×500 |
| 设置/偏好 | 600×450 | 580×400 |
| Sheet | 500×350 | — |
| 侧边栏宽度 | 250pt | 200pt min / 350pt max |

---

## 八、与 iOS 差异速查

| 维度 | iOS | macOS |
|------|-----|-------|
| 正文基准 | 17pt | **13pt** |
| 控件高度 | ~44pt | **22pt** |
| 最小触摸/点击 | 44×44pt | **24×24pt** |
| Dynamic Type | ✅ 支持 | ❌ 不支持（用 `fixedSize`） |
| 表单标签 | 顶部左对齐 | 右对齐 + 冒号 |
| 分组方式 | 卡片 | 留白 |
| Hover 状态 | 无 | 必须 |
| 键盘导航 | 有限 | 必须完整支持 |

---

## 九、WWDC 2026 兼容性清单

| 项目 | 状态 | 说明 |
|------|:--:|------|
| Liquid Glass 2.0 | ✅ 兼容 | `.glassCard()` 自动适配 |
| `UIDesignRequiresCompatibility` 移除 | ✅ 未使用 | 不影响 |
| macOS 27 不再支持 Intel | ✅ | 仅 Apple Silicon |
| `@State` 宏化 | ⚠️ 需检查 | 清理声明+init双重赋值 |
| `ContentBuilder` | 🟢 可采纳 | 编译速度提升 |

---

## 十、设计检查清单（修改 Mac 视图前必查）

- [ ] 所有文字使用设计 token，无 `.system(size:)` 硬编码（SF Symbol 除外）
- [ ] 正文 13pt (`designBodyMedium`)，标签 11pt (`designBodyCaption`)
- [ ] 区块标题 11pt Bold (`designLabel`)
- [ ] 全部 token 为 `fixedSize`（非 `relativeTo`）
- [ ] 间距为 8 的倍数（最小 4pt）
- [ ] 控件高度 22pt
- [ ] 避免卡片嵌套卡片
- [ ] 有 hover 反馈
- [ ] 表单标签右对齐
- [ ] Tab 键可导航
