#!/usr/bin/env python3
"""Regenerates MANIFEST.sha256 for PawsOff.

Enforces strict exclusion of runtime, build, and private artifacts.
"""

from __future__ import annotations

import hashlib
import fnmatch
import os
import subprocess
import sys
from pathlib import Path
from typing import List, Set

ROOT = Path(__file__).resolve().parents[1]

EXCLUDED_EXACT_NAMES = {
    "MANIFEST.sha256",
    ".DS_Store",
    "Thumbs.db",
    "instance.lock",
}

EXCLUDED_DIR_PATTERNS = {
    ".git",
    ".build",
    "dist",
    "DerivedData",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    "build",
    "runs",
    "runtime",
    "*.egg-info",
    ".eggs",
    ".venv",
    "venv",
}

EXCLUDED_FILE_PATTERNS = {
    ".env*",
    "credentials*.json",
    "token*.json",
    "*.pem",
    "*.key",
    "*.pfx",
    "*.pyc",
    "*.pyo",
    "*.pyd",
    "*.so",
    "*.dylib",
    "*.dSYM",
    "*.o",
    "*.tmp",
}


def _is_excluded(rel_path: str) -> bool:
    parts = Path(rel_path).parts
    filename = parts[-1]

    if filename in EXCLUDED_EXACT_NAMES:
        return True

    for pattern in EXCLUDED_FILE_PATTERNS:
        if fnmatch.fnmatch(filename, pattern):
            return True

    for part in parts[:-1]:
        for dir_pat in EXCLUDED_DIR_PATTERNS:
            if fnmatch.fnmatch(part, dir_pat):
                return True

    return False


def get_release_files() -> List[str]:
    files: Set[str] = set()

    # 1. Primary: Use Git ls-files with null delimiters to respect tracked inventory
    git_dir = ROOT / ".git"
    if git_dir.exists():
        try:
            tracked_res = subprocess.run(
                ["git", "-C", str(ROOT), "ls-files", "-z"],
                capture_output=True,
                check=True,
            )
            for raw in tracked_res.stdout.split(b"\x00"):
                if not raw:
                    continue
                rel = raw.decode("utf-8", errors="replace")
                if not _is_excluded(rel):
                    files.add(rel)

            if files:
                return sorted(files)
        except Exception as e:
            raise RuntimeError(f"Git tracked inventory query failed: {e}") from e

    # 2. Rebuilding in a non-git release archive: strictly enforce existing MANIFEST.sha256 membership
    manifest_path = ROOT / MANIFEST_FILE
    if manifest_path.exists():
        with open(manifest_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("  ", 1)
                if len(parts) == 2:
                    rel = parts[1]
                    p = ROOT / rel
                    if p.is_file() and not _is_excluded(rel):
                        files.add(rel)
        if files:
            return sorted(files)

    # 3. Explicit refusal: do not blindly scoop up unreviewed files
    raise RuntimeError(
        "Cannot determine release inventory: not a valid Git repository and no existing MANIFEST.sha256 found. "
        "Strict tracked inventory or explicit manifest custody is required."
    )


def main() -> int:
    files = get_release_files()
    lines = []
    for rel in files:
        p = ROOT / rel
        if not p.is_file():
            continue
        # Verify file does not escape ROOT
        try:
            p.resolve().relative_to(ROOT.resolve())
        except ValueError:
            print(f"Error: Path {rel} escapes package root!", file=sys.stderr)
            return 1
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        lines.append(f"{digest}  {rel}\n")

    lines.sort(key=lambda x: x.split("  ")[1])
    manifest_path = ROOT / "MANIFEST.sha256"
    manifest_path.write_text("".join(lines), encoding="utf-8")
    print(f"Wrote {len(lines)} file hashes to {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
