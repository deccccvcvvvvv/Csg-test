#!/usr/bin/env python3
"""
Unity & Game Asset Patching Diagnostic & Processor
Supports Mode B: Validates patch payloads and identifies required operations
for Unity 2021.3.45f1 IL2CPP targets.
"""

import sys
import os
from pathlib import Path

def inspect_and_route_patches(patch_dir: str):
    patch_path = Path(patch_dir)
    if not patch_path.exists():
        print(f"❌ ERROR: Patch directory does not exist: {patch_dir}", file=sys.stderr)
        return False

    files = list(patch_path.rglob("*"))
    files = [f for f in files if f.is_file()]

    if not files:
        print(f"❌ ERROR: No patch files found in {patch_dir}", file=sys.stderr)
        return False

    print(f"📦 Found {len(files)} patch file(s):")
    operations = []
    unsupported = []

    for f in files:
        rel = f.relative_to(patch_path)
        size_kb = f.stat().st_size / 1024
        print(f"  • {rel} ({size_kb:.1f} KB)")

        suffix = f.suffix.lower()
        rel_str = str(rel)

        if rel_str == "data.unity3d" or rel_str.endswith("data.unity3d"):
            operations.append(("UNITYFS_REPLACE", f, "assets/bin/Data/data.unity3d"))
        elif "libil2cpp.so" in rel_str:
            operations.append(("NATIVE_SO_REPLACE", f, rel_str))
        elif suffix in [".png", ".jpg", ".tga", ".webp"]:
            # Raw image replacement requires UnityFS texture asset injection
            operations.append(("RAW_TEXTURE_INJECT", f, rel_str))
        elif suffix == ".cs":
            unsupported.append((f, "Raw C# source code (.cs) cannot be injected into a compiled IL2CPP APK. Code must be compiled to IL2CPP C++ and binary libil2cpp.so using the Unity 2021.3.45f1 build toolchain."))
        elif suffix == ".dll":
            unsupported.append((f, "Managed .NET assembly DLL cannot be directly added to an IL2CPP project. IL2CPP games execute AOT-compiled native code (libil2cpp.so) with metadata (global-metadata.dat)."))
        elif rel_str.startswith("res/") or rel_str.startswith("assets/"):
            operations.append(("DIRECT_CONTAINER_REPLACE", f, rel_str))
        else:
            operations.append(("DIRECT_ZIP_INJECT", f, rel_str))

    if unsupported:
        print("\n❌ UNSUPPORTED PATCH OPERATIONS DETECTED:", file=sys.stderr)
        for f, reason in unsupported:
            print(f"  - File: {f.name}\n    Reason: {reason}\n", file=sys.stderr)
        print("Build aborted safely to prevent generating a non-functional APK.", file=sys.stderr)
        return False

    print("\n✓ All patch operations mapped to valid Android/Unity packaging pipelines.")
    for op, src, dest in operations:
        print(f"  [Pipeline: {op}] {src.name} -> {dest}")

    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: patch_unity_assets.py <patch_dir>")
        sys.exit(1)

    success = inspect_and_route_patches(sys.argv[1])
    sys.exit(0 if success else 1)
