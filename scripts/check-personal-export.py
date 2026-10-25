#!/usr/bin/env python3
"""Reject Personal export/upload options that permit external distribution."""
import plistlib
import sys
from pathlib import Path


def check(path):
    with Path(path).open("rb") as source:
        options = plistlib.load(source)
    if options.get("testFlightInternalTestingOnly") is not True:
        raise ValueError("Personal export/upload requires testFlightInternalTestingOnly=true")


if __name__ == "__main__":
    for path in sys.argv[1:] or [Path(__file__).resolve().parents[1] / "docs/release/ExportOptions-Personal.plist"]:
        check(path)
    print("Personal export/upload is internal-only")
