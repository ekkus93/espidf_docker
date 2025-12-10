#!/usr/bin/env python3
"""Invoke esptool.py inside the ESP-IDF Docker image.

This piggybacks on the existing idf.py wrapper, so any environment variables
(like IDF_IMAGE) or Docker-related settings honored by idf.py apply here too.
"""

import os
import sys
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
IDF_WRAPPER = os.path.join(SCRIPT_DIR, "idf.py")


def main() -> None:
    if not os.path.exists(IDF_WRAPPER):
        sys.stderr.write(f"Error: idf.py wrapper not found at {IDF_WRAPPER}\n")
        sys.exit(1)

    # Use the same Python interpreter to run idf.py, then forward to esptool.py
    cmd = [sys.executable, IDF_WRAPPER, "--", "esptool.py", *sys.argv[1:]]
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
