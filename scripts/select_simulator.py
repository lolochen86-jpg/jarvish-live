#!/usr/bin/env python3
"""Select an actually installed iPhone simulator, never a guessed model/OS."""
import json
import re
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
sdk = tuple(int(n) for n in sys.argv[2].split(".")[:2])
choices = []
for runtime, devices in data["devices"].items():
    match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
    if not match:
        continue
    version = tuple(int(n or 0) for n in match.groups())
    if version[0] < 17 or version[:2] > sdk:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            choices.append((version, device["name"], device["udid"]))
if not choices:
    raise SystemExit("No available iPhone simulator with iOS >=17 found; inspect devices.json")
version, name, udid = sorted(choices, reverse=True)[0]
print(f"SIMULATOR_ID={udid}")
print(f"SIMULATOR_NAME={name}")
