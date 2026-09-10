#!/usr/bin/env python3
"""Contract checks for the Android-only fork identity."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_ID = "com.zym20192019.anxreader"
EXPECTED_CHANNEL = f"{EXPECTED_ID}/install_info"
EXPECTED_LABEL = "Anx Reader AI"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    gradle = read("android/app/build.gradle")
    require(
        f'namespace "{EXPECTED_ID}"' in gradle,
        "Android namespace must use the fork application id",
    )
    require(
        f'applicationId "{EXPECTED_ID}"' in gradle,
        "Android applicationId must use the fork application id",
    )

    activity_path = ROOT / "android/app/src/main/kotlin/zym20192019/anxreader/MainActivity.kt"
    require(activity_path.is_file(), "Fork MainActivity must live under the fork package path")
    activity = activity_path.read_text(encoding="utf-8")
    require(
        f"package {EXPECTED_ID}" in activity,
        "MainActivity package must match the fork application id",
    )
    require(
        EXPECTED_CHANNEL in activity,
        "Native install-info channel must use the fork namespace",
    )

    require(
        '            android:name="com.zym20192019.anxreader.MainActivity"' in read("android/app/src/main/AndroidManifest.xml"),
        "Android manifest must point to the fork MainActivity",
    )

    dart = read("lib/service/iap/play_store_iap_service.dart")
    require(
        EXPECTED_CHANNEL in dart,
        "Dart install-info channel must match MainActivity",
    )

    for relative in (
        "android/app/src/main/res/values/strings.xml",
        "android/app/src/main/res/values-zh/strings.xml",
    ):
        require(
            f">{EXPECTED_LABEL}<" in read(relative),
            f"{relative} must identify the fork app as {EXPECTED_LABEL}",
        )

    appfile = read("android/fastlane/Appfile")
    require(
        f'package_name("{EXPECTED_ID}")' in appfile,
        "Fastlane package name must use the fork application id",
    )

    print(f"Android fork identity contract passed: {EXPECTED_ID}")


if __name__ == "__main__":
    main()
