#!/usr/bin/env python3
"""Generate Xcode project.pbxproj in JSON format for Xcode 26 compatibility."""

import os, hashlib, json

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))

def uid(s: str) -> str:
    return hashlib.md5(s.encode()).hexdigest()[:24].upper()

base = os.path.join(PROJECT_ROOT, "FirstCC")
files = []
for root, dirs, fnames in os.walk(base):
    dirs[:] = [d for d in dirs if not d.startswith("Preview")]
    for f in sorted(fnames):
        if f.endswith(".swift") or f.endswith(".json"):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, PROJECT_ROOT)
            grp = os.path.relpath(full, base)
            group_parts = ["FirstCC"] + grp.split("/")[:-1]
            files.append((rel, grp, group_parts))

file_refs = {}
for rel, grp, group_parts in files:
    file_refs[rel] = (uid(f"FR:{rel}"), uid(f"BF:{rel}"))

groups_set = set()
for _, _, gps in files:
    for i in range(len(gps)):
        groups_set.add("/".join(gps[:i+1]))
groups = sorted(groups_set, key=lambda x: (x.count("/"), x))
group_ids = {g: uid(f"GRP:{g}") for g in groups}

# Key IDs
project_id = uid("PROJECT")
main_group_id = uid("MAINGROUP")
firstcc_group_id = uid("GRP:FirstCC")
target_id = uid("TARGET")
product_ref_id = uid("PRODUCTREF")
product_group_id = uid("GRP:Products")
sources_phase_id = uid("SOURCESPHASE")
frameworks_phase_id = uid("FRAMEWORKSPHASE")
resources_phase_id = uid("RESOURCESPHASE")
debug_conf_id = uid("DEBUGCONF")
release_conf_id = uid("RELEASECONF")
debug_target_conf_id = uid("DEBUGCONF_TARGET")
release_target_conf_id = uid("RELEASECONF_TARGET")
build_conf_list_id = uid("BCL_PROJECT")
build_conf_list_target_id = uid("BCL_TARGET")

asset_rel = "FirstCC/Resources/Assets.xcassets"
assets_ref_id = uid(f"FR:{asset_rel}")
assets_bf_id = uid(f"BF:{asset_rel}")

default_cat_rel = "FirstCC/Resources/DefaultCategories.json"
if os.path.exists(os.path.join(PROJECT_ROOT, default_cat_rel)):
    default_cat_fr_id = uid(f"FR:{default_cat_rel}")
    default_cat_bf_id = uid(f"BF:{default_cat_rel}")

objects = {}

# ---- PBXBuildFile ----
for rel, _, _ in files:
    _, bfid = file_refs[rel]
    objects[bfid] = {"isa": "PBXBuildFile", "fileRef": file_refs[rel][0]}
objects[assets_bf_id] = {"isa": "PBXBuildFile", "fileRef": assets_ref_id}
if 'default_cat_bf_id' in dir():
    objects[default_cat_bf_id] = {"isa": "PBXBuildFile", "fileRef": default_cat_fr_id}

# ---- PBXFileReference ----
objects[product_ref_id] = {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.application",
    "includeInIndex": "0",
    "path": "荡漾计然.app",
    "sourceTree": "BUILT_PRODUCTS_DIR",
}
for rel, _, _ in files:
    fid, _ = file_refs[rel]
    ext = os.path.splitext(rel)[1]
    file_type = "sourcecode.swift" if ext == ".swift" else "text.json"
    objects[fid] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": file_type,
        "path": os.path.basename(rel),
        "sourceTree": "<group>",
    }
objects[assets_ref_id] = {
    "isa": "PBXFileReference",
    "lastKnownFileType": "folder.assetcatalog",
    "path": "Assets.xcassets",
    "sourceTree": "<group>",
}
if 'default_cat_fr_id' in dir():
    objects[default_cat_fr_id] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "text.json",
        "path": "DefaultCategories.json",
        "sourceTree": "<group>",
    }

# ---- PBXFrameworksBuildPhase ----
objects[frameworks_phase_id] = {
    "isa": "PBXFrameworksBuildPhase",
    "buildActionMask": "2147483647",
    "files": [],
    "runOnlyForDeploymentPostprocessing": "0",
}

# ---- PBXGroup ----
objects[main_group_id] = {
    "isa": "PBXGroup",
    "children": [firstcc_group_id, product_group_id],
    "sourceTree": "<group>",
}

objects[product_group_id] = {
    "isa": "PBXGroup",
    "children": [product_ref_id],
    "name": "Products",
    "sourceTree": "<group>",
}

for group in groups:
    gid = group_ids[group]
    last = group.split("/")[-1]
    path = last if group != "FirstCC" else "FirstCC"
    st = "<group>"

    children = []
    for g in groups:
        if g == group: continue
        if "/".join(g.split("/")[:-1]) == group:
            children.append(group_ids[g])
    for rel, _, gps in files:
        if "/".join(gps) == group:
            children.append(file_refs[rel][0])

    if group == "FirstCC/Resources":
        children.append(assets_ref_id)
        if 'default_cat_fr_id' in dir():
            children.append(default_cat_fr_id)

    objects[gid] = {
        "isa": "PBXGroup",
        "children": children,
        "name": last,
        "path": path,
        "sourceTree": st,
    }

# ---- PBXNativeTarget ----
objects[target_id] = {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": build_conf_list_target_id,
    "buildPhases": [sources_phase_id, frameworks_phase_id, resources_phase_id],
    "buildRules": [],
    "dependencies": [],
    "name": "荡漾计然",
    "productName": "荡漾计然",
    "productReference": product_ref_id,
    "productType": "com.apple.product-type.application",
}

# ---- PBXProject ----
objects[project_id] = {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "2600",
        "LastUpgradeCheck": "2600",
        "TargetAttributes": {
            target_id: {"CreatedOnToolsVersion": "26.4.1"}
        }
    },
    "buildConfigurationList": build_conf_list_id,
    "compatibilityVersion": "Xcode 16.0",
    "developmentRegion": "zh-Hans",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "zh-Hans", "zh-Hant"],
    "mainGroup": main_group_id,
    "productRefGroup": product_group_id,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [target_id],
}

# ---- PBXResourcesBuildPhase ----
res_files = [assets_bf_id]
if 'default_cat_bf_id' in dir():
    res_files.append(default_cat_bf_id)
objects[resources_phase_id] = {
    "isa": "PBXResourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": res_files,
    "runOnlyForDeploymentPostprocessing": "0",
}

# ---- PBXSourcesBuildPhase ----
objects[sources_phase_id] = {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [file_refs[rel][1] for rel, _, _ in files if rel.endswith(".swift")],
    "runOnlyForDeploymentPostprocessing": "0",
}

# ---- XCBuildConfiguration ----
def proj_settings(debug=True):
    s = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWRITE_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "SDKROOT": "iphoneos",
    }
    if debug:
        s.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "MTL_FAST_MATH": "YES",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        })
    else:
        s.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "MTL_FAST_MATH": "YES",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "VALIDATE_PRODUCT": "YES",
        })
    return s

target_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.firstcc.app",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
}

objects[debug_conf_id] = {"isa": "XCBuildConfiguration", "buildSettings": proj_settings(True), "name": "Debug"}
objects[release_conf_id] = {"isa": "XCBuildConfiguration", "buildSettings": proj_settings(False), "name": "Release"}
objects[debug_target_conf_id] = {"isa": "XCBuildConfiguration", "buildSettings": target_settings, "name": "Debug"}
objects[release_target_conf_id] = {"isa": "XCBuildConfiguration", "buildSettings": target_settings, "name": "Release"}

# ---- XCConfigurationList ----
objects[build_conf_list_id] = {
    "isa": "XCConfigurationList",
    "buildConfigurations": [debug_conf_id, release_conf_id],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release",
}
objects[build_conf_list_target_id] = {
    "isa": "XCConfigurationList",
    "buildConfigurations": [debug_target_conf_id, release_target_conf_id],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release",
}

# ---- Root ----
root = {
    "archiveVersion": "1",
    "classes": {},
    "objectVersion": "77",
    "objects": objects,
    "rootObject": project_id,
}

pbxproj_dir = os.path.join(PROJECT_ROOT, "FirstCC.xcodeproj")
os.makedirs(pbxproj_dir, exist_ok=True)
pbxproj_path = os.path.join(pbxproj_dir, "project.pbxproj")
with open(pbxproj_path, "w") as f:
    json.dump(root, f, indent=2)

print(f"Generated {pbxproj_path}")
print(f"Source files: {len([r for r,_,_ in files if r.endswith('.swift')])}")
