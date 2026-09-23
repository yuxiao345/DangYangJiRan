##
# Mac 端报表功能规划

> 2026-06-28 | 基于 Apple Swift Charts + macOS 27 "Golden Gate"
> 关联文档: [[apple-chart-knowledge-base]] (已更新至 WWDC 2026)
> 
> **版本更新:** WWDC 2025 引入 Chart3D（3D 图表），WWDC 2026 无新增 Chart API。
> macOS 27 "Golden Gate" 采用 Uniform Liquid Glass 设计系统，自动适配。Intel Mac 已完全放弃。

---

> ## ⚠️ 实施状态（2026-09-24 实测更正）
>
> **§七 路线图里的复选框已全部过期**（原本全是 `[ ]`，但 Phase 1/2 其实早已完成）。
> 实际状态：**6 大报表全部落地**，`Qianeymac/Views/Reports/` 共 12 个文件。
> 唯一未做的是 **Phase 4 的「macOS HIG 审查」**（与上架清单 P0-6 同一项）。
>
> 本文已从「规划」转为**历史设计记录** —— 需要「现在有什么报表」请看
> `.claude/plans/release-checklist.md` 与 `CLAUDE.md` 的「Mac 报表架构」一节。

---

## 一、个人/家庭财务分析 — 需求梳理

### 核心财务问题（用户真正关心的）

| # | 问题 | 对应报表 |
|---|------|---------|
| 1 | 我的钱花去哪了？ | 支出分类分析 |
| 2 | 收入和支出趋势如何？ | 现金流趋势 |
| 3 | 我的净资产在增长吗？ | 净资产时间线 |
| 4 | 预算执行得怎么样？ | 预算 vs 实际 |
| 5 | 钱都放在哪些账户？ | 资产配置 |
| 6 | 这个月哪天花得最多？ | 日历热力图 |
| 7 | 和上月/去年同期比怎么样？ | 期间对比 |

### 家庭场景特有需求
- 多人账本 → 需要按成员筛选/对比
- 多币种 → 需要汇率换算后的统一视图
- 共享账本 → 需要区分"我的支出" vs "家庭支出"

---

## 二、Mac 报表体系设计

### 报表总览架构

```
┌──────────────────────────────────────────────────────┐
│  报表  (NavigationSplitView)                         │
├───────────┬──────────────────────────────────────────┤
│           │                                          │
│  报表类型  │         报表详情（大画布）                  │
│           │                                          │
│  ▸ 总览    │   ┌─────────────────────────────────┐   │
│  ▸ 现金流   │   │                                 │   │
│  ▸ 支出分析 │   │   交互式 Chart + 摘要面板         │   │
│  ▸ 净资产   │   │                                 │   │
│  ▸ 预算执行 │   │                                 │   │
│  ▸ 资产配置 │   └─────────────────────────────────┘   │
│           │                                          │
│           │   ┌─────────────────────────────────┐   │
│           │   │  数据表格 / 下钻明细               │   │
│           │   └─────────────────────────────────┘   │
└───────────┴──────────────────────────────────────────┘
```

### 6 大报表类型

#### 1. 总览 Dashboard
**定位:** 一页看懂财务状况

**图表组合（多面板布局）:**
```
┌────────────────────┬────────────────────┐
│  月度现金流           │  支出分类甜甜圈      │
│  (柱状+折线组合图)    │  (SectorMark)      │
│  收入 ██ 支出 ██     │  餐饮 32%          │
│                     │  交通 18%          │
│                     │  ...               │
├────────────────────┴────────────────────┤
│  净资产趋势 (AreaMark + LineMark)        │
│  ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░               │
├────────────────────┬────────────────────┤
│  预算环形进度        │  近期交易列表         │
└────────────────────┴────────────────────┘
```
- **交互:** 每块点击进入对应详细报表
- **用途:** 替代当前简单的 Dashboard，作为报表入口

#### 2. 现金流分析
**定位:** 钱的流入流出全貌

**图表类型:** 瀑布图 + 趋势折线

```
  ┌──────────────────────────────────────────┐
  │  月度现金流瀑布图 (Waterfall)              │
  │  月初余额 ── +收入 ── ─支出 ── =月末余额   │
  │  ▓▓▓▓▓▓▓▓ ▓▓▓▓▓▓▓▓ ▓▓▓▓▓▓▓▓ ▓▓▓▓▓▓▓▓  │
  │   ¥12,000  +¥8,500  -¥3,200  ¥17,300    │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │  收支趋势 (LineMark × 2 + RuleMark 均值)   │
  │      ╱╲      ╱╲                          │
  │  ───/──\────/──\── 支出                   │
  │    ╱    ╲  ╱    ╲                        │
  │   ╱      ╲╱      ╲──── 收入               │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  均值线              │
  └──────────────────────────────────────────┘
```

**交互:**
- 悬停显示精确数值 tooltip
- 点击某月 → 下钻到该月日明细
- 图例切换 收入/支出/结余 可见性
- 时间轴可滚动（`.chartScrollableAxis`）

**来源:** 替代并升级当前 iOS `TrendChartView`

#### 3. 支出分类分析
**定位:** 钱的去向深度分析

**图表类型:** 旭日图 / 分层甜甜圈 + 树状图

```
  ┌──────────────────────────────────────────┐
  │  支出结构 — 旭日图 (Sunburst)              │
  │                                          │
  │       ╭──────────────────╮               │
  │       │   餐饮   交通      │               │
  │       │  ┌──┐  ┌──┐     │               │
  │       │  │外│  │打│     │               │
  │       │  │卖│  │车│     │               │
  │       │  └──┘  └──┘     │               │
  │       ╰──────────────────╯               │
  │                                          │
  └──────────────────────────────────────────┘

  或降级方案（更易实现）:
  ┌──────────────────────────────────────────┐
  │  多级甜甜圈 (Multi-level Donut)            │
  │  内圈 = 根分类, 外圈 = 子分类              │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │  分类排名 — 水平柱状图 (BarMark)            │
  │  餐饮 ████████████████████  ¥3,200       │
  │  交通 ██████████            ¥1,800       │
  │  购物 ████████              ¥1,200       │
  │  娱乐 ████                  ¥  600       │
  └──────────────────────────────────────────┘
```

**交互:**
- 扇区点击下钻（内圈 → 外圈 → 交易列表）
- 面包屑导航返回
- 悬停显示分类详情 tooltip
- 时间周期切换

**复用 iOS:** `ReportViewModel.load()` 的支出分类树逻辑完全可用

#### 4. 净资产时间线
**定位:** 个人财富增长可视化

**图表类型:** 堆叠面积图 + Mark 注解

```
  ┌──────────────────────────────────────────┐
  │  净资产趋势 (Stacked AreaMark)             │
  │                                          │
  │  ¥30,000 ┤          ╱╲  ▓▓▓▓▓▓▓▓        │
  │          │        ╱    ╲ ▓▓▓▓▓▓▓▓        │
  │  ¥20,000 ┤   ╱╲╱╱      ╲╱▓▓▓▓▓▓▓▓       │
  │          │ ╱╱            ▓▓▓▓▓▓▓▓▓       │
  │  ¥10,000 ┤╱              ▓▓▓▓▓▓▓▓▓       │
  │          └──────────────────────────      │
  │             6月   7月   8月   9月          │
  │  ▓▓ 资产   ░░ 负债   ── 净资产            │
  └──────────────────────────────────────────┘
```

**交互:**
- 悬停显示月资产/负债/净资产精确值
- 点击标记点查看该月账户明细
- 可滚动长周期

**数据来源:** 需要新增 `AccountBalanceSnapshot` 实体（每月底记录账户余额快照），或从交易累加计算

#### 5. 预算执行
**定位:** 预算 vs 实际，控制支出

**图表类型:** 组合柱状图 + 量表

```
  ┌──────────────────────────────────────────┐
  │  月度预算执行 (BarMark overlay)            │
  │  餐饮     ████████████████░░  85%         │
  │  交通     ██████████░░░░░░░░  50%         │
  │  购物     ████████████████████░  95%  ⚠️  │
  │  娱乐     ██████░░░░░░░░░░░░  30%         │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─            │
  │  总计     ██████████████░░░░  70%         │
  │           ██ = 实际  ░░ = 剩余            │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │  每日支出 vs 预算节奏 (LineMark)           │
  │  应该每天花 ¥107                           │
  │  实际累计 ████████████░░░░░░              │
  │  预算线   ─ ─ ─ ─ ─ ─ ─ ─ ─              │
  └──────────────────────────────────────────┘
```

**交互:**
- 点击某分类 → 展开该分类下子预算或明细
- 超标项红色告警
- 切换不同预算书

#### 6. 资产配置
**定位:** 账户资金分布一目了然

**图表类型:** 甜甜圈 + 账户列表

```
  ┌──────────────────────────────────────────┐
  │  资产配置 (Donut)                         │
  │                                          │
  │       ╭──────────────────╮               │
  │       │   储蓄账户  45%   │               │
  │       │   ╱              │               │
  │       │  ╱               │               │
  │       │ ╱ 投资账户 25%    │               │
  │       │  ╲              │               │
  │       │   ╲  支付宝 20%  │               │
  │       │    ╲ 现金 10%   │               │
  │       ╰──────────────────╯               │
  │                                          │
  │  总资产: ¥ 45,800                        │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │  账户列表 (按余额排序)                     │
  │  🏦 招商储蓄          ¥ 20,610   45%     │
  │  📈 基金账户          ¥ 11,450   25%     │
  │  💳 支付宝余额        ¥  9,160   20%     │
  │  💵 现金             ¥  4,580   10%     │
  └──────────────────────────────────────────┘
```

**交互:**
- 扇区悬停高亮
- 点击扇区/行 → 跳转账户详情页
- 可选择仅显示流动资产 / 全部资产

---

## 三、iOS 资产复用分析

### 可直接复用
| 组件 | 位置 | 说明 |
|------|------|------|
| `ReportViewModel.load()` | FirstCC/ViewModels | 支出分类树逻辑，用于支出分析和旭日图 |
| `ReportViewModel.loadTrendData()` | FirstCC/ViewModels | 月度聚合数据，用于现金流趋势 |
| `ReportPeriod` 枚举 | FirstCC/ViewModels | 6 个时间周期定义 |
| `CategoryPieChartView` | FirstCC/Views/Reports | 可改造为旭日图基类 |
| `CurrencyText` | FirstCC/Views/Components | 金额显示 |
| `CurrencyFormatter` | FirstCC/Utilities | 金额格式化 |
| `TransactionRowView` | FirstCC/Views/Components | 下钻交易列表 |

### 需要新增
| 组件 | 用途 |
|------|------|
| `WaterfallChartView` | 现金流瀑布图 |
| `SunburstChartView` | 支出旭日图（或 MultiRingDonut） |
| `NetWorthTimelineView` | 净资产面积图 |
| `BudgetGaugeView` | 预算量表/柱状对比 |
| `AssetDonutView` | 资产配置甜甜圈 |
| `CalendarHeatmapView` | 日历热力图（支出热度） |
| `ReportDashboardView` | 总览多面板布局 |
| `MacReportViewModel` | Mac 端扩展 ViewModel（或从 ReportViewModel 继承） |

### 需要新增 Service/数据
| 内容 | 用途 |
|------|------|
| `AccountBalanceSnapshot` 实体 | 净资产时间线月度快照 |
| `ReportService.getNetWorthTimeline()` | 净资产趋势数据查询 |
| `ReportService.getDailyExpenses()` | 日历热力图数据 |
| `ReportService.getBudgetComparison()` | 预算 vs 实际 |

---

## 四、交互设计规范

### Mac 特有交互
- **悬停 tooltip:** 鼠标悬停时显示精确值（`.chartOverlay` + `ChartProxy`）
- **右键菜单:** 导出、复制数据、查看详情
- **键盘导航:** Tab 在图表间切换，← → 切换时间周期
- **窗口响应:** 图表随窗口大小自适应调整数据密度
- **多选:** Shift+点击可选多个数据点进行对比

### 通用交互
- **时间周期选择器:** `Picker(.segmented)` 或 `Picker(.menu)` 切换
- **图例交互:** 点击图例切换系列显示/隐藏
- **下钻导航:** 点击 → sheet 或 NavigationLink → 详情
- **数据导出:** 导出按钮 → CSV/PNG

### 动画
- 切换周期时图表平滑过渡（`.animation(.easeInOut)`）
- 选中数据点时 scale 弹跳
- 图例切换时 fade + layout 动画

---

## 五、美学设计方向

### "性感" Chart 的标准

1. **渐变填充** — 面积图使用 `LinearGradient` 从品牌色到透明
2. **微妙阴影** — 关键 Card 使用 `.glassCard` 背景
3. **圆角端点** — `StrokeStyle(lineCap: .round)` 
4. **留白充足** — 数据/墨水比合理，不拥挤
5. **动效克制** — 加载时轻微上滑+淡入
6. **数据突出** — 选中数据点用大号字体浮层显示
7. **质感图层** — 使用 `.regularMaterial` 做图表背景

### 色板设计
```
收入/正向: Color.designPrimaryFixedDim (品牌绿)
支出/负向: Color.designAccentRed
净资产:    Color.designPrimaryContainer (蓝色系)
预算剩余:  Color.designAccentGreen
预算超标:  Color.designAccentRed
参考线:    Color.designOnSurfaceVariant.opacity(0.3)
```

### Typography 层级
```
大数值: .designDisplayMobile (如 ¥12,580)
图标题: .designHeadlineMedium
轴标签: .designBodyCaption
Tooltip: .designMonoData
```

---

## 六、Chart3D 应用机会 (iOS 26 / macOS 26+)

> WWDC 2025 引入 `Chart3D` + `SurfacePlot`，为 Mac 报表打开新维度。

### 适用场景（财务分析）

| 场景 | Chart3D 方案 | 可行性 |
|------|-------------|:---:|
| **净资产地形图** | `SurfacePlot` x=时间, z=账户类型, y=余额 → 3D 资产地形 | ⭐⭐⭐ 创新但需数据支撑 |
| **支出-收入-时间关系** | `PointMark(x:y:z:)` 三维散点，x=时间, y=金额, z=分类 | ⭐⭐ 探索性分析 |
| **多币种汇率曲面** | `SurfacePlot` 数学函数映射汇率波动 | ⭐ 小众需求 |

### 建议
- **Phase 3+ 可考虑** 将净资产趋势从 2D AreaMark 升级为 3D 资产地形图
- **不要为了 3D 而 3D** — Apple 明确建议仅在数据形状比精确读数更重要时使用
- **2D 优先** — 财务报表的核心是精确数值，2D 图表在大多数场景下优于 3D

---

## 七、实施路线图

> ✅/❌ 为 **2026-09-24 实测**结果（原文档全为未勾选的 `[ ]`，已不反映实际）。

### Phase 1 — 基础报表（对标 iOS 功能升级）— ✅ 全部完成
- [x] 现金流趋势图（LineMark + AreaMark + RuleMark）→ `MacTrendChartView.swift`
- [x] 支出分类甜甜圈（复用 SectorMark + 改造 TreeMap）→ `MacCategoryChartView.swift` + `DonutChart.swift` + `SunburstView.swift` + `MacTreemapView.swift`
- [x] 时间周期选择器 + 数据加载 → `ReportContent.swift`（含 `reportPickerBar` + 各报表专属周期集合）
- [x] Mac 端 ReportViewModel 扩展 → 已扩展到 6 种 `ReportType`

### Phase 2 — 高级报表 — ✅ 全部完成
- [x] 净资产时间线（AreaMark 堆叠）→ `MacAssetChartView.swift`
- [x] 预算执行对比（BarMark + RuleMark）→ `MacBudgetChartView.swift`
- [x] 资产配置甜甜圈 → `MacAssetAllocationView.swift`

### Phase 3 — 进阶可视化 — ✅ 完成（1 项以变体落地）
- [x] 瀑布图（自定义 BarMark 组合）→ `DashboardContentColumn.swift:385` `waterfallChart` + `WaterfallSegment:608`
- [x] 总览多面板 Dashboard → `DashboardContentColumn.swift`（多卡片面板）
- [~] 日历热力图 → **以「每日热力」形式落在流水列表**（`TransactionListContent.swift:383-387`），
      **未做成独立报表类型**；如需独立报告需另开

### Phase 4 — 交互打磨 — ✅ 4/5（唯 HIG 审查未做）
- [x] 悬停 tooltip → `MacTrendChartView.swift:293`、`MacAssetChartView.swift:263`，及 `CategoryBarList`/`MacAssetAllocationView`/`MacTreemapView` 的 `onHover`
- [x] 下钻导航 → `MacDimensionChartView.swift:40`（`TransactionDetailList`）
- [x] 导出功能 → `Qianeymac/Views/Settings/MacExportView.swift`
- [x] 动画调优 → `Reports/` 下 32 处 `withAnimation` / `.animation(`
- [ ] **macOS HIG 审查** → ❌ **仍未做**。见 `.claude/plans/release-checklist.md` §二-6

### 计划外实际新增（本文档未规划但已落地）
- 第 6 种报表 `ReportType.member`「多维分析」（商家/项目双维度）→ `MacDimensionChartView.swift`
- 共用组件 `TransactionDetailList.swift`、`CategoryBarList.swift`（从 `MacCategoryChartView` 提取）

---

## 八、技术参考

- [[apple-chart-knowledge-base]] — 项目 Swift Charts 知识库 (已更新至 WWDC 2026)
- Apple HIG Charting: https://developer.apple.com/design/human-interface-guidelines/charting-data
- Swift Charts: https://developer.apple.com/documentation/charts
- WWDC 2025-313 — Bring Swift Charts to the Third Dimension: https://developer.apple.com/videos/play/wwdc2025/313/
- macOS 27 "Golden Gate" — Uniform Liquid Glass 自动适配，无需额外代码
- 竞争产品参考: Finance Copilot, Wiselet, Moneyboard (Charts 实现标杆)
