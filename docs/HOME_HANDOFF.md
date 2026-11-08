# 맥북에서 최신 BLORIQ 이어서 작업하기

2026-10-30. 최신 개발 브랜치는 **`codex/moonstone-season1`**이다. `main`에 병합하지 않고 작업 브랜치로 전달한다. 게임 구현 기준은 `026c70f`이며 그 뒤 이 안내를 갱신했다.

## 완료 상태

- 달빛 석판 보드: 프레임·타일 홈·룬석·장애물·목표 받침의 깊이와 정렬 통일.
- 시즌1: 실제25종 친구·기억·5개 챕터 결말·도감·동행·발견/챕터 공유.
- 기존25개 퍼즐·ID·revision·최단 이동·기믹·별 평가·진행 저장 유지.
- 신규 사용자는 실제1번 튜토리얼, 재방문자는 홈으로 바로 진입.
- Daily·7일 기록·로컬 분석 동의·Preview·Replay·Postcard·테마·오디오 유지.
- 3초 인트로는 콘티 제안만 작성. 설정의 기존4초 다시 보기는 보존.

[전체 실제 화면](moonstone-season1-review.html) · [구현/검증](MOONSTONE_SEASON1.md) · [25종 바이블](LAST_ECHO_BIBLE.md) · [인트로 콘티](INTRO_3S_STORYBOARD.md)

## 가장 안전한 방법: 새 폴더로 받기

맥북의 기존 작업을 덮어쓰지 않도록 새 폴더에 받는다. `bloriq-moonstone`이 이미 있으면 다른 새 이름을 사용한다.

```bash
git clone --branch codex/moonstone-season1 --single-branch https://github.com/corcoidum/bloriq.git bloriq-moonstone
cd bloriq-moonstone
git status --short --branch
flutter --version
flutter pub get
flutter gen-l10n
flutter run -d chrome --web-port 8878
```

개발·검증 기준은 Flutter **3.47.8**, Dart **3.13.7**이다. `pubspec.yaml`은 Dart>=3.13을 요구한다. 다른 컴퓨터의 SDK는 `flutter --version`으로 확인하고, 기존 lockfile을 유지하며 불필요한 `pub upgrade`는 하지 않는다. Chrome이 없으면 `flutter devices`에서 가능한 실행 대상을 확인한다.8878이 사용 중이면 기존 실행을 종료하거나 다른 포트를 쓴다.

## 이미 맥북에 저장소가 있는 경우

```bash
git status --short --branch
git fetch origin --prune
```

미커밋 작업이나 별도 커밋이 있으면 그대로 보존하고 위 새 폴더 방식을 사용한다. 자동 reset·stash·강제 push로 맞추지 않는다.

깨끗한 작업 폴더에서 이 브랜치를 처음 받는다면:

```bash
git switch --track origin/codex/moonstone-season1
```

이미 같은 로컬 브랜치가 있다면:

```bash
git switch codex/moonstone-season1
git pull --ff-only origin codex/moonstone-season1
git rev-list --left-right --count HEAD...origin/codex/moonstone-season1
```

마지막 결과가 `0 0`이면 일치한다. fast-forward가 거부되면 중단하고 새 폴더로 받는다. 앱이 실행 중이었다면 `q`로 종료 후 재실행한다. 새 카탈로그는 세션 시작 시 읽으므로 단순 hot reload만으로 확인하지 않는다.

## 검증 근거와 남은 작업

구현 기준 `026c70f`에서 정적 분석 정상, **Flutter261개·Python5개·BFS25/25·웹 release 빌드**를 통과했다. 이 인수인계 문서만 수정하는 업로드 단계에서 전체 검사를 다시 수행한 것은 아니다.

```bash
flutter analyze
flutter test
python3 tools/validate_levels.py
python3 -m unittest tools.test_hybrid_tools -v
flutter build web --release
```

Android APK는 아직 생성하지 않았다. 회사 PC에서 사용자 동의 후 Java/Android SDK 다운로드 준비를 시작했으나 APK 빌드 완료 상태가 아니다. SDK·JDK·Gradle 캐시·서명 키는 Git에 올리지 않는다. 맥북에서는 자신의 Android 환경을 준비하고 라이선스 동의 후 아래 명령으로 확인한다.

```bash
flutter doctor -v
flutter devices
flutter build apk --debug
# 실제 기기가 준비되면
flutter run --profile -d YOUR_ANDROID_DEVICE_ID
```

기존 release 설정은 debug 서명이며 스토어용 서명으로 간주하지 않는다. 실제 Android 터치·오프라인·음향·종료/복귀·프레임·공유 시트와 사람 관찰은 남아 있다. 이번 전달은 원격 브랜치 업로드이며 main 병합·스토어 배포가 아니다.

## PC 사이에 자동으로 옮겨지지 않는 데이터

진행·수집·테마·오디오·Daily·선택한 테스트 로그는 기기/브라우저 로컬 데이터다. Git clone으로 회사 PC의 플레이 기록이 맥북으로 이동하지 않는다. 새 브라우저 origin/포트에서는 신규 사용자로 시작할 수 있다. 코드·25종 아트·폰트·퍼즐·문서는 저장소에 포함돼 있다. APK·로컬 SDK와 빌드 캐시는 제외한다.
