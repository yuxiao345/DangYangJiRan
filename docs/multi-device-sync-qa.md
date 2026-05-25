# 同 iCloud 账号多设备同步 Q&A

## 同步机制

使用 `NSPersistentCloudKitContainer`，Private 数据库通过 iCloud 自动双向同步。同一 Apple ID 登录的所有设备共享同一份 Private 数据库数据。

## Q: 在一台设备上新增/修改/删除数据，其他设备会自动同步吗？

**会。** 新增、修改、删除三类操作都会自动同步：

- **新增**：`context.save()` 后，`NSPersistentCloudKitContainer` 将新记录导出到 CloudKit，其他设备导入后创建本地记录。
- **修改**：字段变更后保存，CloudKit 推送变更到其他设备，自动合并。
- **删除**：`context.delete()` + `context.save()` 后，CloudKit 记录被删除，其他设备导入后本地记录也被删除。

代码路径：`LedgerServiceImpl.deleteLedger()` → `context.delete(ledger)` → `context.save()` → CloudKit 导出 → 其他设备导入并删除对应对象。

## Q: 同步需要多长时间？

正常情况下几秒到十几秒。首次安装或长时间离线后首次同步可能需要 1-2 分钟。影响因素：

- CloudKit push 通知延迟
- 数据量大小
- 网络状况（Surge/VPN 可能阻断 iCloud 流量，见下文）

## Q: 为什么两台设备都有一个「我的账本」，但它们不同步？

这是初始化时机问题：

1. 两台设备分别在不同时间首次安装 App
2. 每次安装时，`configureDefaultLedger()` 看到本地无账本，就创建「我的账本」——**每次创建的 UUID 不同**
3. 部署新版本后 CloudKit 开始同步，两边各自将自己的「我的账本」推给对方
4. 结果：每台设备上出现了两个「我的账本」——自己创建的原版 + 对方的版本

此时 `deduplicateLedgers()` 被触发：
- 按交易数量排序，保留交易多的那个
- 删除交易少的那个

所以你会看到其中一台设备的「我的账本」先消失再出现——它被替换成了数据更多的那一份。

## Q: 删除了一个账本，另一台设备会自动删除吗？

**会。** 删除是标准 CoreData 操作，`NSPersistentCloudKitContainer` 将其作为记录删除同步到 CloudKit，其他设备收到变更后自动执行本地删除。

## Q: Surge/VPN 会影响同步吗？

**会。** 如果 Surge 规则对以下 Apple 域名走了代理或阻断，CloudKit 同步会失败：

- `apple-relay.apple.com` — Apple 中继服务
- `courier.push.apple.com` — CloudKit push 通知
- `*.icloud.com` — iCloud 服务

解决方案：在 Surge 规则中将这些域名设为 `DIRECT`，或者在测试同步时暂时关闭 VPN。

## Q: 如何判断同步是否正常工作？

1. **看日志**：DiagnosticLog 中 CloudKit 事件日志（`CloudKit[StoreName] IMPORT/EXPORT: OK/FAIL`）
2. **做双向测试**：在设备 A 新建一条交易，看设备 B 是否出现；反之亦然
3. **冷启动测试**：如果同步似乎卡住，关闭 App 重新打开——启动时会主动拉取 CloudKit 数据

## 核心代码位置

| 组件 | 文件 | 作用 |
|------|------|------|
| Stack 初始化 | `CoreDataStack.swift` | 双 Store 配置、CloudKit 事件日志 |
| 去重逻辑 | `AppContainer.swift:deduplicateLedgers()` | 同名账本去重 |
| 默认账本 | `AppContainer.swift:configureDefaultLedger()` | 首次启动创建「我的账本」 |
| 同步服务 | `SyncServiceImpl.swift` | CKShare 共享、参与者管理 |
| 删除账本 | `LedgerServiceImpl.swift:deleteLedger()` | 标准 CoreData 删除 |
