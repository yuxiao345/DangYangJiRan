# 同步冲突：根因、边界、完整性方案

> 起因：2026-10-07 数据事故（详见 `.claude/plans/data-recovery-2026-10.md`）。
> §1 的 API 结论均来自 **SDK 头文件原文（macOS 27.0 SDK）** 或 Apple 官方论坛，非推测。
> **状态：路线已批准（2026-10-08，用户选定方案 A），尚未实施一行代码。**
> **排期：先完成数据修复（见 data-recovery-2026-10.md），再动同步代码。**
> 实施前仍须用户明确同意（CLAUDE.md 规则 3 / [[feedback_ask_before_code]]）。

## 决策记录（2026-10-08）

| 决策 | 结论 |
|---|---|
| 方案路线 | **A** —— 保留 `NSPersistentCloudKitContainer`，在它之上建「审计 + 快照 + 闸门」层。 |
| 排期 | **先修数据，再动同步代码。** 修复期间不要用新构建覆盖正在修复的设备。 |
| 已否决 | 方案 B（iCloud Drive 文档 + `NSFileVersion`）—— 结构性更强但需重写持久层；方案 C（自建同步）；方案 D（换 SwiftData）。理由见 §4。 |
| 已接受的前提 | 「零冲突」在 CKC 上不存在，本方案保证的是「零静默丢失」（§2.2 的四条不变量）。残余风险 H1–H5 已知并接受（§2.3）。 |
| **Schema 变更** | **走「零结构变更」版（第一步）。** 不加实体、不加字段、不改 `.xcdatamodeld`、不改 pbxproj。理由见 §3.2。 |
| 环境状态 | **已上 TestFlight（未上 App Store），用户 3–5 人。CloudKit Production 有真实数据，不可破坏。** |

## 3.2 为什么必须走「零结构变更」版（2026-10-08 定）

**环境约束**：TestFlight 装的是 Archive 出来的 Release 构建 ⇒ 用的是 CloudKit **Production** 环境，
且该环境**已有真实数据、不能重置**。

| 操作 | Production 是否允许 |
|---|---|
| 加字段 / 加记录类型 | ✅ 允许（但要走 Deploy Schema Changes） |
| 改名 / 改类型 / 删字段 / 重置环境 | ❌ **不允许** |

**决定性理由（不是"不允许"，而是"加了也没用"）**：

> TestFlight 上 3–5 个用户，**无法保证所有设备同时升级**。而失败模式恰恰是"旧版本设备全量重传" ——
> 它序列化出的 CKRecord **不含新字段**，CloudKit 整条替换 ⇒ **新字段被清空**。
>
> **⇒ 为了修这个 bug 而加的新字段，恰好会被这个 bug 本身抹掉。**
>
> 更尖锐：**最不可能及时升级的那台设备，正好就是"落后最久"的那台，也就是最危险的那台**
> —— 一台三天没开机的设备，当然也没更新 App。

**推论**：新加的同步字段**绝不能是唯一防线**。而既然它只能是"锦上添花"，
那"第一步不加以省掉全部结构风险"就是纯收益。

**因此第一步的全部状态都放本机**（不进 Core Data store、不随 CloudKit 同步）：

| 状态 | 存放位置 | 为什么放这儿 |
|---|---|---|
| 字段历史值集合（C1） | **Application Support 下的独立文件**，不进 store | Apple 的"关 iCloud 开关抹本地 store"行为抹的是 **store**，不是整个容器 ⇒ 放外面能幸存（⚠️ 待验证：抹的到底是 store 还是整个容器；但放外面更安全这一结论不依赖验证结果） |
| 删除墓碑（C2） | 同上 | 同上 |
| 冲突日志（C3） | 同上 | 同上 |
| 本机快照（C4） | 本机文件 | 会被 iCloud Backup（iOS）/ Time Machine（macOS）覆盖 ⇒ **零成本获得异地副本**，不需要开 iCloud Drive 容器 |

**升级版（`AuditEntry` + 作者时间戳）推迟到上 App Store、版本收敛之后** —— 它换来的是"系统自动收敛、省掉人工裁决"，**是便利，不是安全**。

> **2026-10-08 追加修正**：用户确认**可以控制所有设备（含老婆的设备）的 App 升级节奏** ⇒ 上面
> "无法保证设备同时升级"这条前提**被削弱**，第二步不再被它挡住。但结论不变，另有三条理由站得住：
> ① **`fieldStamps` 本身也是整条记录 LWW 的受害者**，从来就不是安全防线，只是精度提升；
> ② 本项目有 schema 变更的踩坑史（`initializeCloudKitSchema()` 导致看门狗杀进程，已禁用；重复 model → 134020）；
> ③ **第二步应当建在第一步之上，而不是替代它** —— 第一步是"新字段被清空"时的**降级路径**。
>
> **共享账本（CKShare）情况**：2 个参与者（用户 + 其配偶）。⇒ 配偶的**所有设备也是共享账本的写者**，
> 同样可能是本次事故的元凶、同样能在修复后把数据推翻 ⇒ **隔离清单必须包含配偶的设备**（H4 从"待议"升级为"必须处理"）。
> 第三位用户使用**自己的独立账本**（私有库分开），不受本次事故影响，修复也不会波及。


---

# 第一部分 · 根因

## 1.1 这是框架的设计，不是本项目的 bug

`NSPersistentCloudKitContainer`（下称 CKC）有三条硬性质：

1. **冲突解决不可配置。** 服务端按**写入时间**做 last-writer-wins（LWW），粒度为**属性级**。
   - 属性级：两台设备离线时改了**不同**属性 → **不合并**，后写的那台整个对象赢。
   - 关系级：to-one 是 LWW；to-many 是合并。
   - 来源：WWDC19 "Using Core Data with CloudKit"；Apple 论坛 thread 122745 确认"Apple 未文档化此事"。
2. **`mergePolicy` 管不到跨设备合并。** 它作用于 context 层；CloudKit 层的合并在数据进入 context **之前**就完成了。
3. **导入与导出是两条独立的异步循环，没有"先拉后推"的顺序保证。**

**事故就是第 3 条的直接后果**：iPhone Air 打开后先记账（触发**导出**，快），而它的**导入**还没跑完。
导出取的是**当前本地行值**（旧的），到服务端却拿到一个新的写入时间戳 → LWW 判定它最新 → 反向覆盖 Mac。

## 1.2 已排除的 API（别重复尝试）

| API | 结论 |
|---|---|
| `canUpdateRecord(forManagedObjectWith:)`<br>`canDeleteRecord(forManagedObjectWith:)`<br>`canModifyManagedObjects(in:)` | **不是冲突裁决钩子。** 头文件原文：只回答"当前用户对该记录**有没有写权限**"（临时对象 / 非 CK store / 私有库 → YES；公有库 → 仅自己创建的 → YES）。私有库场景**永远返回 YES**。**此路不通。** |
| `mergePolicy`（`NSMergeByPropertyObjectTrumpMergePolicy` 等） | 只作用于 context 层。 |
| 自己写同步 / 用 CKRecord changeTag 做乐观锁 | 过度工程化；且不能消除冲突，只是换一套冲突。参照 CKShare 的教训。 |

## 1.3 可用的钩子（已验证存在，编译通过）

| 钩子 | 能给什么 |
|---|---|
| `NSPersistentCloudKitContainer.eventChangedNotification`<br>`NSPersistentCloudKitContainer.Event` | `type`(.setup/.import/.export) / `startDate` / `endDate` / `succeeded` / `error`。<br>**⇒ 判定"我的改动有没有成功上云"、"上次成功导入是多久前"。** 另有 `EventRequest` 可回查历史事件。
| `NSPersistentStoreRemoteChangeNotification`（+ `...PostOptionKey`） | 每次写入（含跨进程）触发，userInfo 带 `NSPersistentHistoryTokenKey`。 |
| `NSPersistentHistoryTrackingKey`（**本项目已开**） | `transaction.author`（`NSCloudKitMirroringDelegate` 前缀 = 远程导入）；`change.updatedProperties`（**只列改了哪些属性，不存旧值**）。 |

---

# 第二部分 · 能保证什么，不能保证什么

## 2.1 不能保证

**不能保证"不发生冲突"。** 见 §1.1。
⇒ 因此**"绝对不会有同步冲突"的方案在 CKC 上不存在**。

## 2.2 能保证（在框架之上自建，可测试、可验证）

> **财务系统的严谨性不是靠"不出错"，而是靠"每一笔变更都留痕、可核对、可追溯"。**
> 这正是复式记账本身的原理。方案就按这个原理设计。

### 四条不变量 —— 方案的正确性定义

| 编号 | 不变量 | 违反的后果 |
|---|---|---|
| **I1** | **无静默覆盖**：任何远程导入覆盖了本机此前的改动，必在冲突表中留痕、且 UI 可见 | 用户不知道数据被改了 |
| **I2** | **无不可恢复丢失**：任意时刻存在 ≤24h 的完整快照；被覆盖字段的旧值单独留痕 | 数据永久丢失 |
| **I3** | **无陈旧设备抢写**：未完成首次完整导入前不可写入；离线超阈值的设备降级只读 | 2026-10-07 事故 |
| **I4** | **删除不复活**：被本机删除的对象若被远程重新插入，自动再次删除并留痕 | 今天发现 pk 1093–1097 |

**每一条都能写成自动化测试**（§6）。

## 2.3 诚实的残余风险（必须写在发布说明里）

| 编号 | 风险 | 缓解 |
|---|---|---|
| **H1** | 冲突发生在**两台都不是本机的设备**之间，本机从未编辑过该字段 | C1 的**同步版**审计日志（§3 C1'）让**任意**设备都能看到全部变更；每台设备各自检测、各自提示 |
| **H2** | 用户在系统设置里手动删除 iCloud 存储中的 App 数据 | 本机快照 + C4 的云端快照 + 导出文件 |
| **H3** | 所有设备丢失 **且** iCloud 数据被删 | **定期导出可读文件**（项目已有 `ExportService`），用户自己保存。**这是财务应用不可妥协的底线** |
| **H4** | 共享账本（CKShare）多用户；别人的设备不受本方案约束 | 共享账本单列规则：见 §5 B7 |
| **H5** | CKC 本身的行为变更（未来 OS 版本） | 把 §6 的测试套件纳入 CI，每次 OS 大版本升级跑一遍 |

> **"零风险"等于"不做云端同步"。** 正确的发布门槛不是"零风险"，而是：
> **已知风险都有明确检测、可见提示、和执行得通的恢复路径。**

---

# 第三部分 · 方案

## 3.0 结论先行

**保留 CKC，在它之上建一层"审计 + 快照 + 闸门"。**
不要自建同步（工程量大、不必然更好）；不要换成 iCloud Drive 文档 + `NSFileVersion`
（结构性更强但要重写整个持久层，且牺牲增量同步与 CKShare —— 见 §4 备选评估）。

## 3.1 五个组件

### C1 · 变更留痕（本机，不同步）

在本机 `NSManagedObjectContext` 的 `willSave` 钩子里，对 `updatedObjects` 用
`committedValues(forKeys:)` 取**旧值**，写入本机表 `LocalEditLog`：

```
objectStableID   // 实体的 id UUID（所有实体都有）
entityName
fieldName        // 属性名；to-one 关系单独标记
oldValue         // 序列化后的旧值
deviceID         // 本机 UUID（Keychain 持久，卸载重装不变）
localSeq         // 本机单调递增序号（★ 不用墙上时钟，见 §5 B6）
wallTime         // 仅用于展示
```

**关键点：记录"旧值"是本方案的根基** —— 持久化历史不存值，所以**必须在覆盖发生之前**抓。
`localSeq` 用单调序号而非时间戳，避免时钟错误/跨时区污染裁决（边界 B6）。

### C1' · 同步版审计日志（只追加，随 CKC 同步）

一个**只插入、从不更新、从不删除**的实体 `AuditEntry`：

```
entryID (UUID, 唯一)   deviceID   deviceName   localSeq
objectStableID   entityName   fieldName   oldValue   newValue   wallTime
```

**为什么只追加就能安全同步**：每次插入都是新 UUID ⇒ 不与其他记录冲突；to-many 是合并语义 ⇒ 全部保留。
LWW 破坏不了它。**于是任何设备都能重建"谁在什么时候改了什么"的完整历史** ——
这就是财务系统的不可变账本，也是 H1 的缓解。

**容量策略**：只记录金融字段（金额、期初、账户、分类、日期、删除标记），保留 12 个月；超期归档或压缩。

### C2 · 删除墓碑（本机 + 同步）

- 本机删除对象时，把它的 `id` UUID 写入本机表 `DeletedObjectLog`，**并同时向 `AuditEntry` 追加一条删除事件**。
- **每次导入完成后**，扫描本次导入**新增**的对象：若其 `id` 在 `DeletedObjectLog` 中
  ⇒ **判定为"删除被复活"，自动再次删除，并向 `AuditEntry` 追加一条「已拦截复活」事件**。
- 用户从 UI 恢复某个删除时，从 `DeletedObjectLog` 移除该 id。

**为什么这能彻底解决 I4**：重新录入的记录会拿到**全新的 UUID**，不会误命中。
今天 pk 1093–1097 那 5 笔，在这套机制下会被自动再删一次并留下记录。

### C3 · 冲突检测与呈现

**触发时机**：`NSPersistentStoreRemoteChangeNotification` 到达后（异步，不阻塞 UI）。

**两条检测规则**（取并集）：

> **D1 · 未导出覆盖**：本次导入改了 (对象, 字段)，而该字段的本机编辑 **晚于最近一次成功的 export**
> （时间点取自 `EventChangedNotification` 里 `.export` 且 `succeeded` 的 `endDate`）
> ⇒ 这份本地改动**还没安全上云就被改了**，判定为冲突。

> **D2 · 回退覆盖（★ 本方案的核心）**：本次导入写入的值，**等于 `LocalEditLog` 里该字段记录过的某个历史旧值**
> ⇒ **这是把值改回了从前**，判定为冲突。
>
> **为什么 D2 是关键**：D1 抓不到"本机改动已经导出、随后被陈旧设备覆盖"的情况
> —— 而 2026-10-07 的事故**正是这一种**（Mac 的正确值 16:36 已成功上云，21:51 被 Air 的旧值覆盖）。
> D2 不需要任何远程时间戳：**只要"值回到了我们记录过的过去"，就一定是回退。**
>
> 以事故为例：Mac 在 15:16 把「微信-六日」期初设为 X，`LocalEditLog` 记下旧值 `0.00`；
> 21:51 导入把它改回 `0.00` ⇒ **命中 D2**。

**处置（三条同时做，不自动回滚）**：

1. 向本机 `SyncConflictLog` 写入：对象、字段、被覆盖前的值、覆盖后的值、命中规则、时间。
2. 向 `AuditEntry` 追加冲突事件（其他设备也能看到）。
3. **UI**：设置页「同步冲突」列表，每条给 **[恢复我的值] [保留对方的]** 两个动作；
   同时受影响对象所在页面显示一个提示标记。
   **未裁决的冲突不阻塞使用，但绝不能不显示。**

### C4 · 快照（I2 的硬保证）

三个层次：

| 层 | 时机 | 内容 | 保留 |
|---|---|---|---|
| **本机轮转** | 每日首次启动 + **每次大批量远程变更之前**（阈值：单次导入 > 20 个对象，或 > 5% 的对象） | 整库关键实体序列化 | 最近 30 份 |
| **云端只追加** | 同上 | 同一份快照作为**新的 `Snapshot` 记录**推进 CKC 私有库（只追加 ⇒ 不冲突） | 最近 30 份 |
| **用户可携带** | 手动 + 每月提醒 | CSV / 项目已有的 `ExportService` 输出 | 用户自己保管 |

**"大批量变更前先快照"这一条**直接覆盖今天的两个场景：
21:51 的覆盖（5 个对象，低于阈值 → 由 C3 兜住）和 10:05:39 的全量重导（约 60 个对象 → **触发快照**）。

### C5 · 同步闸门与陈旧设备降级（I3）

**闸门（每次冷启动 / 长时间后台后）**：
1. 订阅 `EventChangedNotification`，记录本会话是否已有成功的 `.import`。
2. **未成功导入之前**，写入类入口（记一笔 / 编辑）置为「正在同步…」不可用。
3. 离线兜底：允许写入，但记录「本机在离线窗口内写入」，联网后先完成一次导入再解锁。

**陈旧设备降级**：
- 本机记录 `lastSuccessfulImportAt`。
- 若 `now − lastSuccessfulImportAt > 24h` **且本机存在未导出的本地改动** ⇒ 进入**只读**模式：
  可以看、不能写，直到完成一次成功的 import + export 往返。
- 若 `> 7 天` ⇒ 额外提示「建议重建本地数据」。
  **重建 = 删除本地 store 让它重新全量下载**（CloudKit 上的数据不受影响）。
  **必须用户确认**，且在重建前先做一次本机快照。

---

# 第四部分 · 备选方案评估

| 方案 | 能否更强地保证"不静默覆盖" | 代价 | 结论 |
|---|---|---|---|
| **A. 保留 CKC + 审计层（本方案）** | 冲突仍会发生，但**不静默、可恢复、可追溯** | 新增 4 张表 + 3 个界面；不动同步本身 | ✅ **推荐** |
| **B. iCloud Drive 文档 + `NSFileVersion`** | **结构性更强**：系统保留冲突版本，不静默覆盖（Pages/Numbers 同机制） | 重写整个持久层；失去增量同步、CKShare、Core Data 查询；每次并发编辑都要人工合并 | ⚠️ 只有在 A 的残余风险不可接受时才考虑 |
| **C. 自建同步 / 自建服务端** | 只有做成"服务端唯一权威 + 禁止离线写"才真正为零冲突 —— 那就毁掉了离线记账这个核心场景 | 数月工程量，且引入全新缺陷面 | ❌ 不推荐（过度工程化） |
| **D. 换成 SwiftData + CloudKit** | **没有改善**，底层是同一套机制 | 全量迁移 | ❌ |

**推荐 A。** 理由：它把"不可恢复的灾难"转化为"可检测、可恢复、可审计的事件"，
而后者才是财务软件正确的目标；代价可控，且不触碰同步本身、不引入新缺陷面。

---

# 第五部分 · 边界清单（逐条对应处置）

| # | 边界 | 处置 |
|---|---|---|
| **B1** | 设备长期离线后回归（**本次事故**） | C5 陈旧降级 + C3 D2 + C4 |
| **B2** | 首次安装 / 换新机（空本地库） | C5 闸门：首次完整导入前禁止写入 |
| **B3** | 用户退出 iCloud / 关闭本 App 的 iCloud 开关 | **Apple 设计行为：会抹掉本机 store，且无 API 可关**（Apple DTS 已确认）。处置：① 本地快照同时存云端（C4）② 重新开启后会自动全量拉回，数据不丢、只是慢 ③ UI 文案提前告知 |
| **B4** | iCloud 存储已满 → 导入停滞 | C5 健康页显示失败次数与错误码（事故当晚导入失败 **199 次**、其中 47 次 `CKErrorDomain` code 2，用户全程无感） |
| **B5** | 长期无网络，仍要记账 | 产品决策：闸门是硬拦还是"允许但标记"。**建议允许但标记** |
| **B6** | 设备时钟错误 / 跨时区 | **裁决一律不用墙上时间**：C1 用本机单调序号；C3 用"值回退"（D2）而非时间比较 |
| **B7** | 共享账本（CKShare）多用户并发 | 共享账本单独规则：**建议共享账本降级为"只读共享 + 邀请制写入"**，或明确提示冲突风险更高 |
| **B8** | 删除 vs 编辑竞争 | C2 墓碑 + 导入后扫描 |
| **B9** | to-one 关系被覆盖（今天已发生：60+ 对象的关系被整批改写） | C3 的字段范围**必须包含 to-one 关系**，不能只审计属性 |
| **B10** | 大批量重导（今天 10:05:39 约 60 个对象） | C4 阈值触发快照；且 C3 对"一次导入改了超过 N 个对象"的情况**不逐条报冲突而是汇总报**，避免刷屏 |
| **B11** | 审计表无限增长 | C1 保留 12 个月；C2 墓碑保留期须显著长于冲突窗口（建议 1 年）；`AuditEntry` 只记金融字段 |
| **B12** | 审计功能上线前已经发生的冲突 | 只能从上线时刻起生效。**上线时写入一条基线快照** |
| **B13** | 用户手动"抹掉本地数据重来" | 提供入口，且在抹掉前强制做快照 + 二次确认 |
| **B14** | 部分导入失败 / 重试的幂等性 | C3 检测按最终值判定，不依赖单次事件计数 |
| **B15** | 存储空间与性能（快照序列化的开销） | 快照异步、压缩；本项目规模（55 账户 / 1047 笔交易）单份约数百 KB |

---

# 第六部分 · 验收测试（未通过不得发布）

| # | 场景 | 断言 |
|---|---|---|
| **T1** | 复现本次事故：A 机写下正确值 → 成功导出 → B 机（数据陈旧）推送旧值 | A 机出现冲突记录；命中规则为 **D2**；UI 可见 |
| **T2** | 删除复活：A 删 → B 推回同一记录 | 自动再次删除；`AuditEntry` 有「已拦截复活」；**不产生重复项** |
| **T3** | 冷启动空库 | 首次 `.import` 成功前写入入口不可用 |
| **T4** | 关闭 App 的 iCloud 开关 → 重开 | 数据全量恢复；期间无丢失 |
| **T5** | 大批量重导（> 阈值） | 触发快照；不逐条刷屏报冲突 |
| **T6** | 快照恢复 | 可回滚到任意保留时间点，恢复后净资产与当时一致 |
| **T7** | 时钟错误 | 篡改设备时间后，D1/D2 判定不受影响 |
| **T8** | 并发属性级编辑 | 两台设备改同一对象的**不同字段** → 冲突被发现并提示（不会被静默各赢一半） |

**测试实现建议**：T1/T2/T4/T8 需要双设备，无法在单进程轻易复现 ⇒
把 C2/C3 的检测逻辑写成**纯函数**（输入：历史变更集合 + `LocalEditLog` + 导出时间点 ⇒ 输出：冲突集合），
用**合成数据**直接单测。这是让这套机制可验证的关键设计选择。

---

# 第七部分 · 与发布的关系

**发布门槛（建议写进 `.claude/plans/release-checklist.md`）：**

1. C2（删除墓碑）、C3（冲突检测）、C4（快照）、C5（闸门）**全部实施**
2. §6 的 T1–T8 **全部通过**
3. C3 的冲突界面、C5 的同步健康页**在两端都有入口**（iOS + macOS，遵循 CLAUDE.md 平台一致性表）
4. H3 的导出路径**可用且有引导**

**分批建议**：P0 = C2 + C3 + C4 + C5（发布前必须）；P1 = C1' 同步审计日志 + 设备可见性（发布后第一个版本）。

---

# 第八部分 · 实测：开发/生产环境在这台机器上**完全共库**（2026-10-08）

把「事故根因 = 开发/生产共库」从**结构推断**升级为**时间线实证**。以下均为实测。

## 8.1 两侧真在同一个文件上

| 项 | 生产版 `/Applications/Qianey.app` | Xcode Debug 版 |
|---|---|---|
| `CFBundleIdentifier` | `com.qianey.app.mac.Qianeymac` | **完全相同** |
| CloudKit 容器 | `iCloud.com.qianey.v2` | **完全相同** |
| `icloud-container-environment` | `Production` | **该 key 不存在** |
| `aps-environment` | `production` | `development` |
| 本地库 | `~/Library/Containers/com.qianey.app.mac.Qianeymac/Data/Library/Application Support/FirstCC.sqlite` | **同一个文件** |

- 沙盒容器按 bundle id 认，两个 App 的 bundle id 一字不差（`PlistBuddy Print :CFBundleIdentifier` 实测）
  ⇒ **生产版与 Xcode 版读写同一个 sqlite**。
- 库路径在代码里写死、**无 Debug/Release 分支**：`CoreDataStack.swift:81-83`。
- 容器标识唯一：`FirstCC/Utilities/CloudKitConfig.swift:6`。
- 环境标识**不在仓库里**：两份 entitlements 都没写 `icloud-container-environment`
  ⇒ 由「从哪构建/分发」隐含决定：缺 key ⇒ Development；TestFlight / 商店版 ⇒ **永远** Production，
  不受该 key 影响。依据见参考列表 thread 707098（该 entitlement 对 `NSPersistentCloudKitContainer` 同样有效；
  要改必须写 `.entitlements` 而非 Info.plist）。

## 8.2 事故时刻就在 Debug 会话里

`sharing_diag.log` **只由 `#if DEBUG` 写**（`DiagnosticLog.swift:13-15`，Release 不落盘）
⇒ 该文件存在本身就证明这台机器跑过 Xcode 版；它最后写入 10-07 23:04。

同一库的 `ANSCKEVENT` 与日志**逐条对得上（±1 秒）** ⇒ Debug 会话的同步事件写进了生产库：

| 日志里的启动（10-07） | 库里的事件 |
|---|---|
| 21:44:12.042 | 21:44:12 setup |
| 21:45:03.814 | 21:45:04 setup |
| 21:48:35.212 | 21:48:35 setup |
| **21:50:50.859** | **21:50:52 setup → 21:50:54 import OK → 21:50:55 export OK ×3** |
| 22:03:55.808 | 22:03:56 setup → 22:03:59 import+export |

21:50:55 那三次 export 落在净资产变化时刻（21:50–21:51）之内；库里 21:51:04 另有一条「本机写入」。

## 8.3 诚实边界

库文件**不携带环境标记** —— 无法从盘上判断某次 export 打到 Development 还是 Production。
「同一 App id + 同一个库文件」是实测；「切环境 ⇒ change token 作废 ⇒ 全量重取重推」仍是
推断 + 社区证据（§1.1 与参考列表），Apple 文档从未正面确认。

## 8.4 对修法的直接影响：**两层就够，不需要三层**

1. **库必须分（必需）**：Debug → `FirstCC.debug.sqlite`（共享库同理 `.shared.debug`）。
   只要共库，环境隔离无从谈起 —— 根因正在此。
2. **测试期不再靠纪律（必需）**：现在只认 `-UITEST_MODE`，且**只有 UI 测试会传**
   （`app.launchArguments += ["-UITEST_MODE"]`）；单测不传，而单测宿主是**真实 App**
   （`TEST_HOST = …/Qianey.app/Qianey`，`BUNDLE_LOADER = $(TEST_HOST)` 实测）
   ⇒ 跑单测会以 Debug 版启动真实 App、走真实库 + Development 环境。
   识别测试宿主（`XCTestConfigurationFilePath`）后给独立测试库且**不设** `cloudKitContainerOptions`，
   方可拆掉 CLAUDE.md 那条「不许跑 Mac 测试 scheme」的红线。
3. **显式钉住 Debug 环境（防御性、非必需 —— 2026-10-08 已实施）**：缺 key 默认已是 Development，
   所以只看默认值确实不必需。**但默认值不是保证** —— Apple 原文
   （`Deploying an iCloud Container's Schema`）：
   *"For testing purposes, your app in development can access **either** the development
   or the production environment."* ⇒ 钉住它才是"结构上不可能连生产"，符合 I1「不靠纪律」。
   实测生效路径：源 entitlements 里的键**原样进入签名**（Debug 产物签名里出现
   `icloud-container-environment = Development`），描述文件只是**追加**自己的键
   （`app-sandbox`/`get-task-allow`/`application-identifier`）。
   商店版忽略该 key，不影响上架；但 **Release 的 entitlements 不得含此键**
   （被钉成 Development 会被 App Store 拒审，属 fail-closed）。
   ⚠️ 代价：`*-Debug.entitlements` 与生产 entitlements 只差这 1 个键，需**长期手工同步**。
4. **独立开发容器（可选）**：同容器下 Development 环境会装进一份**真实账本草本**；
   要彻底不混，Debug 才需要 `iCloud.com.qianey.v2.dev`。

## 8.5 用户定的策略（2026-10-08）

> **测试侧绝对不能连接到生产。** 需要测试环境看数据时，**手动**把数据从生产搬到测试。

两条不变量：

- **I1 · 测试端永不触达生产** —— 要**结构性**保证，不靠纪律。
  可保证的部分：Debug 版环境是 Development，而商店 / TestFlight 版**永远** Production
  ⇒ 即使 Debug 版想写生产也写不到（这正是该不变量的结构性依据）。
  保证不了的部分：**本地库**（今天两个 App 同库）⇒ 必须分库，见 8.4-1。
  还要堵一条：禁止把测试 / Debug 库文件拷成 `FirstCC.sqlite`。
- **I2 · 生产 → 测试只允许手动、单向、显式**，不允许自动、不允许反向。
  迁移的**源只能是生产版本的本地产物**（生产库文件 / 导出文件）—— **Debug 版读不到 CloudKit 生产库**
  （entitlement 决定），所以「从生产库迁移」在实现上必然走本地产物，这是结构性事实而非缺陷。
  ⚠️ 搬迁时**必须清空 `ANSCK*` 同步元数据表**：否则测试库携带指向**生产环境**的 change token，
  首次连 Development 会触发一次全量重取重推（只在 Development 内，无害但很吵）。

---

# 参考

- Apple 论坛 thread 122745 —「Core Data with CloudKit doesn't seem to document how changes get merged」
  <https://developer.apple.com/forums/thread/122745>
- Apple 论坛 thread 661474 —「Core Data errors when saving context after syncing from CloudKit」
  <https://developer.apple.com/forums/thread/661474>
- Apple 论坛 thread 811294 —「NSPersistentCloudKitContainer data loss edge case」（关 iCloud 开关会抹本地数据）
  <https://developer.apple.com/forums/thread/811294>
- Apple 论坛 thread 707098 —「icloud-container-environment with NSPersistentCloudKitContainer」
  （该 entitlement 对 CKC 有效；必须写 `.entitlements` 而非 Info.plist；商店/TestFlight 版永远 Production）
  <https://developer.apple.com/forums/thread/707098>
- SDK 头文件逐字核对：`CoreData.framework/Headers/NSPersistentCloudKitContainer.h`、
  `NSPersistentCloudKitContainerEvent.h`、`NSPersistentStoreCoordinator.h`（macOS 27.0 SDK）
