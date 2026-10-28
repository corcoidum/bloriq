# BLORIQ Android 휴대폰 테스트 안내

이 문서는 BLORIQ 개발용 Android 테스트 절차입니다. **debug APK는 개인 테스트용이며 Google Play 배포용이 아닙니다.** 2026-10-28 작업 당시 Windows PC에서 Android SDK를 찾지 못해 APK 빌드와 Android 실기기 실행을 검증하지 못했습니다. 각 컴퓨터의 현재 상태는 `flutter doctor -v`로 확인하세요.

## 1. 개발 환경 준비

1. [Flutter 공식 설치 안내](https://docs.flutter.dev/get-started/install)에 따라 Flutter SDK를 설치하고 PATH를 설정합니다. 기존 개발·자동 테스트에 사용한 버전은 Flutter 3.47.8 / Dart 3.13.7입니다. 설치 후 터미널을 다시 열어 `flutter --version`을 확인합니다.
2. [Android Studio](https://developer.android.com/studio/)를 설치하고 초기 설정에서 Android SDK를 설치합니다. Android Studio 설치만으로 Flutter SDK가 설치되는 것은 아닙니다.
3. Android Studio의 **SDK Manager → SDK Tools**에서 Android SDK Command-line Tools, Android SDK Platform-Tools, Android SDK Build-Tools 설치 상태를 확인합니다. SDK Platforms의 Android SDK도 설치합니다.
4. Android Studio에 포함된 JDK를 사용하거나 호환 JDK를 설정합니다. SDK를 찾지 못하면 `flutter config --android-sdk`에 설치 경로를 지정합니다.
5. 표시되는 Android 라이선스를 읽고 개발자가 직접 동의한 다음 Android toolchain 상태를 확인합니다. 설치 및 동의가 필요한 항목은 `flutter doctor -v`의 안내를 따릅니다.

```bash
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter doctor -v
```

설치 순서와 라이선스는 [Flutter Android 설정 안내](https://docs.flutter.dev/platform-integration/android/setup)를 참고하세요.

## 2. 프로젝트 준비

새 컴퓨터에서 처음 받는다면:

```bash
git clone https://github.com/corcoidum/bloriq.git
cd bloriq
git switch codex/echo-experience-retention
flutter pub get
```

이미 복제한 경우에는 해당 프로젝트 폴더로 이동해 로컬 변경을 확인한 뒤 업데이트합니다.

```bash
git status
git fetch origin
git switch codex/echo-experience-retention
git pull --ff-only
flutter pub get
```

Windows 작업 폴더는 `E:\openkiki\codex_root\bloriq`입니다. Mac에서는 저장소를 복제한 자신의 폴더로 이동하세요. 첫 빌드에는 Android 빌드 도구와 Gradle 의존성을 받기 위해 인터넷이 필요할 수 있습니다.

## 3. 휴대폰 연결 후 바로 실행

1. 휴대폰에서 개발자 옵션을 활성화하고 USB 디버깅을 켭니다. Galaxy는 일반적으로 **설정 → 휴대전화 정보 → 소프트웨어 정보 → 빌드번호 7회**를 누른 뒤 **설정 → 개발자 옵션 → USB 디버깅**에서 켭니다. 기종에 따라 위치가 다릅니다. [Android 개발자 옵션 안내](https://developer.android.com/studio/debug/dev-options.html)
2. 데이터 전송이 가능한 USB 케이블로 컴퓨터와 휴대폰을 연결합니다. 휴대폰에 USB 디버깅 허용 창이 나타나면 개발자가 직접 확인하고 허용합니다.
3. 프로젝트 폴더에서 다음 명령을 실행하고 Android 기기가 목록에 표시되는지 확인합니다.

```bash
flutter devices
```

4. 목록에서 확인한 기기 ID를 아래 명령의 `DEVICE_ID` 대신 입력합니다. 또는 `flutter run`을 실행해 표시되는 기기 선택 안내를 따릅니다.

```bash
flutter run -d DEVICE_ID
```

정상 실행 시 개발용 앱이 휴대폰에 설치되어 열립니다. 터미널의 `q`는 실행 중인 Flutter 세션을 종료합니다.

## 4. debug APK를 만들어 설치

Android 빌드 환경이 준비된 컴퓨터의 프로젝트 폴더에서:

```bash
flutter build apk --debug
```

성공하면 다음 파일이 생성됩니다.

```text
build/app/outputs/flutter-apk/app-debug.apk
```

USB 파일 전송 등으로 APK를 자신의 휴대폰에 복사해 열고 Android의 설치 안내를 직접 확인합니다. 같은 패키지 이름의 앱이 다른 서명으로 이미 설치되어 있으면 설치가 거부될 수 있습니다. 기존 앱의 데이터가 중요할 수 있으므로 삭제 전에 확인하세요.

## 5. 실기기 확인 목록

- 1~25단계를 플레이하면서 스테이지 전환과 마지막 화면을 확인합니다.
- 블록 드래그, 잔상으로 막힌 이동, 되돌리기와 다시 시작을 확인합니다.
- 드래그 중 Echo 및 유효·무효 이동 표시를 확인하고, 터치 취소 시 이동이 확정되지 않는지 확인합니다.
- 클리어 후 Replay를 재생·건너뛰고, 다시 도전하여 별과 최고 기록을 확인합니다. 앱을 종료한 뒤 기록이 유지되는지도 확인합니다.
- Echo Postcard를 미리 보고 다른 앱으로 공유하여 PNG와 별·이동 기록이 올바른지 확인합니다.
- Echo 지우개·유지 칸, 화살표 칸, 목표 전용 칸과 스위치·문이 단독 및 조합된 스테이지를 확인합니다.
- 9단계 세로형 보드와 16단계 5×5 보드에서 모든 칸과 버튼이 보이고 조작되는지 확인합니다.
- 효과음·BGM을 각각 끄고 켜고 앱을 재시작해 설정이 유지되는지 확인합니다. 앱을 백그라운드로 보낸 뒤 복귀할 때 음악과 다른 앱의 오디오가 어떻게 동작하는지, 작은 화면과 진동도 확인합니다. 진동 토글은 아직 없습니다. 실제 출력은 기기 설정에 따라 다를 수 있습니다.
- 네트워크를 끈 상태에서도 게임이 작동하는지 직접 확인합니다. 웹 미리보기 결과는 Android 앱의 오프라인 동작을 증명하지 않습니다.
- 재미와 난이도, 막힌 지점, Undo 횟수를 기록합니다. 첫 조작을 이해하는 시간과 잔상 규칙을 이해하는 시간은 따로 관찰합니다.

최고 기록과 완료 횟수는 기기에 저장됩니다. 앱 데이터 삭제나 앱 제거 시 기록이 사라질 수 있습니다. 테스트 결과에는 기기 모델, Android 버전, 빌드 날짜, 재현 순서를 함께 기록하세요.

## 문제가 생기면

- **`flutter` 명령을 찾을 수 없음:** Flutter SDK와 PATH 설정을 확인하고 터미널을 새로 엽니다.
- **Android SDK 또는 라이선스 오류:** SDK Manager의 Command-line Tools 설치 여부를 확인하고 `flutter doctor -v`와 `flutter doctor --android-licenses` 결과를 확인합니다.
- **휴대폰이 목록에 없음:** 데이터 케이블, USB 디버깅, 휴대폰의 허용 창을 확인합니다. Windows에서는 기종에 따라 제조사 USB 드라이버가 필요할 수 있습니다.
- **서명 충돌:** 설치하려는 APK와 기존 앱의 서명이 다를 수 있습니다. 기존 앱이나 데이터를 삭제하기 전에 백업 필요 여부를 확인합니다.

## 선택 사항: 휴대폰 브라우저 미리보기

PC와 휴대폰을 같은 공유기에 연결하고, 프로젝트 폴더에서 웹 빌드를 만듭니다.

```bash
flutter build web --release
```

Windows에서는 `ipconfig`, macOS에서는 시스템 설정의 네트워크 정보 등에서 공유기에 연결된 컴퓨터의 IPv4 주소를 확인합니다. 아래의 `192.168.0.2`는 **예시**이므로 실제 컴퓨터 주소로 바꿉니다.

```bash
python -m http.server 8768 --bind 192.168.0.2 --directory build/web
```

macOS에서 `python` 명령을 찾지 못하면 설치된 Python 3의 `python3` 명령을 사용합니다. 휴대폰 Chrome에서 `http://컴퓨터_IP:8768/`을 엽니다. 서버를 실행한 컴퓨터가 켜져 있어야 하며, 같은 네트워크의 다른 기기도 접근할 수 있습니다. 서버는 터미널에서 `Ctrl+C`로 종료합니다.

브라우저 미리보기는 화면과 터치 확인을 돕지만 **Android APK 설치, 앱 오프라인 동작, Android 전용 소리·진동을 검증하지 않습니다.**
