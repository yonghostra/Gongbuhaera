"""flutter create 로 만든 iOS/Android 폴더에 앱 설정을 넣는다. (여러 번 실행해도 안전)"""
import pathlib
import plistlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_NAME = "공부해라"


def patch_android():
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    s = manifest.read_text(encoding="utf-8")
    perms = [
        "android.permission.INTERNET",
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO",
    ]
    add = "".join(
        f'    <uses-permission android:name="{p}" />\n'
        for p in perms
        if p not in s
    )
    if add:
        s = s.replace("    <application", add + "    <application", 1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', s, count=1)
    manifest.write_text(s, encoding="utf-8")
    print("✔ Android 권한/이름 설정")


def patch_ios():
    plist_path = ROOT / "ios/Runner/Info.plist"
    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    plist["CFBundleDisplayName"] = APP_NAME
    plist["CFBundleName"] = APP_NAME
    plist["NSCameraUsageDescription"] = (
        "공부하는 동안 졸음·자리 비움을 확인하기 위해 카메라를 사용합니다. "
        "영상은 기기 안에서만 분석되며 저장하거나 전송하지 않습니다."
    )
    plist["NSMicrophoneUsageDescription"] = (
        "가상 부모를 만들기 위해 부모님의 목소리를 녹음합니다."
    )
    plist["NSPhotoLibraryUsageDescription"] = (
        "가상 부모로 쓸 부모님 사진을 고르기 위해 사진 보관함에 접근합니다."
    )
    plist["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f)

    # Google ML Kit 은 iOS 15.5 이상
    podfile = ROOT / "ios/Podfile"
    shutil.copy(ROOT / "ios_templates/Podfile", podfile)
    pbx = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    s = pbx.read_text(encoding="utf-8")
    s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", s)
    pbx.write_text(s, encoding="utf-8")
    print("✔ iOS 권한 문구/이름/최소 버전(15.5) 설정")


if __name__ == "__main__":
    patch_android()
    patch_ios()
