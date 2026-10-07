#!/usr/bin/env python3
"""校验 metadata.md 里各字段是否超 App Store Connect 上限。

直接解析 metadata.md，不重复维护一份文案——避免文案改了、校验脚本没跟着改。
字段上限来自 ASC，超一个字符就提交不了，所以这个脚本是发布前的最后一道闸。

用法：python3 tools/appstore-assets/check_lengths.py
退出码非 0 表示有字段超标。
"""

import re
import sys
import unicodedata
from pathlib import Path

# App Store Connect 字段上限（字符数）
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotional": 170,
    "description": 4000,
    "whatsnew": 4000,
}

HERE = Path(__file__).resolve().parent
MD = HERE / "metadata.md"


def char_count(s: str) -> int:
    """按 Apple 口径数「字符」。

    中文一个字算 1。这里用「组合字符」计数（grapheme-ish 近似）：
    把组合记号并入前一字符，避免带声调符号的拉丁字母被多算。
    """
    return len([c for c in unicodedata.normalize("NFC", s) if not unicodedata.combining(c)])


def parse(md_text: str):
    """从 markdown 里抽出 (字段名, 语言, 文本)。

    规则：以 `## N. 标题` 分段，段内每个 ``` 代码块算一个字段值，
    按出现顺序依次归为 zh / en。
    """
    # 章节标题 -> 字段 key
    section_map = {
        "名称": "name",
        "副标题": "subtitle",
        "关键词": "keywords",
        "推广文本": "promotional",
        "描述": "description",
        "新功能": "whatsnew",
    }

    out = []
    current = None
    for block in re.split(r"^##\s+", md_text, flags=re.M)[1:]:
        title = block.split("\n", 1)[0]
        key = next((v for k, v in section_map.items() if k in title), None)
        if not key:
            continue
        # 该章节里的所有 ``` 代码块
        bodies = re.findall(r"```[a-z]*\n(.*?)```", block, flags=re.S)
        for i, body in enumerate(bodies):
            lang = "zh" if i == 0 else "en" if i == 1 else f"#{i+1}"
            out.append((key, lang, body.strip()))
    return out


def main() -> int:
    if not MD.exists():
        print(f"找不到 {MD}")
        return 2

    entries = parse(MD.read_text(encoding="utf-8"))
    if not entries:
        print("没解析出任何字段，检查 metadata.md 的标题格式")
        return 2

    failed = False
    print(f"{'字段':<14}{'语言':<6}{'长度':>6}{'上限':>6}   状态")
    print("-" * 46)
    for key, lang, text in entries:
        limit = LIMITS.get(key)
        n = char_count(text)
        if limit is None:
            status = "（无上限）"
        elif n > limit:
            status = f"❌ 超 {n - limit}"
            failed = True
        elif n == limit:
            status = "⚠️ 正好卡满"
        else:
            status = f"✓ 余 {limit - n}"
        print(f"{key:<14}{lang:<6}{n:>6}{limit if limit else '-':>6}   {status}")

    print()
    if failed:
        print("有字段超标，ASC 会拒绝提交。")
        return 1
    print("全部在限内。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
