#!/usr/bin/env python3
"""Fail CI if private mail implementation is copied into community sources."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
forbidden = re.compile(r"\b(?:MailCodeStore|MailCodeExtractor|CMailTransport|MailProvider|TypingStatisticsDetailContent|DevelopmentStatisticsDetailContent|DetailedDailyBarChart|TypingTrendSparkline)\b")
violations = []
for folder in ("Sources", "Tests"):
    for path in (root / folder).rglob("*"):
        if path.is_file() and path.suffix in {".swift", ".c", ".h"} and forbidden.search(path.read_text()):
            violations.append(str(path.relative_to(root)))
if forbidden.search((root / "Package.swift").read_text()):
    violations.append("Package.swift")
if violations:
    raise SystemExit("Private implementation found in community package: " + ", ".join(violations))
print("Community boundary check passed")
