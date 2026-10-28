# Android 휴대폰 테스트 안내

이 문서는 BLORIQ 개발용 Android 테스트 절차입니다. debug APK는 테스트용이며 Google Play 배포용이 아닙니다. 현재 작업 PC에서는 Android SDK, JDK 및 연결된 Android 기기를 발견하지 못했기 때문에 실제 APK 빌드와 기기 실행은 아직 확인하지 못했습니다.

## 앱 설치 전: 휴대폰 브라우저에서 먼저 테스트

PC와 Android 휴대폰을 같은 공유기에 연결하고 PC에서 웹 빌드와 임시 서버를 실행합니다. PC는 Wi-Fi 대신 같은 공유기의 유선 연결을 사용해도 됩니다.

```powershell
flutter build web --release
ipconfig
python -m http.server 8768 --bind <PC의_IPv4_주소> --directory build/web
```

`<PC의_IPv4_주소>`를 `ipconfig`에 표시되는 공유기 연결의 IPv4 주소로 바꿉니다. 휴대폰 Chrome에서 `http://<PC의_IPv4_주소>:8768/`을 엽니다. PC가 켜져 있고 서버 명령이 실행 중일 때만 사용할 수 있으며, 같은 네트워크의 다른 기기에서도 접속할 수 있습니다. 실행 중인 터미널에서 `Ctrl+C`를 누르면 서버가 종료됩니다. 접속이 안 되면 동일한 공유기 연결과 방화벽 설정을 확인하세요.

이 방법은 터치와 화면 배치를 확인하는 **웹 테스트**입니다. Android 앱 설치, 앱의 오프라인 동작, Android 전용 사운드·진동 및 APK 서명은 검증하지 않습니다.

## 1. 개발 환경 준비

1. [Flutter 설치 안내](https://docs.flutter.dev/get-started/install)를 따라 Flutter SDK를 설치하고 터미널에서 `flutter --version`이 실행되는지 확인합니다. 이 프로젝트의 테스트 기준은 Flutter 3.47.8 / Dart 3.13.7입니다.
2. [Android Studio](https://developer.android.com/studio/)를 설치하고 초기 설정에서 Android SDK, SDK Platform과 Platform Tools를 설치합니다. 설치 및 SDK 사용에 필요한 약관·라이선스는 개발자가 직접 확인하고 동의합니다.
3. Android Studio에 포함된 JDK를 사용하거나 호환 JDK를 설정합니다. `flutter doctor -v`의 Android toolchain 안내에 따라 누락된 항목을 설치합니다. SDK가 자동으로 발견되지 않으면 `flutter config --android-sdk <SDK_경로>`를 사용합니다.
4. 아래 명령에서 표시되는 Android 라이선스를 읽고 개발자가 직접 동의합니다.

```powershell
flutter doctor -v
flutter doctor --android-licenses
```

## 2. 휴대폰을 연결해 직접 실행

1. 휴대폰에서 개발자 옵션과 USB 디버깅을 켭니다. USB 케이블로 PC와 연결합니다.
2. 휴대폰에 USB 디버깅 허용 창이 나타나면 개발자가 직접 확인합니다. 기기가 인식되지 않으면 케이블, USB 모드, 제조사 드라이버를 확인합니다.
3. 프로젝트 폴더에서 다음 명령을 실행합니다.

```powershell
cd E:\openkiki\codex_root\bloriq
flutter pub get
flutter gen-l10n
flutter devices
flutter run -d <기기_ID>
```

`<기기_ID>`를 `flutter devices`에서 확인한 Android 기기 ID로 바꿉니다. Mac에서는 `cd` 뒤에 Mac에 복제한 프로젝트 경로를 사용합니다. 첫 빌드에는 Android 빌드 도구와 Gradle 의존성 다운로드가 필요할 수 있습니다.

## 3. APK를 만들어 설치

Android 빌드 환경을 준비한 PC에서 프로젝트 폴더를 열고 실행합니다.

```powershell
flutter build apk --debug
```

성공하면 `build/app/outputs/flutter-apk/app-debug.apk`가 생성됩니다. USB 파일 전송 등으로 APK를 본인의 휴대폰에 복사해 열고, 표시되는 Android 설치 안내를 직접 확인합니다. 이미 같은 패키지 이름의 앱이 다른 서명으로 설치되어 있다면 설치가 거부될 수 있습니다. 기존 앱의 데이터가 중요할 수 있으므로 삭제하기 전에 확인합니다.

## 4. 테스트할 내용

- 스테이지 1~20을 처음부터 마지막까지 플레이하고 다음 스테이지와 마지막 화면을 확인합니다.
- 블록을 상하좌우로 드래그할 때 원하는 칸으로 한 번만 이동하는지 확인합니다. 잔상에 막힌 이동은 이동 수를 늘리지 않아야 합니다.
- 되돌리기와 다시 시작이 블록, 잔상, 이동 수를 함께 복원하는지 확인합니다.
- 스테이지 9의 세로형 보드에서 마지막 행까지 조작할 수 있고 화면의 버튼이 보이는지 확인합니다.
- 무음/효과음 설정, 진동, 작은 화면, 화면 전환과 앱 복귀를 확인합니다. 시스템 사운드·진동은 기기 설정에 따라 달라질 수 있습니다.
- 각 스테이지가 명확하고 재미있는지, 막힌 곳과 이동 횟수를 기록합니다. 첫 유효한 조작까지 걸리는 시간과 잔상 규칙을 이해하는 시간은 따로 기록합니다.

현재 앱은 진행 상황을 기기에 저장하지 않습니다. 앱을 종료하거나 다시 실행하면 처음부터 시작할 수 있습니다. 테스트 결과는 사용 기기, Android 버전, 빌드 날짜 및 재현 순서와 함께 기록합니다.
