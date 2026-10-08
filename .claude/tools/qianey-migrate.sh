#!/bin/zsh
# 钱伲：把「生产库」单向搬迁成「调试库」（手动、显式、只读源）
#
# 背景：Debug 构建跑在 CloudKit **Development** 环境，生产版（TestFlight / App Store）
# 跑在 **Production**；两者用不同的本地库文件（`CoreDataStack.swift` 里的 `#if DEBUG`）。
# 所以想用真实数据调试时，必须手工把生产库搬一份进调试库 —— 只允许这个方向。
#
# 用法：
#   .claude/tools/qianey-migrate.sh                     # 生成 ~/Desktop/FirstCC.debug.sqlite，只生成不安装
#   .claude/tools/qianey-migrate.sh --install           # 生成后安装到 App 容器的调试库位置
#   .claude/tools/qianey-migrate.sh --from <生产库路径> # 用外部快照当源（此时不要求 App 已退出）
#   .claude/tools/qianey-migrate.sh --out <输出路径>
#
# 做的事：
#   1. 「活的」生产库作源时，要求钱伲（Mac 版）未在运行；且**只读**源，从不写回
#   2. 拷贝（含 -wal/-shm）到临时目录并 checkpoint
#   3. 清空所有 ANSCK* 同步元数据表 + 持久化历史三表
#      ← 关键：否则调试库会带着指向生产环境的 change token，首次连 Development 触发全量重取重推
#   4. VACUUM、integrity_check、行数与期初抽查
#   5. （可选）安装到容器的 FirstCC.debug.sqlite —— 写入前强制校验目标名含 .debug
#
# ⚠️ 本脚本**永不**写入 FirstCC.sqlite / FirstCC.shared.sqlite（生产库）。
set -euo pipefail

SRC_DIR="$HOME/Library/Containers/com.qianey.app.mac.Qianeymac/Data/Library/Application Support"
SRC="$SRC_DIR/FirstCC.sqlite"
DESKTOP_OUT="$HOME/Desktop/FirstCC.debug.sqlite"
INSTALL=0
FROM=""
OUT_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --from) FROM="$2"; shift 2 ;;
    --out)  OUT_OVERRIDE="$2"; shift 2 ;;
    *) print -r -- "未知参数: $1"; exit 1 ;;
  esac
done
[[ -n "$FROM" ]] && SRC="$FROM"
[[ -n "$OUT_OVERRIDE" ]] && DESKTOP_OUT="$OUT_OVERRIDE"

# CloudKit 同步元数据表的前缀（ANSCK*），下面查/删/校验都用它。
ANSCK_LIKE="ANSCK%"

say() { print -r -- "$@" }

# ---- 0. 硬闸：任何写入目标都必须带 .debug ----
# 生产库叫 FirstCC.sqlite / FirstCC.shared.sqlite，不含 ".debug"，因此物理上不可能被覆盖。
guard_debug_path() {
  case "$1" in
    *".debug.sqlite") ;;
    *) say "✗ 拒绝写入：${1}"; say "  安全闸：目标文件名必须含 .debug.sqlite（生产库不带这个后缀）。"; exit 1 ;;
  esac
}
guard_debug_path "$DESKTOP_OUT"

# ---- 1. 前置检查 ----
if [[ -z "$FROM" ]] && pgrep -f "Qianey.app/Contents/MacOS/Qianey" >/dev/null 2>&1; then
  say "✗ 钱伲（Mac 版）正在运行，请先退出再执行（或用 --from 指定一份外部快照）。"; exit 1
fi
[[ -f "$SRC" ]] || { say "✗ 找不到源库：$SRC"; exit 1; }

WORK=$(mktemp -d /tmp/qianey-migrate.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
say "源库: $SRC"
say "  大小: $(stat -f '%z' "$SRC") bytes  修改: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$SRC")"

# ---- 2. 只读拷贝 ----
cp "$SRC" "$WORK/FirstCC.sqlite"
for ext in -wal -shm; do [[ -f "$SRC$ext" ]] && cp "$SRC$ext" "$WORK/FirstCC.sqlite$ext"; done
DB="$WORK/FirstCC.sqlite"
sqlite3 "$DB" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null

q() { sqlite3 -noheader "$DB" "$1"; }
say ""
say "【搬迁前】"
for t in ZACCOUNT ZTRANSACTION ZLEDGER ZBUDGETITEM ZRECURRINGRULE ZCATEGORY ZMEMBER; do
  printf "  %-16s %s\n" "$t" "$(q "select count(*) from $t;")"
done
printf "  %-16s %s（待清空）\n" "ANSCK* 表" "$(q "select count(*) from sqlite_master where type='table' and name like '$ANSCK_LIKE';")"

# 业务数据指纹：搬迁**只该**动同步元数据与持久化历史，业务表必须逐项不变。
# 用「数 + 合计」而不是具体主键——`Z_PK` 每次安装各自分配，写死主键换一份源库就查不到、只会打空行。
bizfp() {
  q "select (select count(*) from ZACCOUNT)||'|'||(select count(*) from ZTRANSACTION)||'|'||
            (select printf('%.2f', coalesce(sum(ZINITIALBALANCEINFEN),0)/100.0) from ZACCOUNT)||'|'||
            (select printf('%.2f', coalesce(sum(ZAMOUNTINFEN),0)/100.0) from ZTRANSACTION);"
}
BIZ_BEFORE=$(bizfp)
say "  业务指纹 账户数|交易数|期初合计|交易额合计: $BIZ_BEFORE"

# ---- 3. 清空同步元数据 + 持久化历史 ----
{
  print "PRAGMA foreign_keys=OFF;"
  q "select 'DELETE FROM \"'||name||'\";' from sqlite_master where type='table' and name like '$ANSCK_LIKE';"
  print "DELETE FROM ACHANGE; DELETE FROM ATRANSACTION; DELETE FROM ATRANSACTIONSTRING;"
  print "VACUUM;"
} | sqlite3 "$DB"

say ""
say "【搬迁后】"
ANSCK_TABLES=$(q "select count(*) from sqlite_master where type='table' and name like '$ANSCK_LIKE';")
ANSCK_ROWS=0
for t in $(q "select name from sqlite_master where type='table' and name like '$ANSCK_LIKE';"); do
  ANSCK_ROWS=$(( ANSCK_ROWS + $(q "select count(*) from \"$t\";") ))
done
say "  ANSCK* 表 $ANSCK_TABLES 张，残留行数合计 $ANSCK_ROWS（应为 0）"
# 三张持久化历史表都要查 —— 删的是三张（见上面那段 DELETE），少查一张就等于断言漏了一半。
say "  持久化历史残留: $(( $(q 'select count(*) from ACHANGE;') + $(q 'select count(*) from ATRANSACTION;') + $(q 'select count(*) from ATRANSACTIONSTRING;') ))（应为 0）"
say "  完整性检查: $(q 'PRAGMA integrity_check;')"
BIZ_AFTER=$(bizfp)
say "  业务指纹 账户数|交易数|期初合计|交易额合计: $BIZ_AFTER"
if [[ "$BIZ_BEFORE" == "$BIZ_AFTER" ]]; then
  say "  ✓ 业务数据未变（只清了同步元数据与持久化历史）"
else
  say "  ✗ 业务数据被打动了，已中止、未写任何输出："
  say "      搬迁前 $BIZ_BEFORE"
  say "      搬迁后 $BIZ_AFTER"
  exit 1
fi

# 外部二进制资源（附件/照片）按 <store 名>_ckAssets 存放；当前为空
ASSETS="$SRC_DIR/FirstCC_ckAssets"
ASSET_N=$(ls -A "$ASSETS" 2>/dev/null | wc -l | tr -d ' ')
say "  附件资源 FirstCC_ckAssets: $ASSET_N 个文件"
if [[ "$ASSET_N" != "0" ]]; then
  say "  ⚠ 该目录非空：搬迁后调试库读不到这些附件。如需一并搬运，"
  say "     手动 cp -R \"$ASSETS\" \"$SRC_DIR/FirstCC.debug_ckAssets\""
  say "     （FirstCC_ckAssets 这个目录名按 store 文件名派生，属**推断未实测**；搬完请确认调试库里附件能打开）"
fi

# ---- 4. 输出 ----
cp "$DB" "$DESKTOP_OUT"
say ""
say "✓ 已生成: $DESKTOP_OUT  ($(stat -f '%z' "$DESKTOP_OUT") bytes)"

if [[ $INSTALL -eq 1 ]]; then
  TARGET="$SRC_DIR/FirstCC.debug.sqlite"
  guard_debug_path "$TARGET"
  if [[ -f "$TARGET" ]]; then
    BAK="$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$TARGET" "$BAK"; say "  已备份旧调试库 → $BAK"
  fi
  cp "$DB" "$TARGET"
  rm -f "$TARGET-wal" "$TARGET-shm"
  say "✓ 已安装: $TARGET"
  say "  下一步：正常打开 **Debug 版**钱伲（它连 Development 环境），首次会把这批记录整体上传到 Development。"
else
  say "  下一步：确认无误后加 --install 安装到容器，或用 Finder 手动改名放入。"
fi
