# 집에서 이어서 작업하기

2026-10-29. 최신 작업 브랜치는 **`codex/star-courier-design`**이다. `main`에 병합하지 않고 현재 개발 상태를 보관한다.

## 현재 완료 상태

| 단계 | 상태 |
|---|---|
| 인트로·홈 | 공통 세션, 4초 인트로, 홈 진입 구현 |
| P0 | 실제 1레벨 튜토리얼, 2~5레벨 개선, revision별 진행 기록 보존 |
| P1 | Daily Echo, 최근 7일·연속 참여, 챕터 진행률, 선택 동의 기반 로컬 분석·내보내기 |
| 최신 디자인 | 선택한 2번 ‘밤하늘 별배달부’를 홈·인트로·게임판·결과·Daily·설정·공유에 적용 |
| 공개 콘텐츠 | 25개. 26~40은 자동 검증한 초안이며 수동 검토 전 비공개 |
| 출시 | Android 실기기·사람 관찰 미검증. 광고·release 서명 작업은 미진행 |

디자인 구현 기준 커밋은 `cc765b1`이다. 그 이후 이 문서를 추가했다. 이전 인트로·P0·P1 작업도 같은 브랜치 이력에 포함되어 있다.

## 가장 안전하게 받는 방법: 별도 폴더

기존 집 PC 작업 폴더를 덮어쓰지 않으려면 아래처럼 새 폴더에 받는다. `bloriq-home`이라는 폴더가 이미 있다면 다른 새 이름을 사용한다.

```powershell
git clone --branch codex/star-courier-design --single-branch https://github.com/corcoidum/bloriq.git bloriq-home
cd bloriq-home
git status --short --branch
flutter --version
flutter pub get
flutter gen-l10n
flutter run -d chrome --web-port 8877
```

개발 기준은 Flutter **3.47.8**, Dart **3.13.7**이다. Flutter SDK의 `bin`이 PATH에 있어야 한다. Dart는 Flutter에 포함된 버전을 사용한다. `pubspec.lock`을 그대로 사용하며 불필요한 `pub upgrade`는 하지 않는다. 해당 포트를 이미 쓰고 있으면 기존 개발 서버를 확인하거나 다른 포트를 지정한다.

새 설치는 Dark의 밤하늘 화면으로 시작한다. 기존에 저장한 테마 선택이 있으면 유지하므로, 필요한 경우 설정에서 Dark를 선택한다. 새 사용자는 인트로·홈 대신 실제 1레벨의 튜토리얼로 시작한다. 완료/건너뛰기 후의 다음 실행은 인트로→홈이다.

## 집에 이미 저장소가 있는 경우

먼저 `git status --short`로 변경 사항을 확인한다. 미커밋 작업을 자동으로 지우거나 덮어쓰지 않는다. 변경이 있거나 브랜치 상황이 불확실하면 위의 새 폴더 방식을 사용한다.

작업 폴더가 깨끗하고 이 브랜치를 처음 받는 경우:

```powershell
git fetch origin --prune
git switch --track origin/codex/star-courier-design
```

이미 해당 로컬 브랜치가 존재하는 경우:

```powershell
git fetch origin --prune
git switch codex/star-courier-design
git pull --ff-only origin codex/star-courier-design
git rev-list --left-right --count HEAD...origin/codex/star-courier-design
```

마지막 결과는 `0 0`이면 양쪽 커밋이 같다. fast-forward가 거부되면 별도 로컬 커밋이 있는지 확인하고 강제 reset/push로 맞추지 않는다.

## 수행한 검증과 재현

코드 기준 `cc765b1`에서 정적 분석 정상, **Flutter 테스트 153개**, **Python 도구 테스트 5개**, **25/25 레벨 BFS**, 웹 release 빌드를 통과했다. 새 그림·폰트·퍼즐·Daily 데이터는 저장소에 포함되어 있다. 캡처 60장과 선택 시안 비교 자료는 [화면 모음](star-courier-review.html)에 있다.

```powershell
flutter analyze
flutter test
python tools/validate_levels.py
python -m unittest tools.test_hybrid_tools -q
flutter build web --release
```

Python은 레벨·플레이 테스트 분석 도구용이다. 웹 게임을 실행하는 데 Python 서버나 외부 서비스는 필요하지 않다. 브라우저 직접 조작과 Android 실기기 검증을 자동 테스트 통과로 대신하지 않았다.

## Git으로 옮겨지지 않는 것

- 브라우저/앱의 로컬 진행·별·Daily 기록·설정·분석 로그는 기기 저장소에 있다. Git clone은 현재 PC의 플레이 기록을 옮기지 않는다. 미완료 보드 재실행 복원도 지원하지 않는다.
- SDK, Android SDK/JDK, 빌드 폴더, 로컬 서버 프로세스는 복제되지 않는다. 집 PC에서 의존성을 받고 다시 실행한다.
- 수집에 동의한 플레이 테스트 JSON은 명시적으로 내보내는 별도 자료다. 실제 테스트 로그·서명 키·비밀정보를 저장소에 추가하지 않는다.

## 다음 작업 순서와 완료 기준

1. 실제 Android 기기에서 게임 시작→3동작 튜토리얼→5레벨, Undo·Restart·오디오·백그라운드 복귀를 확인한다. SDK/기기 준비 후 `flutter devices`에 나온 ID로 `flutter run -d "YOUR_DEVICE_ID"`를 실행한다.
2. [5명 무설명 관찰표](PLAYTEST_OBSERVATION.md)로 Echo 이해와 작은 캐릭터 식별을 확인한다. 규칙·조작 문제를 추가 콘텐츠보다 먼저 수정한다.
3. [26~40 검토표](LEVEL_REVIEW.md)의 수동 플레이를 마친 후보만 공개한다. 광고·힌트·release 서명은 별도 승인 범위다.

[최신 구현 상세](STAR_COURIER_DESIGN.md) · [P0/P1 구현 상세](HYBRID_EXECUTION.md) · [Android 출시 체크리스트](ANDROID_SOFT_LAUNCH.md)
