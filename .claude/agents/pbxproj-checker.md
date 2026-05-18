---
name: pbxproj-checker
description: Validate Xcode project file integrity after edits
tools: Bash, Read
---
# pbxproj-checker

Validate this project's pbxproj file for common corruption issues that break builds.

## Checks

1. **Valid plist**: `plutil -lint FirstCC.xcodeproj/project.pbxproj` — must pass silently
2. **No null values**: `grep -c 'null' FirstCC.xcodeproj/project.pbxproj` — JSON round-trip corruption produces literal `null` in plist
3. **File references have build entries**: Compare PBXFileReference paths against PBXBuildFile references — dangling references compile but cause linker errors
4. **No duplicate file IDs**: `grep -oE '[A-F0-9]{24}' FirstCC.xcodeproj/project.pbxproj | sort | uniq -d` — duplicates corrupt the project

Report any issues found with specific lines and suggested fixes.
