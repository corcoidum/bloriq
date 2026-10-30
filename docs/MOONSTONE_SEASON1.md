# BLORIQ — 달빛 석판 보드와 시즌 1 완성

2026-10-30 · 기준 `affe391` → 로컬 작업 브랜치 `codex/moonstone-season1`.

[전후 비교·화면 모음](moonstone-season1-review.html) · [25종 바이블](LAST_ECHO_BIBLE.md) · [아트·프롬프트](../assets/art/season1/README.md) · [3초 인트로 제안](INTRO_3S_STORYBOARD.md) · [디자인 QA](MOONSTONE_SEASON1_QA.md)

## A. 현재 상태와 개선 대상

사용자가 제공한5개 화면은 별문2·3·4·5·9와 대응한다. 불투명 사각 바탕이 둥근 틀과 맞지 않고, 늘인 프레임 PNG와 타일·룬석·장애물이 서로 다른 소재로 보이는 문제를 확인했다. 입력 좌표는 이전 공통 geometry 작업에서 정리되어 있었으므로, 이번에는 그림의 경계와 입체감을 개선했다.

기존 첫5종 수집·기억·동행과25종 설정, 퍼즐·Preview·Replay·Postcard·Daily·기록·오디오를 재사용했다. 퍼즐 배치·ID·revision·최단 이동·기믹·별 평가와 기존 진행/수집 저장 키는 변경하지 않았다. Android 출시·브라우저 동작·사람의 이해도는 자동 검사와 별개다.

## B. 구현 구조

| 영역 | 구현 |
|---|---|
| 달빛 석판 | `BoardGeometry`의 프레임·판·모서리·3~6px 두께를 공유. Flutter `MoonstoneFramePainter`와 Flame `BoardMaterial`이 같은 소재 토큰 사용 |
| 깊이와 맞물림 |24px 외부 여백 안의 받침·접지 그림자, 같은 둥근 clipping, 파인 홈, Blue 룬석·Slate 장애물·Mint 받침의 공통 광원 |
| 기믹 표시 | Echo·Gate·Switch·Eraser·Hold·One-way·Goal-only 의미 유지. 기믹 기호는 폰트 누락에 의존하지 않는 작은 Canvas 도형으로 표시 |
| 시즌 자료 | `StoryChapter`에 계열 이름·결말 제목/본문을 KO/EN으로 추가. `StoryCatalog`에서 챕터별 친구와 결말 조회 |
| 아트·반응 |20종 신규 ImageGen PNG+기존5종. 투명 원본 보존, 표시 배율/앵커만 정규화. sway/tilt/wave/float/bow의 짧은 위젯 반응 |
| 도감·공유 | 시즌 N/25, 챕터 N/5, 접을 수 있는5개 챕터, 상세·동행,25종 발견 카드와 챕터별5종 카드 |

주요 변경은 `lib/design/board_material.dart`, `lib/game/`, `lib/story/`, `lib/app/`, `lib/main.dart`, KO/EN ARB, `assets/story/season1.json`과 신규 아트다. 퍼즐 엔진 밖에서 이야기·보상을 관리한다. 새 production dependency·서버·광고·결제·release 서명 변경은 없다.

## C. 실제 동작과 호환성

```text
신규 실행 → 실제1번 튜토리얼 → 별문 완료
→ 저장된 완료 기록과 공개 배정 대조 → 친구·기억 집합 추가
→ 결과 한 화면에서 기억/즉시 넘기기/다음/Replay/Postcard
→ 다섯 챕터의 친구와 결말 →25번 아스테르와 옛 리크 기록의 단서

재방문 → 홈의 시즌 수집·다음 챕터·이어가기 / 지도 / 도감 / Daily
```

- 첫5종을 유지하고 나머지20종을 실제 아트 검토 후 공개했다. 같은 친구를 다시 클리어해도 발견을 반복 지급하지 않는다.
- 일반 발견은 최대1.5초 이내(기존1.45초), 수호 정령은 최대2.2초다. 즉시 넘기기·다음 진행을 제공하고 모션 줄이기에서는 정적이다. 배경은 정적이며 새 블러·지속 입자를 넣지 않았다.
- 다섯 챕터의 작은 결말이 각각 해당 수호 정령과 도감에 연결된다. 마지막은 아스테르가 고장 난 기억 보존 장치에서 친구를 지키려고 등대를 멈췄다는 고백과 리크 별 표식의 단서다. 리크의 기억 상실/첫 Echo의 창조자는 미해결이다.
- 홈은 첫 미완료 별문과 해당 챕터를 추천한다. 전체 완료 뒤에는 첫 별문으로 다시 간다. 모든 스테이지는 계속 자유 선택 가능하다.
- 도감은 기존 유효 동행의 챕터를 처음 펼친다. 미획득 이름·기억은 숨기고, 소유 친구는 상세·동행·공유를 사용할 수 있다.
- 공유는 소유한 같은 챕터의 친구만 받도록 검증한다. 긴 제목/기억도 겹치지 않게 PNG 텍스트 영역을 맞춘다. 사용자가 공유 버튼을 눌러야 기존 시스템 공유 기능을 호출한다.
- Daily는 오늘의 작은 산책이며 정식 친구·기억을 지급하지 않는다. 연습도 진행·수집과 분리한다.

### 기존 기록 복구

완료된 같은 코스의 스테이지 ID가 수집 권리다. 기존5종 사용자에게 신규20종 중 이미 완료한 친구만 추가하고, 선택 동행·확인/미확인 상태·알 수 없는 선택 필드를 보존한다. 기존 완료자는 복구 요약 한 번을 보며 강제 연속 보상 연출은 없다.

현재 revision의 별/완료율과 과거 revision의 수집 권리는 기존 정책대로 분리한다. 구형 다른 코스의 번호는 합치지 않는다. 저장 실패 시 완료 횟수를 늘리지 않는 재시도를 제공하고, 진행 저장 이후 수집 저장 전에 종료돼도 다시 대조해 복구한다. 손상 원문 백업·미래 schema 보호를 유지한다. 두 저장 키를 원자적 트랜잭션으로 가정하거나 물리적 내구성을 보장하지 않는다.

## D. 실제 검증

Windows·Flutter3.47.8·Dart3.13.7. 실행 로그는 Git에서 제외한 `build/moonstone-*.log`에 있다.

| 검사 | 결과 |
|---|---|
| `flutter pub get`, `flutter gen-l10n` | 실행, 새 production dependency/lockfile 변경 없음 |
| `dart format lib test`, `flutter analyze --no-pub` | 포맷/정적 분석 정상 |
| `flutter test --no-pub --reporter expanded` | **261개 통과** |
|25개 원본 퍼즐의 실제 solver 해법 드래그 |25종 지급·5개 올바른 결말·아스테르 동행 복원·재클리어 중복 없음 통과 |
| `python tools/validate_levels.py` |25/25 해결 가능, JSON 최단 이동과 BFS 일치 |
| `python -m unittest tools.test_hybrid_tools -v` |5개 통과 |
| 별도 `CAPTURE_SEASON1=true` 캡처 |201장 실제 위젯/Canvas 출력, 대표84장+첨부 원본5장 보존 |
|25종 RGBA/투명 여백·48px 표시 | 원본 검사와 소형 렌더 범위 검사 통과 |
| `flutter build web --release --no-pub --dart-define=BUILD_TAG=moonstone-season1-2026-10-30` | **성공**, `build/web` |
| `flutter doctor -v`, `flutter build apk --debug` | Android SDK 없음 확인, APK 빌드 중단 |
| Android profile·실기기·서명 AAB·사람 관찰 | 미실행 |

추가 확인 범위:

-3×3·4×4·직사각형, DPR1/2/3 셀 중심↔터치·경계·프레임 투명 모서리.6개 화면 크기에서1/6/14/25번 실제 드래그·resize 후 Preview 취소·Undo 유지.
- 기존5종에서25종 복구, 과거 revision·구코스 격리, 부분 저장 실패·재시도·원문/미래 schema 보호.
- 한국어/영어·Light/Dark·320px·글자200%에서 첫/마지막 챕터 도감과 동행 조작. 기존 홈·지도·설정·도움말·모션 줄이기 회귀.
- 실제 글꼴 캡처에서 기믹 기호의 누락을 찾아 도형 렌더링으로 수정. 원본 프레임 틈·사각 바탕과 마지막 챕터 공유 카드도 검토.

기본 웹 release 빌드는 성공했다. SDK의 CupertinoIcons 폰트 경고는 남았으며 실제 조작 아이콘은 MaterialIcons를 사용한다. `--wasm` 앱 실행을 검증한 것은 아니다.

화면 자료는 테스트용 합성 진행 상태다. 브라우저 캡처나 실제 공유 시트·음향·16.7ms 프레임 측정 결과로 표현하지 않는다. 브라우저 접근 거절 뒤 우회 재시도하지 않았다. Android 출시·Crash-free·D1/D7 성과는 검증하지 않았다.

## E. 실행·검토와 남은 작업

기존 `flutter run`을 열어 두었다면 **완전히 종료 후 다시 실행**하는 것이 안전하다. 새 시즌 카탈로그는 세션 시작 시 읽으므로 기존 인스턴스의 단순 hot reload만으로 확인하지 않는다.

```powershell
cd E:\openkiki\codex_root\bloriq
flutter pub get
flutter gen-l10n
flutter run -d chrome --web-port 8878
```

현재 PC에서 Flutter가 PATH에 없으면 확인된 `C:\Users\user\.codex\visualizations\2026\10\28\01a17fdf-a558-7601-b474-70371016fa0d\flutter-sdk\bin\flutter.bat` 절대 경로로 실행한다. Android는 SDK/JDK·기기 준비 뒤 `flutter devices`, `flutter run --profile -d YOUR_DEVICE_ID`로 확인한다.

캡처 재현:

```powershell
flutter test test/moonstone_season1_capture_test.dart --dart-define=CAPTURE_SEASON1=true
python tools/publish_moonstone_captures.py
```

원본201장은 `build/moonstone-captures/`에 남고, 문서에는 중복을 줄인 대표 화면만 복사한다. 퍼즐/첫5종 원본 아트·인트로 진입/타임라인은 기준 커밋과 비교해 보존을 확인한다.3초 인트로는 [콘티 제안](INTRO_3S_STORYBOARD.md)만 작성했다.

이번 범위의 보드·시즌1 코드는 완료했으나 모바일 출시 준비 완료를 뜻하지 않는다. 다음 확인은 실제 Android의 터치·오프라인·BGM/무음·종료/복귀·저장 복구와 [사람 관찰표](LAST_ECHO_PLAYTEST.md)의 Echo 이해/다음 별문 동기다. 원격 푸시·main 병합·공개 배포는 하지 않는다.
