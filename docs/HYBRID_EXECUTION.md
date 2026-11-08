# BLORIQ Hybrid Visual Puzzle 실행 결과

기준일: 2026-10-29. 작업 브랜치: `codex/hybrid-echo-p0-p1`. 원격 푸시·main 병합·광고 SDK 도입은 하지 않았다.

## P0

### A. 현재 상태 진단

- 원격 main 기준은 `37841b2`. 미커밋이던 인트로·홈·디자인 작업은 `8ab9d0a`로 먼저 보존했다.
- 기존 Preview·Replay·별 평가·Postcard·설정·오디오를 재사용했다. 원래 2~5레벨은 특수 기믹을 연달아 도입해 기본 Echo를 반복 학습하기 어려웠다.

### B. 구현 계획과 완료 기준

- 첫 사용자에게 실제 1레벨을 바로 제공하고 세 번의 조작으로 Echo 생성·차단·교체를 가르친다.
- 1레벨을 유지하고 2~5의 배치만 변경한다. 기존 기록은 삭제하지 않고 revision으로 분리한다.
- 튜토리얼 완료/건너뛰기/중단/연습, Preview·Undo·Restart, 작은 화면을 검증한다.

### C. 실제 구현 결과

- 최초 실행은 인트로·홈을 거치지 않고 실제 1레벨로 진입한다. 오른쪽 이동 → Echo로 돌아가려다 차단 → 오른쪽 출구 순서다. 잘못된 입력은 턴을 소비하지 않는다.
- 안내는 실제 `PuzzleController`·`MoveValidator`·Preview를 사용한다. 튜토리얼 문구는 즉시 갱신하며 추가 애니메이션에 의존하지 않는다.
- 건너뛰기는 현재 보드·Undo를 유지한다. 중간 종료 후에는 초기 상태에서 다시 안내한다. 도움말의 연습은 별도 컨트롤러로 진행하며 캠페인에 저장하지 않는다.
- 최초 정상 완료만 캠페인에 저장한다. 기록이 있는 사용자에게 튜토리얼을 강제하지 않는다. 이후 실행의 4초 인트로와 설정의 다시 보기는 유지했다.
- 1~5의 최소 이동은 `2 → 4 → 4 → 5 → 6`. 2는 legacy 2, 3·4는 기존 배치에서 특수 칸 제거, 5는 legacy 5를 재사용했다. 6~25의 배치는 그대로다.
- `Level.revision` 기본값은 1, 변경된 2~5는 2다. 진행 기록은 새 `bloriq.progress.v2`에 `(levelId, revision)`으로 저장한다. 기존 course2 기록은 revision 1로 복사하고 원본 키·더 오래된 코스 키는 보존한다.
- 바뀐 퍼즐의 옛 별은 현재 진행률에 합산하지 않는다. 미래 schema는 덮어쓰지 않는다. migration 저장 실패 시 메모리 상태를 유지하고 원본으로 재시도할 수 있다.
- 드래그 임계값은 셀의 24%로 유지하고 Preview와 입력 확정이 같은 상수를 사용한다. 가로 화면에서도 가능하면 셀을 최소 48 logical pixels로 유지한다.

주요 영역: `lib/tutorial/`, `lib/domain/puzzle.dart`, `lib/progress/`, `lib/app/`, `lib/main.dart`, `assets/levels/levels.json`.

### D. 테스트 결과

- P0 체크포인트 `bdf0a6a`: 정적 분석 정상, 전체 Flutter 테스트 **119개 통과**. 새 튜토리얼·revision migration을 기존 회귀 테스트와 함께 검증했다.
- 최종 통합 테스트에는 실패하는 migration writer, 프로세스 재시작, 연습 기록 격리, 최신 Daily·분석 연동도 추가했다. 최종 결과는 아래 명령과 로컬 `build/hybrid-final-tests.log`에 기록한다.
- 최종 통합 결과: `dart format .` 변경 없음, `flutter analyze --no-pub` 문제 없음, **Flutter 테스트 151개 통과**, **Python 도구 테스트 5개 통과**, 공개 25개와 후보 15개 감사 통과.
- 5명 무설명 플레이, 3~5초 이해도, 실제 플레이 시간은 아직 측정하지 않았다. [관찰 체크리스트](PLAYTEST_OBSERVATION.md)를 준비했다.

### E. 준비도

P0 소프트웨어 구현은 완료했다. 첫 화면 이해 시간과 초반 재미는 사용자 관찰 확인이 남아 있다. 튜토리얼·1레벨 5~15초, 2~5레벨 15~60초, 이후 30~90초는 제품 가설이며 검증 성과가 아니다.

## P1

### A. 현재 상태 진단

기존 엔진과 로컬 저장을 확장하는 것으로 Daily와 성장 표현을 구현할 수 있었다. 서버·로그인·외부 분석 SDK는 필요하지 않았다.

### B. 구현 계획과 완료 기준

- 날짜별 고정 Daily, 7일 참여와 연속 참여, 5레벨 챕터 진행률을 추가한다.
- 동의 후 로컬 이벤트를 기록하고 사용자 선택으로만 내보낸다.
- 새 15개 후보는 검증하되 수동 플레이 확인 전 공개하지 않는다.

### C. 실제 구현 결과

- Daily 풀 v1은 변경 전 6~25의 고정 사본이다. 로컬 연·월·일을 UTC civil date로 정규화하고 1970-01-01 이후 일수 `% 20`으로 선택한다.
- 날짜별 최초 배치에 풀 버전과 퍼즐 전체 스냅샷을 저장한다. 앱 업데이트나 풀 교체가 같은 날짜의 배치를 바꾸지 않는다. 자정을 넘긴 판은 시작한 날짜에 기록하고 홈 복귀·앱 복귀 때 오늘의 퍼즐을 갱신한다.
- Daily는 캠페인과 분리된 `bloriq.daily.v1`에 참여·완료 횟수·최고 이동을 저장한다. 최단 이동이면 Perfect다. 유효 이동 한 번이 참여이며, 완료는 별도 표시한다. 시계 변경으로 과거·미래 기록을 삭제하지 않는다.
- 홈의 최근 7일과 오늘/어제부터 계산한 연속 참여는 읽기 전용 표시다. 놓친 날을 비난하는 문구나 시간제한을 넣지 않았다.
- 스테이지 선택은 5개 단위 챕터로 묶고 현재 revision의 완료 수·별을 표시한다. 모든 공개 스테이지는 계속 직접 선택할 수 있다.
- 분석은 기본 꺼짐이다. 일반 빌드는 설정에서, `PLAYTEST_MODE=true` 빌드는 시작 전 선택 화면에서 동의한다. 동의 전 ID·이벤트 생성과 소급 기록은 없다.
- 로컬 이벤트는 `lib/analytics/`가 담당한다. 플레이 컨텍스트·레벨·revision·시도 ID·최종 이동·실제 성공 입력·Undo·Restart·활성 시간을 기록하며 이름·연락처·광고 ID·이동 경로는 기록하지 않는다.
- 시도는 입장/Restart부터 완료·이탈·다음 Restart까지다. 풀이 시간은 Stopwatch로 측정하고 백그라운드·도움말·설정·연습 모달 시간을 제외한다. 강제 종료의 누락된 끝 이벤트는 추정해 만들지 않는다.
- 이벤트는 최대 30일·1만 건이며 5초/20건 단위와 시도 종료 때 배치 저장한다. 빠른 입력의 저장 요청은 합쳐 쓰기 대기열이 무한히 커지지 않게 했다.
- 설정에서 중단·삭제·JSON 내보내기를 제공한다. 삭제는 기록도 중단하며 게임/Daily 데이터는 유지한다. 공유는 내보내기 버튼을 눌렀을 때만 기존 `share_plus`로 수행한다.
- 중단 구간·잘린 로그·내보낸 날짜를 메타데이터로 보존한다. `tools/analyze_playtests.py`는 ID/이벤트 중복을 제거하고 미성숙 코호트·미회수 기록·수집 중단을 구분한다. 추적이 불완전한 사람을 자동 미복귀자로 세지 않는다.
- 콘텐츠 감사는 회전·반사·일반 블록 ID를 정규화해 동일 퍼즐을 차단한다. 유사 배치·최단 이동 급증·새 기믹 동시 도입·탐색량 급증은 경고로 남긴다.
- 26~40 후보 15개는 별도 JSON에 고정했다. 양쪽 solver, 드래그 해법, Undo/Restart 테스트를 통과했지만 `awaiting_manual_play` 상태다. **생산 에셋에는 등록하지 않았고 공개 콘텐츠는 25개다.**

### D. 테스트 결과와 경계

- Daily 결정성·재실행·풀 변경·자정·윤일·7일 경계·시계 역행·미래 schema·캠페인 격리를 검사했다.
- 동의/거절·설정에서 동의·동의 전 소급 금지·중단·삭제·보존 기간·1만 건 상한·모달/백그라운드 시간·미래 schema를 검사했다.
- 공개 25개와 후보 15개는 Python/Dart solver로 검증했고 후보는 Flutter 제스처로 풀었다. 제스처 자동화는 인간의 수동 플레이나 재미 검증을 대체하지 않는다.
- 한국어/영어·Light/Dark·작은 화면·200% 글꼴 회귀 테스트와 가로 화면 최소 셀 크기를 확인했다. `docs/screenshots/hybrid/`의 28개 PNG는 위젯 렌더러로 만든 자료다.
- 실제 브라우저 조작은 이전 로컬 주소 접근 승인 거절 이후 재시도하지 않았다. Android 실기기 성능·오디오·사용자 재방문 데이터는 없다.
- `flutter build web --release --no-pub --dart-define=BUILD_TAG=hybrid-local-2026-10-29`는 성공했다. 결과는 `build/web`이며 기존 로컬 서버 `http://127.0.0.1:8877/`에서 새로고침해 확인할 수 있다. 빌드 성공은 브라우저 조작 검증을 의미하지 않는다.
- APK debug 빌드를 실제 시도했으나 `No Android SDK found`로 실패했다. Flutter 엔진용 Android 산출물이 있어도 Android SDK가 설치된 것은 아니다.
- AAB는 서명·SDK·실기기가 준비되지 않아 시도하지 않았다. release의 기존 debug 서명 설정도 출시용으로 간주하지 않는다.

### E. 준비도와 다음 1~2주

| 항목 | 상태 |
|---|---|
| P0 튜토리얼·초반 콘텐츠·기록 호환 | 구현·자동 검증 완료, 5명 관찰 대기 |
| P1 Daily·진행 UI·동의 기반 분석 | 구현·자동 검증 완료 |
| P1 26~40 콘텐츠 | 후보 자동 검증 완료, 수동 검토 전 비공개 |
| P2 힌트·광고·release 서명 | 미구현·별도 승인 필요 |
| 소프트 론칭 | Android·사람·정책 검증 전이므로 현재 불가 |

1주차에는 Android SDK/기기 환경을 준비하고 [5명 관찰](PLAYTEST_OBSERVATION.md), 5·8레벨과 감사 도구의 경고 구간을 먼저 확인한다. 2주차에는 검토된 후보만 공개 목록에 편입하고, 20~50명 비공개 테스트의 명시적 내보내기로 초기 이탈·조작 문제를 분석한다. D1/D7은 충분한 추적 기간과 회수율을 함께 보고한다.

## 재현 명령

Flutter/Dart가 PATH에 있어야 한다. 이 PC에서 확인한 SDK는 Flutter 3.47.8 / Dart 3.13.7이며 PATH에는 등록되지 않아 도구 실행에는 SDK의 `bin/*.bat` 절대 경로를 사용했다.

```powershell
flutter pub get
flutter gen-l10n
dart format .
flutter analyze
flutter test
python tools/validate_levels.py
python -m tools.level_audit --include-drafts --output docs/LEVEL_REVIEW.md
python -m unittest tools.test_hybrid_tools -v
flutter build web --release --dart-define=BUILD_TAG=hybrid-local-2026-10-29
flutter run -d chrome
```

선택형 분석 동의를 시작 전에 받는 테스트 빌드:

```powershell
flutter run -d chrome --dart-define=PLAYTEST_MODE=true --dart-define=BUILD_TAG=hybrid-local
flutter test test/hybrid_visual_capture_test.dart --dart-define=CAPTURE_HYBRID=true --dart-define=DESIGN_FONT=C:/Windows/Fonts/malgun.ttf
```

사용자가 선택해 내보낸 파일만 분석한다. 실제 테스트 파일은 `.playtest-data/` 또는 `playtest-exports/`에 두고 Git에 커밋하지 않는다.

```powershell
python -m tools.analyze_playtests playtest-exports/participant-a.json playtest-exports/participant-b.json --as-of 2026-11-15 --output .playtest-data/summary.json
```

[화면 모음](hybrid-review.html) · [레벨별 검토·해법·수동 체크](LEVEL_REVIEW.md) · [출시 체크리스트](ANDROID_SOFT_LAUNCH.md)
