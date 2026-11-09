# Codex 제작 프롬프트 모음

[빛길 로드맵](../ROADMAP_LIGHTROAD.md)을 Codex 작업 단위로 나눈 프롬프트다. 위에서부터 차례로 하나씩 실행한다.

## 쓰는 법
1. Codex에서 **새 세션**을 연다. 이전 작업 대화를 이어 쓰지 않는다.
2. 아래 표의 프롬프트 블록(```text … ```)을 그대로 붙여 넣는다.
3. Codex가 끝나면 보고를 확인한다. 화면이 바뀌는 단계(C)는 APK를 폰에서 해 본다.
4. 문제가 없으면 다음 줄로 넘어간다.

모든 프롬프트는 저장소 루트의 `AGENTS.md`(공통 규칙: 브랜치, 두 solver, 검증 명령, 토큰 절약)를 Codex가 자동으로 읽는다고 가정한다.

## 순서
| 순서 | 파일 | 작업 | 끝나면 생기는 것 |
|---|---|---|---|
| 1 | [01_foundation.md](01_foundation.md) | 01-A 기믹 등록 구조·힌트 백그라운드 | 새 기믹을 한 묶음으로 추가할 수 있는 구조, 화면이 멈추지 않는 힌트 |
| 2 | 〃 | 01-B 공통 생성기·이야기 검사·세계 테마 | `tools/design_world.py`, 세계별 보드 색과 BGM 연결 |
| 3 | [03_world3_mirror_lake.md](03_world3_mirror_lake.md) | 3-A 규칙 · 3-B 판 · 3-C 이야기·출시 | 세계 3 공개 |
| 4 | [04_world4_clocktower.md](04_world4_clocktower.md) | 4-A · 4-B · 4-C | 세계 4 공개 |
| 5 | [05_world5_ice_cave.md](05_world5_ice_cave.md) | 5-A · 5-B · 5-C | 세계 5 공개 |
| 6 | [06_world6_dream_library.md](06_world6_dream_library.md) | 6-A · 6-B · 6-C | 세계 6 공개 |
| 7 | [07_world7_first_star.md](07_world7_first_star.md) | 7-A · 7-B · 7-C · 7-D | 세계 7과 엔딩 |
| 언제든 | [09_longevity.md](09_longevity.md) | 도전 과제·잔상의 시련·항해 v2 | 반복 플레이 콘텐츠. 세계 3 출시 뒤 아무 때나 |
| 따로 | [08_art.md](08_art.md) | 수호 정령 원화·보드 스킨 이미지 | 이미지 생성 도구가 있는 곳에서 |

## 세계 작업 A·B·C의 공통 모양
- **A 규칙:**
  - 새 기믹을 Dart와 Python 두 solver에 넣는다.
  - 보드에 그리고, 범례 배지와 문구, 드래그 미리보기, 되돌리기를 연결한다.
  - 단위 테스트와 두 solver 일치 테스트를 쓴다.
  - 화면은 테스트용 임시 판으로만 확인하고, 사가에는 아직 공개하지 않는다.
- **B 판:**
  - `tools/worlds/wN.py`에 SLOTS 25개를 쓴다.
  - `python3 -m tools.design_world --world N`으로 생성한다.
  - 검증기·감사 도구를 통과시킨다.
  - 각 판의 의도(`learningIntent`)와 최단 수 곡선을 표로 보고한다.
- **C 이야기·출시:**
  - `assets/story/worldN.json`을 쓴다(프롤로그, 5장, 정령 25명, ko/en).
  - `saga.json`에서 그 세계를 `playable`로 바꾸고, 세계 테마를 넣는다.
  - 새 규칙 안내 카드를 연결한다.
  - 캡처를 남기고, README와 SAGA를 갱신하고, 버전을 올리고, 릴리스 APK를 빌드한다.
