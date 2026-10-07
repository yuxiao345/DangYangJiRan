# App Store Connect 上架文案

钱伲 · iOS（Mac 端名为 Qianey，文案需另备一套，不能与本套同名同文）

> **字数上限（App Store Connect 硬限制，超一个字符就提交不了）**
> 名称 30 · 副标题 30 · 关键词 100 · 推广文本 170 · 描述 4000
> 「名称 + 副标题 + 关键词」三个字段**共用同一套搜索索引**，重复的词是纯浪费
> （Apple 会去重，重复词不带来任何排名收益）。下面的关键词**刻意不含**副标题里已有的词。

---

## 1. 名称（≤30）

```
钱伲
```

已定，见 `appstore_naming_rules`：iOS = 钱伲，Mac = Qianey，同账户内两条记录不能同名。

---

## 2. 副标题（≤30）

**中文（15 字符）**

```
隐私优先的手记账本，家庭共享
```

**英文（26 字符）**

```
Private manual bookkeeping
```

> 英文备选：`Manual bookkeeping, shared`（26 字符，换掉「隐私」保「共享」）。
> 30 字符装不下 privacy + manual + shared 三个词，必须舍一个。
> 中文版把三个卖点都塞进去了，是因为中文字符信息密度高——这是中英文案不能互译的原因之一。

---

## 3. 关键词（≤100，逗号分隔，逗号后**不留空格**）

**中文（96 字符）**

```
记账,个人财务,收支,预算,日常开销,消费记录,理财,存钱,AA,分摊,报销,借贷,流水,报表,离线,无广告,无追踪,共同记账,情侣记账,生活记账,简单记账,攒钱,记账软件,每日记账,支出管理
```

- 不含「手记」「账本」「家庭」「共享」「隐私」——这些词副标题里已经有了，重复无收益
- `AA` / `分摊` / `报销` / `借贷` 对应 App 真实功能（`SplitService` / `reimbursementStatusRaw` / `lendingDirection`）
- `无广告` `无追踪` 为真：全项目零第三方依赖，`PrivacyInfo.xcprivacy` 里 `NSPrivacyTracking = false`
- `离线` 为真：本地 store 优先，无网也能记

**英文（95 字符）**

```
budget,expense,envelope,no ads,privacy,offline,couples,family,net worth,saving,AA,ledger,splits
```

- 不含 `private` `manual` `bookkeeping` —— 英文副标题已占用
- 英文索引空间比中文紧得多：同一个意思，中文 2 个字符、英文要 10 个字母，
  所以英文关键词必然比中文少几个词。这是字符限制造成的，不是遗漏。

---

## 4. 推广文本（≤170，**不参与搜索索引**，但可随时改、无需重新送审）

用来打季节性卖点或近期更新，是唯一能「随时改」的字段。

**中文**

```
不用注册，不用绑定手机号，不接任何第三方 SDK。数据只存在你自己的 iCloud 里，没有广告，也没有追踪。手记的账一笔是一笔，家人可以共享同一本账；预算不用一次做全——先记着，没进预算的开销会单列出来，你再慢慢补。
```

**英文（166 字符）**

```
No sign-up, no third-party SDKs. Your records stay in your own iCloud — no ads, no tracking. Manual entry, one ledger shared with family, a budget you grow gradually.
```

---

## 5. 描述（≤4000，**不参与搜索索引**）

> ⚠️ 描述不索引，所以**不必堆关键词**——它的唯一任务是说服已经点进来的人下载。
> 前 3 行是折叠线以上的内容，最重要。
>
> ⚠️ **描述末尾写了产品方向承诺**（「不打算做自动记账，也不打算做截图识别记账」）。
> 这是**有意为之**：主动筛掉期待自动记账的用户，减少「为什么不能自动导入」的差评。
> 但它是**承诺，会过期**——将来真要上自动记账或截图识别，这**两处必须同步改掉**
> （中文「钱伲适合谁」段、英文 "Who Qianey is for" 段），否则同一份描述自相矛盾。
>
> 措辞口径（别写错）：说的是**方向和重心**，不是「本 App 没有导入能力」——
> 正式包里确实有信用卡账单 CSV 导入（`CreditCardReconciliationView.swift:310`，
> 未包 `#if DEBUG`）。`OCRTestView` 是 DEBUG 专有、正式包不含，所以「不做截图识别记账」成立。

**中文**

```
钱伲是一本你自己的账本。

不用注册，不用绑定手机号，不接任何第三方 SDK。每一笔记录都保存在你自己的 iCloud 私有空间里——没有广告，没有追踪。

■ 记账最难的是坚持，不是功能

钱伲是一本手动记账工具，不是财务分析软件。它不替你去猜钱花在哪，也不把「自动记账」当作方向——它想帮你养成的，是「每一笔都自己记下来」的习惯。所以它把录入压到几秒钟：数字键盘、常用分类、模板、周期账，让「顺手记一笔」真的顺手。记满一个月，你会第一次看清自己的钱到底去了哪。

■ 先记着，预算慢慢补

很多人不做预算，是因为刚开始就要把所有分类填满，太累。钱伲反过来：先记一段时间，预算页会把「没进预算的开销」单独列出来，让你看清钱实际花在哪，再决定哪些该管起来、该给多少。父分类设了总额，子分类还能继续往下分子限额。

■ 一家人的账，一本就够

把账本共享给家人，几个人记的是同一本账。谁花了多少、AA 谁该给谁、谁先垫的钱，都能对清楚。

■ 记得细，也看得清

· 账户：现金、储蓄卡、信用卡、电子钱包统一管理，余额与负债一目了然，信用卡账单还能对账
· 流水：分类、成员、商户、项目四个维度标记，怎么顺手怎么来
· 分摊与借贷：AA 分摊、借出借入、报销状态跟踪，往来账不再含糊
· 周期账与模板：房租、水电、会员这些固定支出设一次，到点自动生成
· 报表：分类占比、收支趋势、资产变化、预算执行、资产配置、多维分析
· 搜索：直接写「2026 餐饮」这样的人话就能搜
· 数据导出：随时把账目导出成文件带走
· App 锁：用面容 ID 或触控 ID 锁住账本

■ 关于隐私，说清楚

· 不需要注册账号，我们拿不到你的手机号、邮箱或任何身份信息
· 数据存放在你自己的 iCloud 私有空间，我们看不到，也无法读取
· 没有广告，没有数据分析 SDK，没有账号体系可供泄露
· App Store 隐私标签：不追踪

■ 钱伲适合谁

适合愿意自己动手记、在意数据归属、需要和家人一起管钱的人。

钱伲的重点始终是手动记账：不打算做自动记账，也不打算做截图识别记账。它想帮你养成的，是「每一笔都自己记下来」的习惯。如果你想把记账完全交给工具自动完成，钱伲不是那个选择——它更安静，也更简单。
```

**英文**

```
Qianey is a ledger that belongs to you.

No sign-up. No phone number. No third-party SDKs. Every record stays in your own private iCloud space — no ads, no tracking.

■ The hard part of bookkeeping is keeping it up

Qianey is a manual bookkeeping tool, not a financial analysis service. It doesn't guess where your money went, and automatic entry isn't where it's heading — it's built to help you form the habit of recording every single expense yourself. So logging one takes seconds: a number pad, your usual categories, templates and recurring entries. Keep it up for a month and you'll see, for the first time, where your money actually goes.

■ Record first, budget later

Most people never build a budget because filling in every category up front is exhausting. Qianey flips it: record for a while, and your budget page lists the spending that isn't budgeted yet. See where the money actually goes, then decide what to cap and at what amount. Set a total on a parent category and split it into sub-limits if you want.

■ One ledger is enough for the whole family

Share a ledger with your family and everyone records into the same book. Who spent what, who owes whom on a split, who fronted the money — all accounted for.

■ Detailed where it matters

· Accounts: cash, debit, credit cards and e-wallets in one place, with balances and liabilities at a glance
· Transactions: tag by category, member, merchant and project
· Splits and lending: AA splits, money lent and borrowed, reimbursement status
· Recurring and templates: rent, utilities, subscriptions — set once and they generate on schedule
· Reports: category breakdown, income vs. expense trend, asset change, budget execution, asset allocation, multi-dimension analysis
· Search: type "2026 groceries" and it understands
· Export: take your records out as a file whenever you like
· App Lock: protect the ledger with Face ID or Touch ID

■ About privacy, plainly

· No account to create. We have no phone number, no email, no identity of yours
· Data lives in your own private iCloud space. We can't see it and can't read it
· No ads, no analytics SDKs, no account system to leak
· App Store privacy label: Data Not Used to Track You

■ Who Qianey is for

People who don't mind entering transactions themselves, who care where their data lives, and who need to manage money together with family.

Qianey stays focused on manual entry: no automatic bookkeeping planned, no screenshot recognition planned. It exists to help you form the habit of recording every expense yourself. If you'd rather hand bookkeeping over to a tool entirely, Qianey isn't that tool — it's quieter, and simpler.
```

---

## 6. 新功能（What's New）

首个版本 ASC 会允许留空或填「首次发布」。建议写一句定位，顺便让老用户（TestFlight）看到价值：

**中文**

```
首次发布。

一本不需要注册、数据只存在你自己 iCloud 里的手记账本。支持家庭共享账本、渐进式预算、AA 分摊与借贷、周期账与模板、六类报表。
```

**英文**

```
First release.

A manual bookkeeping app with no sign-up, where your data stays in your own iCloud. Shared family ledgers, gradual budgeting, AA splits and lending, recurring entries and templates, six report types.
```

---

## 7. ASC 其余必填项（现状）

| 字段 | 状态 | 说明 |
|---|---|---|
| **隐私政策 URL** | 🟡 **页面已成稿，待上线**——送审阻断项 | 页面在 `~/Documents/AI/qianey-legal/privacy.html`（独立公开仓库，不放在本仓库的 `docs/`，原因见下）。建好仓库开 Pages 后填入 |
| **支持 URL** | 🟡 页面已成稿，待上线 | 同上，`~/Documents/AI/qianey-legal/support.html`；不能填 App Store 链接 |
| 营销 URL | 可选 | 无 |
| 分类 | 建议 **财务**（主要）+ 效率（次要） | 竞品多在财务 |
| 内容分级 | 4+ | 素材也必须是 4+，见 README |
| 版权 | 待定 | 一般为开发者/公司名 |
| 价格 | 待定 | 无内购（全项目 0 处 StoreKit），所以是纯买断或免费 |

---

## 待办

- [x] 中英文案定稿，全部字段经 `check_lengths.py` 校验在限内（2026-10-07）
- [ ] **隐私政策 URL / 支持 URL 上线** —— 送审阻断项。页面已写好（见 `~/Documents/AI/qianey-legal/`），
      还差三步：① 替换页面里的 `【支持邮箱】` 和 `【开发者名称】` 占位符；
      ② 在 GitHub 建**公开**仓库 `qianey-legal` 并 push（命令见该目录 README）；
      ③ Settings → Pages 选 `main` / root，拿到 URL 后填进 ASC。
      > ⚠️ 这两个页面**不放本仓库的 `docs/`**：那里已经有 `multi-device-sync-qa.md` 和
      > `pm-testing-issues.md` 两个**内部**文档（后者是待修复 bug 清单），而 GitHub Pages 会
      > 把该目录下的所有文件都公开。
- [ ] 文案改动后**必须重跑** `python3 tools/appstore-assets/check_lengths.py`
- [ ] Mac 端（Qianey）另备一套文案，不能与本套同名同文

> 本文件里的文案改完，务必跑一次校验脚本。它直接解析本文件，不维护第二份副本，
> 所以不会出现「文案改了、校验还是旧的」这种假绿灯。
