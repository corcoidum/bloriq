# BLORIQ

현재 버전은 **BLORIQ — THE LAST ECHO 시즌 1**입니다. 밤숲 위의 입체적인 달빛 석판 보드와25종 친구·기억·5개 챕터 결말을 구현했습니다. [실제 전후 비교와 화면](docs/moonstone-season1-review.html), [실행·검증 안내](docs/MOONSTONE_SEASON1.md), [25종 바이블](docs/LAST_ECHO_BIBLE.md)을 참고하세요. 기존25개 퍼즐과 기록을 유지하며 신규사용자 튜토리얼·재방문 홈 진입은 그대로입니다. [3초 인트로](docs/INTRO_3S_STORYBOARD.md)는 콘티 제안이며 자동재생 구현은 하지 않았습니다.

[집 PC에서 이어서 작업하기](docs/HOME_HANDOFF.md): 최신 작업 브랜치 받기, 실행 명령, 검증 결과와 남은 작업을 정리했습니다.

민트 표식의 리크를 한 칸씩 밀어 별문으로 보내는 퍼즐입니다. 블록이 비운 칸에 한 턴 동안 잔상이 남아 다음 이동을 막습니다. 현재는 핵심 재미와 학습 흐름을 검증하기 위한 **25개 스테이지 프로토타입**입니다. 로그인과 서버 없이 Android에서 오프라인으로 플레이하는 것이 목표이며 실기기 오프라인 테스트는 아직 필요합니다.

현재 규칙을 기준으로 정리한 후속 제작 지시와 완료 기준은 [개발 마스터 프롬프트 v3](docs/ECHO_BLOCK_MASTER_PROMPT_V3.md)를 참고하세요.

첨부된 상용 게임 개발 방향과 현재 게임 방식의 선택 근거는 [BLORIQ 제품 방향](docs/BLORIQ_PRODUCT_DIRECTION.md)에 정리했습니다.

## 게임 방법

새 사용자는 실제 1레벨에서 이동 → Echo 차단 → 출구 이동을 직접 경험하는 세 단계 튜토리얼로 시작합니다. 처음부터 건너뛸 수 있고 도움말에서 다시 연습할 수 있습니다. 연습은 진행 기록을 바꾸지 않습니다. 재방문자는 여정 홈으로 바로 들어갑니다. 기존 4초 무음 인트로는 설정에서 다시 볼 수 있으며, 모션 줄이기에서는 생략합니다. 홈에서 현재 퍼즐 revision의 완료·별과 첫 미완료 단계를 확인하고, 5개 단위 챕터 그리드에서 원하는 스테이지를 고릅니다.

- 블록을 상하좌우로 드래그하면 한 번에 한 칸 이동합니다. 민트 표식의 리크를 별문까지 보내면 클리어합니다.
- 일반 칸에서 성공적으로 이동하면 출발 칸에 잔상이 생깁니다. 이전 잔상은 다음 이동을 판정할 때까지 장애물로 남고, 그 이동이 끝나면 새 잔상으로 교체됩니다. 아래의 특수 칸에서는 예외가 적용됩니다.
- Echo 지우개 칸에서 떠나면 이전 잔상을 지우고 새 잔상을 남기지 않습니다. Echo 유지 칸에서 떠나면 이전 잔상이 그대로 유지됩니다.
- 화살표 칸에서는 표시된 방향으로만 나갈 수 있습니다. 목표 전용 칸에는 리크만 들어갈 수 있습니다.
- 스위치가 있는 스테이지에서는 스위치 위의 잔상이 문을 엽니다. 잔상이 남아 있는 동안 문으로 들어갈 수 있고, 다음 이동을 마치면 이전 잔상이 사라지며 문이 닫힙니다. 블록이 문 위에 있을 때 문이 닫혀도 블록을 문 밖으로 이동할 수 있습니다.
- 막힌 칸으로 드래그하거나 가만히 기다리는 것은 턴을 소비하지 않습니다.
- Undo는 블록 위치와 잔상을 함께 복원하고 Restart는 현재 스테이지를 처음부터 시작합니다. 이동할 수 있는 수가 없으면 되돌리기 버튼이 안내됩니다.
- 우측 상단의 설정에서 Light / Dark / System 테마와 모션 줄이기, 효과음, BGM을 선택합니다. 새 설치는 Dark이며 기존 테마 선택은 기기에 저장됩니다. 테마를 바꿔도 현재 보드와 Undo 기록은 유지됩니다. 물음표는 게임 방법입니다. BGM은 플레이를 누른 뒤 시작하며 홈과 인트로에서는 재생을 중단합니다. 설정에서 인트로를 다시 봐도 현재 게임은 유지됩니다. 진동을 별도로 끄는 설정은 아직 없습니다.
- 홈 버튼 또는 시스템 뒤로 가기로 나갈 때, 이동한 미완료 판이 있으면 초기화 여부를 확인합니다. 단순 백그라운드 복귀는 보드와 Undo를 유지합니다. 앱 종료 후 미완료 판을 복원하는 기능은 없습니다.

새 25개 스테이지는 초반부터 여러 기믹을 하나씩 익히고 뒤로 갈수록 조합하도록 구성했습니다. 블록을 드래그하면 이동 가능 여부와 다음 잔상, 문 상태 변화가 미리 표시됩니다. 클리어 후 별과 개인 최고 기록을 확인하고, 해결 과정을 리플레이하거나 결과를 정령 포스트카드로 공유할 수 있습니다. 재미와 난이도는 실제 사용자 테스트로 확인해야 합니다.

## 테마와 클리어 연출

- 모든 스테이지에 Blue 룬석, Mint 목표 받침의 리크, Purple Echo, Gold 보상, Slate 장애물, Cyan Switch/Gate를 동일하게 적용합니다. 두 테마의 배치와 색상 역할은 같습니다.
- 일반 클리어 연출은 1.45초이며, 루나벨 첫 발견은 최대 2.2초입니다. 목표 블록 확대 → Purple/Mint 파동과 입자 → 획득 별 순차 표시 → 결과 패널로 이어집니다. 최고 기록은 Gold 강조와 짧은 반짝임으로 구분합니다.
- 축하 연출은 건너뛸 수 있으며, 앱 또는 시스템의 모션 줄이기 설정에서는 결과를 바로 표시합니다. Android의 Remove animations와 iOS의 Reduce Motion 변경도 반영합니다.
- 별 평가와 기록 저장은 완료 즉시 수행합니다. 렌더러가 멈춰도 독립 타이머가 결과 버튼을 표시하며, 스테이지 전환 시 이전 연출을 정리합니다.
- 공통 토큰은 `lib/design/game_theme.dart`, 로컬 설정은 `lib/settings/`, 연출은 `lib/game/`에 있습니다. 퍼즐 규칙과 스테이지 데이터는 변경하지 않았으며 새 production dependency는 없습니다.

[Light/Dark 및 개선 전후 화면 비교](docs/design-comparison.html)와 [디자인 QA 결과](docs/DESIGN_QA.md)를 참고하세요. 문서의 화면은 Flutter widget renderer로 생성한 검증 이미지이며 실기기 성능 측정 자료는 아닙니다.

후속 아케이드 디자인에서는 인트로·홈·게임 HUD·스테이지 그리드·설정과 대화상자를 통일했습니다. [최신 화면 및 인트로 프레임 비교](docs/arcade-design-review.html), [구현·검증 결과와 재현 방법](docs/ARCADE_EXPERIENCE_QA.md)을 참고하세요. 게임 규칙과 25개 스테이지, 기록 저장 형식은 유지했습니다.

그 다음 Hybrid Visual Puzzle 개선에서는 초반 2~5레벨만 기본 Echo 학습용 revision 2로 바꾸고, 기존 기록을 보존하는 v2 migration을 추가했습니다. 날짜별 고정 **Daily Echo**, 최근 7일 참여·연속 참여, 챕터별 진행률, 동의 후 로컬 테스트 기록과 명시적 내보내기를 제공합니다. [P0/P1 당시 화면 모음](docs/hybrid-review.html), [단계별 구현·검증 결과](docs/HYBRID_EXECUTION.md), [5명 관찰표](docs/PLAYTEST_OBSERVATION.md)를 참고하세요. 공개 콘텐츠는 25개이며 26~40 후보는 자동 검증만 끝나 별도 초안으로 보관합니다.

## 실행 방법

Flutter stable SDK가 필요합니다. 이 프로젝트의 개발 기준은 Flutter 3.47.8 / Dart 3.13.7입니다. 설치는 [Flutter 공식 문서](https://docs.flutter.dev/get-started/install)를 참고하세요. Chrome으로 실행할 때는 Android SDK가 필요하지 않습니다.

다른 컴퓨터에서 처음 시작한다면 `git clone https://github.com/corcoidum/bloriq.git`으로 저장소를 내려받고 `cd bloriq`으로 이동합니다. 이미 저장소가 있다면 본인 작업을 확인한 후 `git pull --ff-only`로 최신 변경을 가져옵니다.

프로젝트 폴더에서 PowerShell 또는 터미널을 열고:

```powershell
flutter --version
flutter doctor -v
flutter pub get
flutter gen-l10n
flutter devices
flutter run -d chrome
```

Chrome 창이 열리면 마우스로 블록을 드래그해 플레이합니다. 종료하려면 실행 중인 터미널에서 `q`를 누릅니다. 최초 실행은 의존성과 웹 빌드 도구 다운로드로 시간이 걸릴 수 있습니다.

Android 실행에는 Android SDK, 호환 JDK, USB 디버깅을 켠 기기 또는 에뮬레이터가 필요합니다. [Android 환경 설정](https://docs.flutter.dev/platform-integration/android/setup) 후 `flutter devices`에서 기기 ID를 확인하고 `flutter run -d <기기_ID>`를 실행합니다. `flutter doctor`가 Android 라이선스 동의를 요청하면 `flutter doctor --android-licenses`를 실행합니다.

Android debug APK가 필요하면 `flutter build apk --debug`를 실행합니다. 결과는 `build/app/outputs/flutter-apk/app-debug.apk`에 생성됩니다. 이 파일은 테스트용이며 스토어 배포용이 아닙니다.

Android SDK 설치, 휴대폰 연결, APK 설치 및 확인할 항목은 [Android 휴대폰 테스트 안내](docs/ANDROID_PHONE_TEST.md)를 참고하세요. 2026-10-30 현재 작업 환경에서는 Android SDK를 찾을 수 없어 APK 빌드가 중단되었습니다. Android 환경 설정과 실기기 확인이 필요합니다.

## 검증

```powershell
flutter gen-l10n
flutter analyze
flutter test
python tools/validate_levels.py
python -m tools.level_audit --include-drafts --output docs/LEVEL_REVIEW.md
python -m unittest tools.test_hybrid_tools -v
```

독립 Python 검증기는 각 스테이지의 해결 가능성과 최단 이동 횟수를 BFS로 확인합니다. 특수 칸과 문을 포함한 독립 상태 전이로 해를 계산합니다. Flutter 테스트는 이동 판정, 잔상, Undo/Restart, solver와 연속 스테이지 플레이, 테마 전환·저장, 작은 화면·큰 글꼴, 축하 건너뛰기·입력 차단·실패 복구를 검증합니다. 자동 테스트만으로 터치 감도, 사운드 출력, 실기기 성능이나 첫 사용자 이해도를 보장하지는 않습니다.

## 데이터와 범위

`assets/levels/levels.json`에서 `startPosition`은 목표 블록 시작 위치, `exitPosition`은 출구, `blocks`는 일반 블록, `obstacles`는 고정 장애물입니다. `specialRules`에는 `echoGate`, `echoEraser`, `echoHold`, `oneWay`, `goalOnly`를 조합할 수 있습니다. 좌표 `(0, 0)`은 왼쪽 위입니다. `minimumMoves`는 잔상까지 포함해 검증한 최단 이동 횟수입니다. 새로운 스테이지를 추가하면 위 테스트와 검증기를 다시 실행하세요.

계정, 서버, 광고, 결제 기능은 없습니다. 스테이지별 최고 이동 수, 최고 별, 완료 횟수는 기기 내부에 저장되며 스테이지 메뉴에서 최고 별을 볼 수 있습니다. 새 코스의 기록은 이전 코스와 분리되며, 이전 기록은 기기에 보존되지만 새 코스에는 표시되지 않습니다. 이전 스테이지 데이터는 `assets/levels/legacy_levels.json`에 보관합니다. 앱 데이터 삭제나 앱 제거 시 기록이 사라질 수 있습니다. 포스트카드에는 스테이지 번호와 결과만 들어가며 실제 퍼즐 이동 경로는 포함되지 않습니다. 공유를 선택하면 기기의 시스템 공유 창이 열립니다. 효과음과 BGM은 앱에 포함된 합성 음원으로 오프라인에서 재생되며 기기의 오디오 설정에 영향을 받습니다. Android 아이콘과 서명은 출시용이 아닙니다. 실기기 사용자 테스트, 접근성 검토 및 정식 출시 준비는 후속 작업입니다.

이 저장소는 공개 저장소입니다. 키, 비밀번호, 개인정보 및 실제 환자 정보를 Git 이력에 넣지 마세요.

### Daily와 선택형 테스트 기록

Daily는 기기 로컬 날짜의 검증된 퍼즐을 고정하고 기록을 캠페인과 분리합니다. 시계를 바꿔도 이미 배정한 날짜의 퍼즐은 바꾸지 않습니다. 서버 검증이나 부정행위 방지 기능은 없습니다.

테스트 기록은 기본 꺼짐이며 설정에서 동의한 이후에만 기기에 저장합니다. 자동 업로드는 하지 않고 내보내기 버튼으로 선택한 파일만 공유합니다. 기록을 삭제하면 수집도 중단하며 게임과 Daily 데이터는 유지합니다. 테스트용 최초 동의 화면은 `flutter run -d chrome --dart-define=PLAYTEST_MODE=true`로 켤 수 있습니다.

실제 내보내기 파일은 Git에서 제외한 `playtest-exports/`에 보관합니다. 오프라인 분석 예시는 [실행 결과](docs/HYBRID_EXECUTION.md)를 참고하세요. 로그가 없는 사람을 미복귀자로 처리하지 않으며 현재 D1/D7·Crash-free 실적은 측정하지 않았습니다. Android SDK와 실제 기기·서명 준비 전에는 [소프트 론칭 완료](docs/ANDROID_SOFT_LAUNCH.md)로 간주하지 않습니다.

### 시즌 1의 친구와 기억

캠페인1~25번의 첫 완료에서25종 친구와 기억을 만납니다. 다섯 챕터는 초승달 정원·잠든 수문·잊힌 우체국·바람의 회랑·첫 별의 관측소입니다. 결과 한 화면에서 이야기를 넘기거나 도감에서 다시 읽고 동행을 바꿀 수 있습니다. Daily·연습은 캠페인 수집과 분리합니다.

진행 JSON과 별 평가를 유지합니다. 같은 코스의 저장된 완료 기록으로 새롭게 공개한 친구만 복구하며, 기존 동행·확인 상태를 보존합니다. revision별 별은 분리하고 구형 다른 코스의 번호를 섞지 않습니다. 도감은 시즌 N/25와 챕터 N/5를 표시합니다. 손상·미래 schema를 자동 덮어쓰지 않습니다.

검증과 Android·사람 관찰의 남은 경계는 [시즌 1 실행 기록](docs/MOONSTONE_SEASON1.md)에 있습니다. 광고·서버·계정·결제·미완료 판 재실행 복원은 없습니다.
