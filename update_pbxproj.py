#!/usr/bin/env python3
import uuid
import re

pbxproj_path = "SummerSpark.xcodeproj/project.pbxproj"

# 新增的Swift文件及其相对路径
new_files = {
    "UsernameValidator.swift": "src/Modules/Identity/UsernameValidator.swift",
    "GroupVoiceMixer.swift": "src/Modules/Voice/GroupVoiceMixer.swift",
    "LocationManager.swift": "src/Modules/Location/LocationManager.swift",
    "TrackRecorder.swift": "src/Modules/Location/TrackRecorder.swift",
    "CoordinateTransformer.swift": "src/Shared/Utils/CoordinateTransformer.swift",
    "ContourRenderer.swift": "src/Modules/Map/ContourRenderer.swift",
}

# 生成UUID (24位大写十六进制)
def gen_uuid():
    return uuid.uuid4().hex[:24].upper()

# 为每个文件生成UUID
file_refs = {}
build_files = {}
for name in new_files:
    file_refs[name] = gen_uuid()
    build_files[name] = gen_uuid()

# 读取原始内容
with open(pbxproj_path, 'r', encoding='utf-8') as f:
    pbx_content = f.read()

print(f"Read {len(pbx_content)} chars from pbxproj")

# 1. 在PBXBuildFile section末尾添加
build_file_section_end = "/* End PBXBuildFile section */"
build_file_entries = ""
for name in new_files:
    build_file_entries += f"\t\t{build_files[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[name]} /* {name} */; }};\n"

pbx_content = pbx_content.replace(
    build_file_section_end,
    build_file_entries + build_file_section_end
)

# 2. 在PBXFileReference section末尾添加 - 使用完整路径
file_ref_section_end = "/* End PBXFileReference section */"
file_ref_entries = ""
for name, path in new_files.items():
    file_ref_entries += f"\t\t{file_refs[name]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = \"<group>\"; }};\n"

pbx_content = pbx_content.replace(
    file_ref_section_end,
    file_ref_entries + file_ref_section_end
)

# 3. 在PBXSourcesBuildPhase的files数组中添加
pattern = r'(isa = PBXSourcesBuildPhase;[^}]*?files = \(\n)'
match = re.search(pattern, pbx_content, re.DOTALL)

if match:
    insert_pos = match.end()
    build_file_refs = ""
    for name in new_files:
        build_file_refs += f"\t\t\t\t{build_files[name]} /* {name} in Sources */,\n"
    
    pbx_content = pbx_content[:insert_pos] + build_file_refs + pbx_content[insert_pos:]
    print("✅ Found PBXSourcesBuildPhase and inserted files")
else:
    print("ERROR: Could not find PBXSourcesBuildPhase")

# 写回文件
with open(pbxproj_path, 'w', encoding='utf-8') as f:
    f.write(pbx_content)

print(f"✅ Wrote {len(pbx_content)} chars to pbxproj")
for name, path in new_files.items():
    print(f"  Added: {path}")
