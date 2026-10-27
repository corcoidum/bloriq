# BLORIQ (블로릭)

**Move Smart. Find Your Way.**

블록을 움직여, 탈출의 길을 열어라.

BLORIQ는 Flutter와 Flame으로 만드는 오프라인 블록 경로 퍼즐입니다. 이 저장소는 Android 출시를 위한 **Phase 1 프로토타입**으로, 5×5 보드와 첫 10개 스테이지를 중심으로 개발합니다. 앱 이름과 Android package ID는 상표 및 스토어 검토 전까지 후보입니다.

## 게임 방법

1. 블록을 상하좌우로 한 칸씩 드래그해 길을 만듭니다. 다른 블록이나 장애물과 겹치거나 보드 밖으로 이동할 수 없습니다.
2. 시작점에서 출발해 빈 칸을 상하좌우로 연결하고 도착점까지 경로를 그립니다. 같은 칸을 두 번 지나거나 블록을 통과할 수 없습니다.
3. 실수했으면 Undo로 직전 이동을 취소하거나 Restart로 스테이지를 처음부터 다시 시작합니다.

## 개발 환경

- Flutter stable SDK와 Flutter에 포함된 Dart SDK. 개발 시 확인한 stable 버전: Flutter 3.47.8 / Dart 3.13.7.
- Android 실행 및 빌드에는 Android SDK, Android SDK Command-line Tools, Android 기기 또는 에뮬레이터, 호환 JDK가 필요합니다.
- Flutter 및 Android 설치와 라이선스 안내는 [Flutter 공식 설치 문서](https://docs.flutter.dev/get-started/install)와 [Android 설정 문서](https://docs.flutter.dev/platform-integration/android/setup)를 참고하세요.
- Flame은 `pubspec.yaml`의 의존성으로 설치합니다. 패키지 버전은 프로젝트 설정을 기준으로 합니다.

SDK 설치와 Android 기기 연결 후 프로젝트 폴더에서 실행합니다.

```bash
flutter --version
flutter doctor -v
flutter pub get
flutter gen-l10n
flutter devices
flutter run
```

여러 기기가 표시된다면 `flutter run -d <기기_ID>`로 선택합니다. Android 라이선스 관련 문제가 `flutter doctor`에 표시되면 안내에 따라 `flutter doctor --android-licenses`를 실행하고 내용을 확인하세요.

## 정적 검사와 테스트

```bash
flutter gen-l10n
flutter analyze
flutter test
```

자동 테스트 성공만으로 Android 실기기에서의 터치, 성능, 다양한 화면 크기가 검증되는 것은 아닙니다. 실기기 테스트 결과는 별도로 기록해야 합니다.

## 스테이지 데이터

스테이지는 [`assets/levels/levels.json`](assets/levels/levels.json)에 배열로 저장합니다. 각 스테이지는 `id`, 보드 크기, 시작점과 도착점, 블록, 장애물, 특수 규칙, `minimumMoves`, 난이도를 포함합니다. 좌표의 원점 `(0, 0)`은 왼쪽 위입니다. `minimumMoves`는 임의로 추정하지 않고 solver의 최소 이동 결과와 일치하도록 검증합니다.

스테이지를 추가하거나 수정한 후에는 `flutter test`와 `python3 tools/validate_levels.py`를 실행해 데이터 유효성과 해결 가능성을 확인하세요. Phase 1에서 지원하지 않는 특수 규칙은 빈 배열로 두어야 하며, 방향 제한·스위치·게이트는 후속 단계에서 구현합니다.

## 현재 범위와 제한

Phase 1은 핵심 퍼즐의 플레이 가능성과 정확성을 검증하는 단계입니다. 광고, 실제 결제, 계정, 서버, 정식 출시를 위한 개인정보 동의 및 Google Play 제출은 이 단계의 범위가 아닙니다. 사운드, 별 보상, 진행 상황 저장, 힌트, 수동 언어 선택은 후속 단계에서 다룹니다. 현재 한국어 및 영어 문구는 기기 언어에 따라 적용하고, 그 밖의 언어는 영어로 표시합니다. 기기별 사용성, 재미, 난이도는 별도의 실제 사용자 테스트가 필요합니다. Android 앱 아이콘은 Flutter 기본 임시 아이콘이며, 출시 전 BLORIQ 전용 아이콘과 release 서명을 준비해야 합니다. 현 템플릿의 release 빌드는 임시 debug 서명 설정이므로 스토어 제출용이 아닙니다.

## 공개 저장소와 개인정보

이 프로젝트의 GitHub 저장소는 공개되어 있습니다. API 키, 광고 계정 ID, 서명 키, 비밀번호, 개인정보, 실제 환자 데이터는 파일이나 Git 이력에 넣지 마세요. 샘플 데이터는 가상 데이터만 사용합니다. 공개 배포와 스토어 제출은 개발자의 별도 승인 후 진행합니다.
