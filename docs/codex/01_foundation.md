# 01 기반 정비 — 세계 3 전에 한 번

세계 3~7에 기믹 네 개와 판 125개가 더 들어온다. 그 전에 기믹을 넣는 자리, 힌트 계산, 생성기, 이야기 검사, 세계 테마를 한 번 정리한다. 두 작업으로 나눈다.

---

## 01-A 기믹 등록 구조와 힌트 백그라운드 계산

```text
BLORIQ 저장소에서 "기반 정비 01-A"를 진행해 줘. 규칙은 AGENTS.md를 따르고, 브랜치는 origin/main에서 codex/foundation-mechanics로 만든다.

목표: 세계 3~7에서 새 기믹(거울 짝, 시곗바늘 칸, 얼음, 책장 문)을 한 묶음씩 추가할 수 있게 구조를 정리하고, 힌트 계산이 화면을 멈추지 않게 한다. 게임 동작과 저장 형식은 바뀌면 안 된다.

1. 기믹 등록 구조 (Dart)
   - 지금 lib/domain/puzzle.dart는 specialRules를 Level 생성자에서 type별로 파싱하고, MoveValidator·PuzzleController·PuzzleSolver.successors가 기믹별 분기를 직접 가진다. 이걸 "기믹 하나 = 한 파일"로 정리한다.
   - lib/domain/mechanics/ 아래에 공통 인터페이스(예: BoardMechanic)를 두고, 기존 echoEraser, echoHold, oneWay, goalOnly, echoGate를 각각 옮긴다. 인터페이스에 들어갈 것:
     · JSON 파싱과 검증(잘못된 데이터면 FormatException)
     · 칸 진입 가능 여부
     · 이동 뒤 잔상 처리
     · 이동 결과 변환 훅(미끄러짐·순간 이동·짝 이동처럼 착지 칸이나 다른 블록 위치를 바꾸는 기믹용)
     · 상태 키에 더할 값(시각처럼 위치 말고도 상태가 있는 기믹용)
   - 레지스트리 한 곳에 type 이름 → 구현을 등록한다. 모르는 type이 오면 지금처럼 오류를 낸다.
   - 권능(PowerRules)은 이번에 옮기지 않아도 된다. 다만 새 기믹 훅이 권능 이동 뒤에도 불리도록 순서를 문서화한다(권능 착지 → 기믹 변환 → 잔상).
   - 화면 쪽도 같은 키로 찾게 한다: lib/game/board_badge.dart의 배지, lib/game/mechanic_legend.dart의 범례 문구, lib/game/bloriq_game.dart의 칸 그리기가 기믹 type으로 그리기 함수를 찾게 한다. 지금 그림과 픽셀 단위로 같아야 한다.

2. 기믹 등록 구조 (Python)
   - tools/validate_levels.py도 같은 이름의 기믹 함수 묶음(tools/mechanics.py 등)으로 나눈다. Dart와 같은 훅 이름을 쓴다.
   - tools/design_world2.py, tools/design_endless.py, tools/level_audit.py가 그대로 동작해야 한다.

3. 두 solver 일치 테스트 일반화
   - test/power_solver_agreement_test.dart와 tools/power_fuzz_fixture.py를 "기믹 목록을 받아 무작위 판 N개를 만들고 두 solver의 최단 수를 비교"하는 형태로 넓힌다. 이후 세계 작업에서 새 기믹 이름만 추가하면 되게 한다.

4. 힌트를 화면 스레드에서 빼기
   - lib/main.dart의 별빛 길(약 681줄)과 풀이 따라 하기(약 735줄)는 PuzzleSolver를 동기로 부른다. 이걸 바꾼다:
     a) tools/validate_levels.py가 구한 최단 풀이를 레벨 JSON에 "solution" 필드(이동 목록)로 저장하는 옵션(--write-solutions)을 만들고, levels.json·world2.json에 채워 넣는다. 저장된 풀이와 실제 최단 수가 같은지 테스트한다.
     b) 판의 처음 상태에서는 저장된 풀이를 쓴다. 판 도중에는 isolate(compute)에서 시간 제한(예: 1.5초)과 상태 예산을 두고 탐색한다. 시간이 넘으면 "처음부터 다시 하면 별빛 길을 쓸 수 있어요" 같은 안내를 보여 준다(ko/en).
     c) 계산하는 동안 버튼에 진행 표시를 보여 주고, 연타해도 계산이 한 번만 돌게 한다.
   - 별바다 항해의 별빛 한 수(lib/endless/endless_screen.dart)도 같은 경로를 쓴다.

5. 검증
   - 기존 테스트가 모두 통과해야 한다. 테스트를 고쳐서 통과시키지 말고, 동작이 같아야 한다.
   - 새 테스트: 레지스트리에 기존 다섯 기믹이 모두 등록됨, 모르는 type은 오류, 저장된 solution 길이 == minimumMoves, isolate 힌트가 시간 초과 시 안내를 띄움.
   - flutter analyze, flutter test -r failures-only, python3 tools/validate_levels.py 통과.

끝나면 바뀐 구조를 docs/SAGA.md의 "새 세계를 여는 순서" 1번 항목에 반영하고(새 기믹을 넣는 파일 목록), 커밋·푸시한 뒤 결과를 보고해 줘. main 병합은 하지 마.
```

---

## 01-B 공통 생성기, 이야기 검사, 세계 테마, 출시 서명

```text
BLORIQ 저장소에서 "기반 정비 01-B"를 진행해 줘. AGENTS.md를 따르고, 01-A가 들어간 브랜치(또는 main)에서 codex/foundation-worlds 브랜치를 만든다.

1. 공통 판 생성기
   - tools/design_world2.py의 엔진(무작위 판 → 언덕 오르기 → 검증)을 tools/design_world.py로 옮긴다. 세계별 설정은 tools/worlds/w2.py(SLOTS, 판 크기, 쓸 수 있는 기믹, 권능)로 분리한다.
   - 실행: python3 -m tools.design_world --world 2 [--only 7] [--workers 8]. 결과는 assets/levels/world{N}.json, 레벨 id는 (N-1)*100+1부터.
   - tools/design_endless.py의 accept()에 있는 "들어간 기믹을 하나씩 빼 보면 최단 수가 달라져야 한다(장식 기믹 금지)" 검사를 공통 함수로 옮기고, 세계 생성기에도 적용한다. 단, 세계 2 기존 판은 다시 생성하지 않는다. --check 모드로 기존 world2.json이 새 엔진의 검증을 통과하는지만 확인한다.
   - 생성 중 30초마다 저장하고 끊겨도 이어서 만든다. 진행 로그는 build/design_logs/wN.log에 남긴다.
   - 슬롯마다 탐색 예산과 최대 시간을 설정에 둔다. 예산을 넘는 판(상태 폭발)은 버리고 로그에 남긴다.

2. 세계 공통 이야기·레벨 검사
   - test/world2_levels_test.dart와 story 관련 테스트를, 세계 번호를 받아 같은 검사를 하는 test/world_content_test.dart로 일반화한다. saga.json에서 playable인 세계 모두에 대해 돈다:
     · 레벨 25개, id 범위, 각 장 다섯째 판의 수호 정령 연결
     · 정령 25명(id sN-01~25), 모든 문구에 ko·en이 비어 있지 않음
     · 장 5개, globalChapter (N-1)*5+1부터, 별자리 stars 5개(0..1 좌표)
     · prologue, intro, endingTitle, ending 존재
     · 레벨 JSON의 solution 길이 == minimumMoves
   - assets/story/TEMPLATE_world.json(빈 틀 + 각 필드 설명 주석 대신 README)을 docs/STORY_TEMPLATE.md로 만든다. world2.json을 예시로 쓴다.

3. 세계 테마
   - saga.json의 세계 항목에 선택 필드 "theme"를 받는다: { "palette": {배경, 판, 테두리, 강조 색}, "floor": 그림 경로|null, "rock": 그림 경로|null, "bgm": 오디오 경로|null }.
   - 값이 없으면 지금 달빛 숲 스킨을 그대로 쓴다. 그림이 없으면 색만 바꿔 그린다.
   - 세계 2에는 구름바다 느낌의 palette만 넣는다(밝은 하늘빛 판석, 흰 테두리 계열). 홈·지도 색은 바꾸지 않는다.
   - BGM은 세계에 들어가면 그 세계 곡, 없으면 기본 곡. tools/generate_audio.py로 세계 2용 짧은 루프를 하나 합성해 assets/audio/bgm_w2.wav로 넣는다(30초 이하, 용량 1MB 이하).

4. 출시 서명 준비 (키는 커밋하지 않음)
   - android/app/build.gradle(.kts)이 android/key.properties가 있으면 그 키로 릴리스 서명하고, 없으면 지금처럼 디버그 키로 서명하게 한다.
   - .gitignore에 key.properties, *.jks, *.keystore가 있는지 확인한다.
   - 키 만드는 법(keytool 명령)과 보관 주의사항을 docs/ANDROID_SOFT_LAUNCH.md에 적는다. 키 자체는 만들지 않는다. 사람이 직접 만든다.

5. 검증: flutter analyze, flutter test -r failures-only, python3 tools/validate_levels.py, python3 -m tools.design_world --world 2 --check. 세계 2 화면 캡처(360×740) 한 장을 docs/screenshots/foundation/에 남기고 색이 바뀐 것을 확인한다.

끝나면 docs/SAGA.md "새 세계를 여는 순서"를 새 생성기·테마·검사 기준으로 고쳐 쓰고, 커밋·푸시·보고해 줘. main 병합은 하지 마.
```
