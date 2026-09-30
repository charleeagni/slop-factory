#!/usr/bin/env python3
"""Check tracked files and reachable history without printing matched values."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def git(*args):
    return subprocess.check_output(["git", *args])


def private_content(path, data):
    text = data.decode("utf-8", errors="replace")
    rules = {
        "personal home directory": r"/(?:Users|home)/(?!REDACTED(?:/|\b))[^/\s\"'`]+",
    }
    if path.startswith("docs/"):
        rules["personal email in evidence"] = (
            r"[A-Za-z0-9._%+-]+@(?:gmail\.com|outlook\.com|hotmail\.com|icloud\.com|yahoo\.com)\b"
        )
    return [label for label, pattern in rules.items() if re.search(pattern, text)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--working-tree-only", action="store_true")
    parser.add_argument("--gitleaks", default="gitleaks")
    args = parser.parse_args()
    root = Path(git("rev-parse", "--show-toplevel").decode().strip())
    findings = set()
    files = [p.decode() for p in git("ls-files", "-z").split(b"\0") if p]
    with tempfile.TemporaryDirectory(prefix="slop-public-scan-") as directory:
        export = Path(directory)
        for name in files:
            source = root / name
            if not source.is_file() or source.is_symlink():
                raise RuntimeError(f"Cannot scan tracked file: {name}")
            data = source.read_bytes()
            target = export / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            for label in private_content(name, data):
                findings.add(("working tree", name, label))
        result = subprocess.run([
            args.gitleaks, "dir", str(export), "--config", str(root / ".gitleaks.toml"),
            "--redact", "--no-banner", "--ignore-gitleaks-allow",
        ])
    failed = result.returncode != 0
    blobs = 0
    if not args.working_tree_only:
        result = subprocess.run([
            args.gitleaks, "git", str(root), "--log-opts=--all", "--redact",
            "--no-banner", "--ignore-gitleaks-allow", "--config", str(root / ".gitleaks.toml"),
        ])
        failed |= result.returncode != 0
        for entry in git("rev-list", "--objects", "--all").splitlines():
            oid, _, path = entry.partition(b" ")
            if git("cat-file", "-t", oid.decode()).strip() != b"blob":
                continue
            blobs += 1
            name = path.decode()
            for label in private_content(name, git("cat-file", "blob", oid.decode())):
                findings.add(("history", name, label))
    for scope, name, label in sorted(findings):
        print(f"FAIL: {scope}: {name}: {label}")
    print(f"Checked {len(files)} tracked files and {blobs} historical blobs.")
    return int(failed or bool(findings))


if __name__ == "__main__":
    sys.exit(main())
