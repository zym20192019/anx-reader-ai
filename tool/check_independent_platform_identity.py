#!/usr/bin/env python3
"""Fail-fast identity and release-path checks for Anx Reader AI."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ANDROID_ID = "com.zym20192019.anxreader"
APP_LABEL = "Anx Reader AI"
IOS_EXTENSION_ID = f"{ANDROID_ID}.shareExtension"
APP_GROUP = f"group.{ANDROID_ID}"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    android = read("android/app/build.gradle")
    manifest = read("android/app/src/main/AndroidManifest.xml")
    activity = read("android/app/src/main/kotlin/zym20192019/anxreader/MainActivity.kt")
    dart_channel = read("lib/service/iap/play_store_iap_service.dart")
    strings = read("android/app/src/main/res/values/strings.xml")
    fastlane = read("android/fastlane/Appfile")

    require(f'namespace "{ANDROID_ID}"' in android, "Android namespace mismatch")
    require(f'applicationId "{ANDROID_ID}"' in android, "Android applicationId mismatch")
    require(f'android:name="{ANDROID_ID}.MainActivity"' in manifest, "Manifest activity mismatch")
    require(f"package {ANDROID_ID}" in activity, "Kotlin package mismatch")
    require(f'"{ANDROID_ID}/install_info"' in activity, "Kotlin MethodChannel mismatch")
    require(f"MethodChannel('{ANDROID_ID}/install_info')" in dart_channel, "Dart MethodChannel mismatch")
    require(APP_LABEL in strings, "Android label mismatch")
    require(ANDROID_ID in fastlane, "Android Fastlane package mismatch")

    ios_project = read("ios/Runner.xcodeproj/project.pbxproj")
    require(f"PRODUCT_BUNDLE_IDENTIFIER = {ANDROID_ID};" in ios_project, "iOS bundle ID mismatch")
    require(f"PRODUCT_BUNDLE_IDENTIFIER = {IOS_EXTENSION_ID};" in ios_project, "iOS extension bundle ID mismatch")
    require(APP_GROUP in read("ios/Runner/Runner.entitlements"), "iOS app group mismatch")
    require(APP_GROUP in read("ios/ShareExtension/shareExtension.entitlements"), "iOS extension app group mismatch")
    require("com.anxcye" not in ios_project, "Upstream iOS bundle identifier remains")
    require("AnxContainer" not in ios_project, "Upstream iOS app group remains")
    require("28W956D5K8" not in ios_project, "Upstream Apple team remains")
    require("match AppStore" not in ios_project, "iOS Match profile remains")
    require("Anx Reader AI" in read("ios/Runner/Info.plist"), "iOS display name mismatch")

    macos_config = read("macos/Runner/Configs/AppInfo.xcconfig")
    macos_project = read("macos/Runner.xcodeproj/project.pbxproj")
    require(f"PRODUCT_BUNDLE_IDENTIFIER = {ANDROID_ID}" in macos_config, "macOS bundle ID mismatch")
    require("PRODUCT_NAME = Anx Reader AI" in macos_config, "macOS product name mismatch")
    require("com.anxcye" not in macos_project, "Upstream macOS bundle identifier remains")
    require("28W956D5K8" not in macos_project, "Upstream macOS team remains")
    require("match AppStore" not in macos_project, "macOS Match profile remains")

    linux = read("linux/CMakeLists.txt")
    require(f'set(APPLICATION_ID "{ANDROID_ID}")' in linux, "Linux application ID mismatch")
    require('set(BINARY_NAME "anx_reader_ai")' in linux, "Linux binary name mismatch")
    require(APP_LABEL in read("linux/my_application.cc"), "Linux window title mismatch")

    windows = read("windows/CMakeLists.txt")
    runner_rc = read("windows/runner/Runner.rc")
    require('project(anx_reader_ai LANGUAGES CXX)' in windows, "Windows CMake project mismatch")
    require('set(BINARY_NAME "anx_reader_ai")' in windows, "Windows binary name mismatch")
    require(APP_LABEL in read("windows/runner/main.cpp"), "Windows title mismatch")
    require(APP_LABEL in runner_rc, "Windows resource metadata mismatch")
    require("com.anxcye" not in runner_rc, "Upstream Windows publisher remains")

    web = read("web/manifest.json")
    require(f'"name": "{APP_LABEL}"' in web, "Web app name mismatch")
    require(f'"short_name": "{APP_LABEL}"' in web, "Web short name mismatch")
    require(f"<title>{APP_LABEL}</title>" in read("web/index.html"), "Web title mismatch")

    workflow = read(".github/workflows/release-independent.yaml")
    require("anx-ai-v*" in workflow, "Independent release tag namespace missing")
    require("SIGNPATH" not in workflow and "MATCH_" not in workflow, "Upstream signing secret in independent workflow")
    require("TELEGRAM_TOKEN" not in workflow and "NOTIFICATION_URL" not in workflow, "Upstream notification secret in independent workflow")

    print("Independent platform identity contract passed")


if __name__ == "__main__":
    main()
