#!/usr/bin/env python3
"""Convert Localizable.xcstrings to .lproj/Localizable.strings for iOS bundle."""
import json, os, sys

SRCROOT = os.environ.get('SRCROOT', os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
BUILT_DIR = os.environ.get('BUILT_PRODUCTS_DIR', '/tmp/firstcc-build/Build/Products/Debug-iphonesimulator/钱伲.app')

xc_path = os.path.join(SRCROOT, 'FirstCC', 'Resources', 'Localizable.xcstrings')

with open(xc_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for lang in ['en', 'zh-Hans']:
    lproj_dir = os.path.join(BUILT_DIR, f'{lang}.lproj')
    os.makedirs(lproj_dir, exist_ok=True)

    strings_path = os.path.join(lproj_dir, 'Localizable.strings')
    with open(strings_path, 'w', encoding='utf-8') as out:
        for key, entry in data['strings'].items():
            localizations = entry.get('localizations', {})
            lang_entry = localizations.get(lang, localizations.get('zh-Hans'))
            if not lang_entry:
                continue
            value = lang_entry.get('stringUnit', {}).get('value')
            if value is None:
                continue

            # Escape for .strings format: \ → \\, " → \", newline → \n
            escaped_key = key.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
            escaped_value = value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
            out.write(f'"{escaped_key}" = "{escaped_value}";\n')

    count = len(data['strings'])
    print(f"Generated {strings_path} ({count} entries)")

# Remove raw xcstrings from bundle (iOS reads .lproj/.strings, not raw xcstrings)
raw_xc = os.path.join(BUILT_DIR, 'Localizable.xcstrings')
if os.path.exists(raw_xc):
    os.remove(raw_xc)
