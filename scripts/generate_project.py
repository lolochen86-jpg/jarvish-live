#!/usr/bin/env python3
"""Generate a dependency-free, deterministic Xcode project and shared scheme."""
import hashlib
import json
import plistlib
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NAME = "JARVISHLive"
objects = {}


def ident(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()


def add(label, isa, **fields):
    key = ident(label)
    objects[key] = {"isa": isa, **fields}
    return key


def render(value, indent=0):
    if isinstance(value, dict):
        body = "\n".join("\t" * (indent + 1) + json.dumps(k) + " = " + render(v, indent + 1) + ";" for k, v in value.items())
        return "{\n" + body + "\n" + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(render(v, indent) for v in value) + ")"
    return json.dumps(str(value))


def config_list(label, settings):
    configs = []
    for mode in ("Debug", "Release"):
        values = dict(settings)
        values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if mode == "Debug" else "-O"
        if mode == "Debug":
            values["ENABLE_TESTABILITY"] = "YES"
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
        configs.append(add(label + mode, "XCBuildConfiguration", name=mode, buildSettings=values))
    return add(label + "Configs", "XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


project_id = ident("Project")
products = []
groups = []
targets = []
app_id = ident(NAME + "Target")
for target, product_type, ext in [
    (NAME, "com.apple.product-type.application", "app"),
    (NAME + "Tests", "com.apple.product-type.bundle.unit-test", "xctest"),
    (NAME + "UITests", "com.apple.product-type.bundle.ui-testing", "xctest"),
]:
    files, sources, resources = [], [], []
    for path in sorted((ROOT / target).iterdir()):
        if not path.is_file():
            continue
        file_type = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".xcprivacy": "text.xml"}.get(path.suffix)
        if not file_type:
            continue
        ref = add(str(path.relative_to(ROOT)), "PBXFileReference", lastKnownFileType=file_type,
                  path=path.name, sourceTree="<group>")
        files.append(ref)
        if path.suffix in (".swift", ".xcprivacy"):
            build = add(str(path.relative_to(ROOT)) + "Build", "PBXBuildFile", fileRef=ref)
            (sources if path.suffix == ".swift" else resources).append(build)
    groups.append(add(target + "Group", "PBXGroup", children=files, path=target, sourceTree="<group>"))
    product = add(target + "Product", "PBXFileReference", explicitFileType="wrapper.application" if ext == "app" else "wrapper.cfbundle",
                  includeInIndex="0", path=target + "." + ext, sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    phases = [add(target + "Sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=sources, runOnlyForDeploymentPostprocessing="0"),
              add(target + "Frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0"),
              add(target + "Resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=resources, runOnlyForDeploymentPostprocessing="0")]
    settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "org.example.jarvishlive" + ("" if target == NAME else "." + target),
                "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "TARGETED_DEVICE_FAMILY": "1",
                "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
                "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO"}
    dependencies = []
    if target == NAME:
        settings.update({"INFOPLIST_FILE": NAME + "/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
                         "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1"})
    else:
        proxy = add(target + "Proxy", "PBXContainerItemProxy", containerPortal=project_id,
                    proxyType="1", remoteGlobalIDString=app_id, remoteInfo=NAME)
        dependencies.append(add(target + "Dependency", "PBXTargetDependency", target=app_id, targetProxy=proxy))
        if target.endswith("UITests"):
            settings["TEST_TARGET_NAME"] = NAME
        else:
            settings.update({"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/JARVISHLive.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/JARVISHLive", "BUNDLE_LOADER": "$(TEST_HOST)"})
    targets.append(add(target + "Target", "PBXNativeTarget", name=target, productName=target,
                       productReference=product, productType=product_type, buildPhases=phases,
                       buildRules=[], dependencies=dependencies, buildConfigurationList=config_list(target, settings)))

product_group = add("Products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("Main", "PBXGroup", children=groups + [product_group], sourceTree="<group>")
project_config = config_list("Project", {"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "GCC_C_LANGUAGE_STANDARD": "gnu17"})
add("Project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1640"},
    buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="zh-Hant",
    hasScannedForEncodings="0", knownRegions=["zh-Hant", "en", "Base"], mainGroup=main_group,
    productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
project = ROOT / (NAME + ".xcodeproj")
project.mkdir(exist_ok=True)
document = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project_id}
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(document) + "\n", encoding="utf-8")
scheme_dir = project / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme = ET.Element("Scheme", LastUpgradeVersion="1640", version="1.3")


def reference(parent, target):
    return ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=ident(target + "Target"),
                         BuildableName=target + (".app" if target == NAME else ".xctest"), BlueprintName=target,
                         ReferencedContainer="container:" + NAME + ".xcodeproj")


build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build, "BuildActionEntries")
entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
reference(entry, NAME)
tests = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = ET.SubElement(tests, "Testables")
for target in (NAME + "Tests", NAME + "UITests"):
    reference(ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), target)
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), NAME)
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme)
ET.ElementTree(scheme).write(scheme_dir / (NAME + ".xcscheme"), encoding="utf-8", xml_declaration=True)
print(f"Generated {project.name}: {len(targets)} targets, {len(objects)} objects")
