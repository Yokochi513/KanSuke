"""CI 上で配布プロファイルと Firebase の iOS 設定を適用する。"""

import datetime
import os
from pathlib import Path
import plistlib
import shutil
import uuid


def read_plist(path):
    with path.open("rb") as source:
        return plistlib.load(source)


def write_plist(path, value):
    with path.open("wb") as destination:
        plistlib.dump(value, destination)


def main():
    temporary = Path(os.environ["RUNNER_TEMP"])
    profile = read_plist(temporary / "profile.plist")
    entitlements = profile["Entitlements"]
    team = profile["TeamIdentifier"][0]
    profile_uuid = str(uuid.UUID(profile["UUID"])).upper()
    bundle_id = "com.kansuke.kansuke"
    application_id = entitlements["application-identifier"]
    if application_id.split(".", 1)[1] != bundle_id:
        raise ValueError("Provisioning profile must target com.kansuke.kansuke")
    if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices") or entitlements.get("get-task-allow"):
        raise ValueError("An App Store distribution profile is required")
    if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("Provisioning profile has expired")
    if entitlements.get("aps-environment") != "production" or "Default" not in entitlements.get("com.apple.developer.applesignin", []):
        raise ValueError("Profile requires Push Notifications and Sign in with Apple")

    firebase = read_plist(Path("ios/Runner/GoogleService-Info.plist"))
    if firebase["BUNDLE_ID"] != bundle_id:
        raise ValueError("Firebase configuration must target com.kansuke.kansuke")
    info_path = Path("ios/Runner/Info.plist")
    info = read_plist(info_path)
    info["GIDClientID"] = firebase["CLIENT_ID"]
    url_types = info.setdefault("CFBundleURLTypes", [])
    if not any(firebase["REVERSED_CLIENT_ID"] in item.get("CFBundleURLSchemes", []) for item in url_types):
        url_types.append({"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [firebase["REVERSED_CLIENT_ID"]]})
    background_modes = info.setdefault("UIBackgroundModes", [])
    if "remote-notification" not in background_modes:
        background_modes.append("remote-notification")
    write_plist(info_path, info)
    entitlement_path = Path("ios/Runner/Runner.entitlements")
    runner_entitlements = read_plist(entitlement_path)
    # FR-5: TestFlight の通知を APNs production 環境で受け取る。
    runner_entitlements["aps-environment"] = "production"
    write_plist(entitlement_path, runner_entitlements)

    destination = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(temporary / "profile.mobileprovision", destination / f"{profile_uuid}.mobileprovision")
    write_plist(temporary / "ExportOptions.plist", {
        "method": "app-store-connect",
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "teamID": team,
        "provisioningProfiles": {bundle_id: profile_uuid},
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    })
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as environment:
        environment.write(f"IOS_TEAM_ID={team}\nIOS_PROFILE_UUID={profile_uuid}\n")


if __name__ == "__main__":
    main()
