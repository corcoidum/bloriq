# 집에서 BLORIQ 이어서 작업하기

개발 기준은 GitHub의 [`main`](https://github.com/corcoidum/bloriq/tree/main)이다. BLORIQ `0.5.0+7`에는 세계 6 꿈의 서고까지 150판이 들어 있다. 세계 6 병합과 포스트카드 수정이 들어간 기준 커밋은 [`2ee40c0`](https://github.com/corcoidum/bloriq/commit/2ee40c0c173883b36c70fb9224757d3a5f23e552)이다.

## 저장소 받기

### 새 폴더에서 시작

macOS 터미널 또는 Windows PowerShell에서 저장소를 둘 상위 폴더로 이동한다. `bloriq-home`이 이미 있으면 비어 있는 새 이름을 사용한다.

```bash
git clone --branch main https://github.com/corcoidum/bloriq.git bloriq-home
cd bloriq-home
git status --short --branch
git rev-list --left-right --count HEAD...origin/main
```

마지막 결과 `0 0`은 로컬과 원격 `main`에 각자만 가진 커밋이 없다는 뜻이다.

### 기존 복사본 갱신

```bash
git remote get-url origin
git status --short --branch
git fetch origin --prune
```

`origin`이 `corcoidum/bloriq`인지 확인한다. 작업 중인 파일이 있으면 기존 폴더를 보존하고 위의 새 폴더 방식을 쓴다. 이전 인수인계대로 `--single-branch`로 받은 경우에는 아래 명령으로 다른 원격 브랜치도 가져올 수 있게 한다.

```bash
git remote set-branches origin '*'
git fetch origin --prune
```

작업 폴더가 깨끗하면 `main`을 연다. 로컬 `main`이 처음이라면 첫 줄에 `git switch --track origin/main`을 사용한다.

```bash
git switch main
git merge --ff-only origin/main
git rev-list --left-right --count HEAD...origin/main
```

fast-forward가 거부되거나 결과가 `0 0`이 아니면 기존 브랜치를 보존하고 새 폴더에서 이어서 작업한다.

## 실행 환경과 웹 미리보기

검증에 사용한 버전은 Flutter **3.47.8**, Dart **3.13.7**, Python **3.13.7**이다. Dart는 Flutter SDK에 포함된다. Flutter SDK의 `bin`을 PATH에 추가한 뒤 터미널을 새로 연다. 웹 미리보기는 Chrome으로 실행한다. [Flutter SDK 아카이브](https://docs.flutter.dev/install/archive) · [Flutter 3.47.8 태그](https://github.com/flutter/flutter/tree/3.47.8) · [웹 실행 환경 설정](https://docs.flutter.dev/platform-integration/web/setup)

프로젝트 폴더에서 아래 명령을 실행한다. 저장소의 `pubspec.lock`을 기준으로 의존성을 받는다.

```bash
flutter --version
flutter doctor -v
flutter pub get
flutter gen-l10n
flutter devices
flutter run -d chrome --web-port 8878
```

`flutter devices`에서 `chrome`을 확인한다. 포트 8878이 사용 중이면 실행 중인 세션을 `q`로 종료하거나 다른 포트를 지정한다. 레벨이나 이야기 데이터를 바꿨을 때는 세션을 재시작해 새 카탈로그를 불러온다.

Android가 필요하면 해당 컴퓨터에 Android SDK와 JDK를 설정한 뒤 프로젝트에서 `flutter build apk --release`를 실행한다. 결과는 `build/app/outputs/flutter-apk/app-release.apk`에 생성된다. 테스트 APK로 기존 앱을 업데이트하려면 앱 ID와 서명을 먼저 확인한다. [Android 환경 설정](https://docs.flutter.dev/platform-integration/android/setup) · [BLORIQ 휴대폰 테스트 안내](ANDROID_PHONE_TEST.md)

## 작업 재개와 검증

1. Codex에서 받은 `bloriq-home` 폴더를 연다. [저장소 작업 규칙](../AGENTS.md)
2. 새 작업은 최신 `origin/main`에서 `codex/` 브랜치를 만든다. 세계 7을 이어갈 때는 **7-A 혼합 판 생성 준비**부터 진행한다. [세계 7 작업 프롬프트](codex/07_world7_first_star.md#7-a-혼합-판-생성-준비)
3. 작업 브랜치에서 검증하고 커밋한 뒤 `git push -u origin HEAD`로 올린다. 다른 컴퓨터에서 `git fetch origin` 후 해당 브랜치를 연다. 처음 받을 때는 `git switch --track origin/브랜치명`을 사용하고, 이미 로컬에 있으면 브랜치를 연 뒤 `git merge --ff-only origin/브랜치명`으로 갱신한다.

세계 7-A를 새로 시작할 때 쓰는 명령이다.

```bash
git fetch origin
git switch -c codex/w7-mix-prep origin/main
```

Windows PowerShell에서 Python 실행 파일 이름이 `python`이면 아래 `python3`를 `python`으로 바꾼다.

```bash
flutter analyze
flutter test -r failures-only
python3 -m unittest discover -s tools
python3 tools/validate_levels.py
python3 -m tools.level_audit --world 6
```

세계 6 병합 기준으로 Flutter 테스트 2,107개, Python 테스트 37개, 캠페인 150판과 보관 25판 검증, 세계 1~6 감사, Android 테스트 APK 빌드를 통과했다. [꿈의 서고 레벨 검토](LEVEL_REVIEW_W6.md) · [세계 6 화면 캡처](screenshots/world6/)

### 저장 복구 작업 이어받기

저장 오류 복구와 아이템 구매 수정 `9a1c720`은 당시 기준 커밋 `711bb20`에서 시작한 별도 브랜치에 있다. 이 브랜치에서 관련 Flutter 테스트 52개를 통과했다. [저장 복구 브랜치](https://github.com/corcoidum/bloriq/tree/codex/fix-save-recovery)

```bash
git fetch origin
git switch --track origin/codex/fix-save-recovery
```

같은 로컬 브랜치가 이미 있으면 `git switch codex/fix-save-recovery` 후 `git merge --ff-only origin/codex/fix-save-recovery`를 사용한다.

## 컴퓨터별로 관리하는 데이터

Git에는 소스·레벨·이야기·에셋·문서가 들어 있다. 플레이 기록과 설정은 사용한 기기 또는 브라우저 프로필과 주소에 저장된다. SDK, Gradle 캐시, 빌드 APK, Android 서명 키와 로컬 설정은 각 컴퓨터에서 별도로 관리한다.
