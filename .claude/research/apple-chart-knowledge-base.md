# Apple Swift Charts — 项目知识库

> 为 Qianeymac 报表功能建设的技术参考文档。
> 基于 Apple HIG + Swift Charts 官方文档，补充大模型在 Apple 最新 Chart API 方面的知识欠缺。

---

## 一、Mark 类型速查

| Mark | 用途 | 关键参数 | 最低版本 |
|------|------|---------|---------|
| `BarMark` | 柱状图、直方图、甘特图 | `x`, `y`, `width`, `height` | iOS 16 / macOS 13 |
| `LineMark` | 折线趋势图 | `x`, `y`, `series` | iOS 16 / macOS 13 |
| `PointMark` | 散点图、关键数据点标记 | `x`, `y`, `symbol` | iOS 16 / macOS 13 |
| `AreaMark` | 面积图（趋势+体量感知） | `x`, `y`, `series` | iOS 16 / macOS 13 |
| `RectangleMark` | 热力图、范围带、块图 | `xStart`, `xEnd`, `yStart`, `yEnd` | iOS 16 / macOS 13 |
| `RuleMark` | 参考线（均值、目标、阈值） | `x` 或 `y` | iOS 16 / macOS 13 |
| `SectorMark` | 饼图/甜甜圈图 | `angle`, `innerRadius`, `outerRadius` | iOS 17 / macOS 14 |
| `LinePlot` / `AreaPlot` / `PointPlot` | 批量数据绘图（无需 ForEach） | 数组直接传入 | iOS 18 / macOS 15 |
| `SurfacePlot` | **3D 数学曲面** (Chart3D 专用) | `(Double, Double) -> Double` 闭包 | iOS 26 / macOS 26 |
| `Chart3D` | **3D 图表容器**，替代 Chart | Z 轴数据 + 旋转手势 | iOS 26 / macOS 26 |

---

## 二、常用 Modifier

### 轴配置
```swift
.chartXAxis {
    AxisMarks(values: .stride(by: .month)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.month(.abbreviated))
    }
}
.chartXAxis(.hidden)  // 隐藏轴
```

### 图例
```swift
.chartLegend(position: .bottom, alignment: .center)
.chartLegend(.hidden)  // 单系列时自动隐藏
```

### 缩放与滚动 (iOS 17+ / macOS 14+)
```swift
.chartScrollableAxis(.horizontal)
.chartXVisibleDomain(length: 3600 * 24 * 30)  // 30天可见窗口
```

### 选中交互 (iOS 17+ / macOS 14+)
```swift
@State private var selectedX: Date?
Chart { ... }
    .chartXSelection(value: $selectedX)
// SectorMark 用 .chartAngleSelection(value: $selectedAngle)
```

### 标记注解 (iOS 17+ / macOS 14+)
```swift
PointMark(...)
    .annotation(position: .top) {
        Text("Peak: \(value)").font(.caption)
    }
```

### 比例尺
```swift
.chartXScale(domain: startDate...endDate)
.chartYScale(domain: 0...maxValue)
```

### 样式
```swift
.lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
.interpolationMethod(.catmullRom)  // 平滑曲线
.interpolationMethod(.monotone)    // 保持单调性
.interpolationMethod(.stepCenter)  // 阶梯线
```

### 堆叠
```swift
BarMark(...)
    .position(by: .value("Type", type))  // 分组/堆叠
// 默认 .automatic → 堆叠; 用 .dodge 做并排
```

### ChartProxy（坐标转换）
```swift
.chartOverlay { proxy in
    GeometryReader { geometry in
        // proxy.position(for:) → 数据值转屏幕坐标
        // proxy.value(at:) → 屏幕坐标转数据值
    }
}
```

---

## 三、Chart3D — iOS 26 / macOS 26+ (WWDC 2025)

> **Session:** "Bring Swift Charts to the Third Dimension" (WWDC 2025-313)
> **平台:** iOS 26+, macOS 26+, visionOS 26+

### Chart3D 容器
```swift
Chart3D {
    ForEach(data) { point in
        PointMark(
            x: .value("X", point.x),
            y: .value("Y", point.y),
            z: .value("Z", point.z)  // 新增 Z 轴
        )
    }
}
```

### 3D 专用 Mark
| Mark | 说明 |
|------|------|
| `PointMark(x:y:z:)` | 3D 散点 |
| `RuleMark(x:y:z:)` | 3D 参考线 |
| `RectangleMark(x:y:z:)` | 3D 矩形区域 |
| `SurfacePlot(x:y:z:) { x, z in ... }` | **新增** — 数学曲面，接受 `(Double, Double) -> Double` |

> ⚠️ BarMark、LineMark、SectorMark、AreaMark **不支持** 3D，仅用于 2D Chart。

### SurfacePlot 示例
```swift
Chart3D {
    SurfacePlot(x: "X", y: "Y", z: "Z") { x, z in
        (sin(5 * x) + sin(5 * z)) / 2
    }
    .foregroundStyle(.heightBased)  // 按高度着色
}
```

### 相机控制
```swift
// 预设姿态
.chart3DPose(.default)   // 默认 3D 视角
.chart3DPose(.front)     // 正面（类 2D）
.chart3DPose(.back)      // 背面
.chart3DPose(.left)      // 左侧
.chart3DPose(.right)     // 右侧

// 自定义姿态
.chart3DPose(Chart3DPose(
    azimuth: .degrees(20),
    inclination: .degrees(7)
))

// 投影模式
.chart3DCameraProjection(.orthographic)  // 默认 — 物体大小不随深度变化
.chart3DCameraProjection(.perspective)   // 透视 — 远小近大
```

### SurfacePlot 着色模式
```swift
.foregroundStyle(.heightBased)   // 按高度渐变
.foregroundStyle(.normalBased)   // 按曲面法线方向着色
.foregroundStyle(LinearGradient(colors: [.red, .blue]))
.foregroundStyle(EllipticalGradient(colors: [.red, .orange, .yellow]))
```

### 组合 2D + 3D
```swift
Chart3D {
    // 3D 散点
    ForEach(points) { p in
        PointMark(x: .value("X", p.x), y: .value("Y", p.y), z: .value("Z", p.z))
    }
    // 叠加 3D 曲面
    SurfacePlot(x: "X", y: "Y", z: "Z") { x, z in
        regressionModel(x, z)
    }
    .foregroundStyle(.gray.opacity(0.5))
}
```

### 内置手势
- 单指/鼠标拖拽旋转
- 自动吸附到侧面（呈现 2D 视图）
- visionOS 支持手部追踪 + 空间音频

### 何时用 3D
- 数据本身是三维的（如 x/y/z 空间坐标）
- 数据的**形状**比精确数值更重要
- 需要交互式探索
- 不适用于：精确读数、饼图占比、简单趋势线

---

## 四、HIG 图表设计规范

### 选型原则
- **柱状图:** 比较离散值 → 必须从 0 起始
- **折线图:** 展示趋势 → 可以从非 0 起始（但要标注）
- **面积图:** 强调变化体量
- **饼图/甜甜圈:** 占比 → 限制 3-5 个扇区
- **散点图:** 相关性分析
- **热力图:** 二维数据密度

### 颜色规范
- 系统色自动适配 Light/Dark
- `foregroundStyle(by: .value(...))` 使用系统无障碍调色板
- 不可仅靠颜色区分 — 需配合标签、符号、线型
- 选中态用高饱和/微缩放
- 自定义颜色需提供 light/dark 双变体

### 可访问性
- `.chartAccessibilityLabel("描述")` — 图表整体概述
- 每个 Mark 可设 `.accessibilityLabel` / `.accessibilityValue`
- Swift Charts 自动生成音频图 (Audio Graphs)
- 尊重 `.accessibilityReduceMotion`

### 平台差异
| 方面 | macOS | iOS |
|------|-------|-----|
| 主交互 | 指针悬停、右键菜单、键盘导航 | 触摸、长按、滑动手势 |
| 空间 | 宽屏，可展示更密集数据 | 竖屏，需精简 |
| 窗口 | 可变大小，图表需响应式 | 全屏/SplitView |
| 精度 | 可展示更多轴标签和数值 | 轴标签需简短 |

---

## 五、常见图表模式

### 1. 甜甜圈图 + 中心标签
```swift
Chart {
    ForEach(data) { item in
        SectorMark(
            angle: .value("Amount", item.amount),
            innerRadius: .ratio(0.55),
            outerRadius: .automatic,
            angularInset: 1
        )
        .foregroundStyle(by: .value("Category", item.category))
    }
}
.chartAngleSelection(value: $selectedAngle)
```

### 2. 组合图（柱状 + 折线 + 参考线）
```swift
Chart {
    BarMark(x: .value("Month", m), y: .value("Expense", expense))
    LineMark(x: .value("Month", m), y: .value("Income", income))
        .foregroundStyle(.green)
    RuleMark(y: .value("Average", avg))
        .foregroundStyle(.red.opacity(0.5))
        .lineStyle(StrokeStyle(dash: [4]))
}
```

### 3. 热力图（RectangleMark）
```swift
Chart {
    ForEach(data) { cell in
        RectangleMark(
            xStart: .value("Start", cell.x),
            xEnd: .value("End", cell.x + 1),
            yStart: .value("Y0", cell.y),
            yEnd: .value("Y1", cell.y + 1)
        )
        .foregroundStyle(by: .value("Value", cell.value))
    }
}
```

### 4. 堆叠面积图
```swift
Chart {
    ForEach(series) { s in
        AreaMark(x: .value("Date", s.date), y: .value("Value", s.value))
            .foregroundStyle(by: .value("Category", s.category))
    }
}
```

### 5. 滚动时间序列 + 选中注解 (iOS 17+)
```swift
Chart {
    ForEach(data) { d in
        LineMark(x: .value("Date", d.date), y: .value("Value", d.value))
    }
    if let selected {
        RuleMark(x: .value("Selected", selected))
        PointMark(x: .value("Selected", selected),
                   y: .value("Value", data.first { $0.date == selected }!.value))
            .annotation { Text("...") }
    }
}
.chartXSelection(value: $selected)
.chartScrollableAxis(.horizontal)
```

---

## 六、当前项目现有 Charts 实现

### iOS CategoryPieChartView
- `SectorMark` 甜甜圈（`innerRadius: .ratio(0.55)`, `angularInset: 1`）
- `.chartAngleSelection(value:)` 实现扇区点击
- 中心覆盖文字（分类名 + 总额）
- 下方列表展示分类明细（色块 + 名称 + 金额 + 百分比 + PixelProgressBar）
- 支持 3 级下钻（根分类 → 子分类 → 叶子级交易列表）

### iOS TrendChartView
- **未使用 Swift Charts** — 完全自定义的 GeometryReader + HStack
- 水平堆叠柱状图（收入绿、支出红、结余蓝）
- 手动计算 bar 宽度和坐标
- 月份标签、年度分隔线、图例切换

### 共享 ReportViewModel
- `@Observable` (iOS 17+ Observation)
- 直接 Core Data NSFetchRequest（不经过 Service 层）
- 支出分类树: `CategoryExpenseItem`（最多 3 层嵌套）
- 趋势数据: 按月聚合的 `TrendDataPoint`
- 支持 6 个时间周期: 本月/近3月/近6月/近1年/近2年/近3年

---

## 七、版本能力对照

| 能力 | iOS 16 / macOS 13 | iOS 17 / macOS 14 | iOS 18 / macOS 15 | iOS 26 / macOS 26 |
|------|:---:|:---:|:---:|:---:|
| 基础 Mark (Bar/Line/Point/Area/Rectangle/Rule) | ✅ | ✅ | ✅ | ✅ |
| SectorMark (饼/甜甜圈) | ❌ | ✅ | ✅ | ✅ |
| chartXSelection / chartAngleSelection | ❌ | ✅ | ✅ | ✅ |
| chartScrollableAxis | ❌ | ✅ | ✅ | ✅ |
| .annotation (Mark 注解) | ❌ | ✅ | ✅ | ✅ |
| @Observable 宏 | ❌ | ✅ | ✅ | ✅ |
| LinePlot / AreaPlot (批量) | ❌ | ❌ | ✅ | ✅ |
| Plot 协议 + PlotView | ❌ | ❌ | ✅ | ✅ |
| chartSelection(point:) | ❌ | ❌ | ✅ | ✅ |
| **Chart3D 容器** | ❌ | ❌ | ❌ | ✅ |
| **SurfacePlot** | ❌ | ❌ | ❌ | ✅ |
| **3D PointMark / RuleMark / RectangleMark** | ❌ | ❌ | ❌ | ✅ |
| **chart3DPose / chart3DCameraProjection** | ❌ | ❌ | ❌ | ✅ |
| **heightBased / normalBased 着色** | ❌ | ❌ | ❌ | ✅ |

> **项目目标:** iOS 26 / macOS 27 — 包含 WWDC 2025 的 Chart3D 全部能力。WWDC 2026 无新增 Chart API。
> **macOS 27 "Golden Gate":** Uniform Liquid Glass 设计系统自动应用，无需手动适配。

---

## 八、外部参考

- Apple HIG — Charting Data: https://developer.apple.com/design/human-interface-guidelines/charting-data
- Swift Charts Framework: https://developer.apple.com/documentation/charts
- WWDC 2022 — Hello Swift Charts: https://developer.apple.com/videos/play/wwdc2022/10136/
- WWDC 2023 — Explore pie charts and interactivity: https://developer.apple.com/videos/play/wwdc2023/10037/
- WWDC 2024 — Swift Charts: Vectorized and function plots: https://developer.apple.com/videos/play/wwdc2024/10156/
- WWDC 2025 — Bring Swift Charts to the Third Dimension: https://developer.apple.com/videos/play/wwdc2025/313/
- 3D Charts 实践: https://artemnovichkov.com/blog/cook-up-3d-charts-with-swift-charts
- macOS 27 Golden Gate — Uniform Liquid Glass 自动适配，无需额外代码
