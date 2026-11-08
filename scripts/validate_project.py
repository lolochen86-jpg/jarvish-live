#!/usr/bin/env python3
"""Source/plist checks only. A passing result is not an Xcode build."""
import plistlib
from pathlib import Path
from xml.etree import ElementTree as ET

root = Path(__file__).resolve().parents[1]
info = plistlib.loads((root / "JARVISHLive/Info.plist").read_bytes())
assert info["NSLocalNetworkUsageDescription"]
assert set(info["NSBonjourServices"]) == {"_http._tcp", "_https._tcp", "_rtsp._tcp"}
assert "NSAppTransportSecurity" not in info
assert "UIBackgroundModes" not in info
assert not list(root.glob("**/*.entitlements"))
privacy = plistlib.loads((root / "JARVISHLive/PrivacyInfo.xcprivacy").read_bytes())
assert privacy["NSPrivacyTracking"] is False
scheme = ET.parse(root / "JARVISHLive.xcodeproj/xcshareddata/xcschemes/JARVISHLive.xcscheme")
assert len(scheme.findall(".//TestableReference")) == 2
project = (root / "JARVISHLive.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
for folder in ("JARVISHLive", "JARVISHLiveTests", "JARVISHLiveUITests"):
    sources = list((root / folder).glob("*.swift"))
    assert sources, folder
    for source in sources:
        assert source.name in project, f"Missing project membership: {source}"
        source.read_text(encoding="utf-8")
print("PASS: source membership, shared test scheme, plist/privacy declarations (static only)")
