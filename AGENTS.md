# BLORIQ 작업 규칙 (Codex·Claude 공통)

BLORIQ는 Flutter + Flame으로 만든 오프라인 잔상 퍼즐이다. 큰 줄거리와 세계 틀은 `docs/SAGA.md`, 앞으로의 제작 순서는 `docs/ROADMAP_LIGHTROAD.md`, 단계별 작업 지시는 `docs/codex/`에 있다.

## 언어
- 보고, 문서, 커밋 설명은 한국어로 쓴다. 코드 식별자와 커밋 제목은 영어로 쓴다.
- 게임 문구는 ko/en을 함께 넣는다(`lib/l10n/*.arb`, 이야기 JSON의 `{"ko","en"}`).

## 브랜치와 커밋
- 작업마다 최신 `main`에서 새 브랜치를 만든다: `git fetch origin && git switch -c codex/<작업이름> origin/main`.
- `main`에 직접 커밋하지 않는다. `main`에는 `git merge --ff-only`로만 넣는다. 앞으로 당길 수 없으면 멈추고 사람에게 묻는다.
- 오래된 로컬 `main`을 푸시하지 않는다. 푸시하기 전에 `git log origin/main..HEAD`로 올라갈 커밋을 확인한다.
- `.claude/`, `build/`, `playtest-exports/`, 서명 키(`*.jks`, `key.properties`)는 커밋하지 않는다.
- 강제 푸시와 `reset --hard`로 남의 커밋을 지우지 않는다.

## 규칙을 바꿀 때 지킬 것
- 퍼즐 규칙은 두 곳에 같은 뜻으로 있다: Dart `lib/domain/puzzle.dart`(앱)와 Python `tools/validate_levels.py`(검증). 한쪽만 바꾸지 않는다.
- 새 기믹을 넣으면 두 solver의 일치 테스트(`test/power_solver_agreement_test.dart` 방식)를 같이 넣는다.
- 저장 형식(`ProgressRepository`, `ProgressionRepository`, `EndlessRepository`의 키와 필드)은 바꾸지 않는다. 바꿔야 하면 옛 데이터를 읽는 이전(migration) 코드와 테스트를 함께 넣는다.
- 레벨 id, 정령 id, 전역 장 번호는 `docs/SAGA.md`의 번호 규칙을 따른다. 한 번 공개한 id는 바꾸지 않는다.
- 판은 손으로 고치지 말고 생성기로 만든다. 생성한 뒤에는 반드시 검증기로 다시 확인한다.

## 검증 명령
```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # Mac 기준
flutter gen-l10n
flutter analyze
flutter test -r failures-only
python3 tools/validate_levels.py
python3 -m tools.level_audit --world <N>
```
- 완료라고 말하기 전에 위 명령이 모두 통과해야 한다. 실패를 숨기지 말고 출력 그대로 보고한다.
- 화면을 바꿨으면 캡처 테스트로 360×740 화면을 남기고 직접 열어 본다(`docs/screenshots/`).

## 토큰 절약
- 큰 파일(`lib/main.dart`, `lib/game/bloriq_game.dart`, `lib/app/journey_panel.dart`, `lib/endless/endless_screen.dart`)은 `grep -n`으로 위치를 찾고 필요한 부분만 읽는다.
- 테스트는 `-r failures-only`로 돌리고, 긴 로그는 `| tail -40`으로 줄인다.
- 판 생성기처럼 오래 걸리는 작업은 백그라운드로 돌리고 로그를 파일에 남긴다. 끝난 뒤 요약 줄만 읽는다.
- 이미지(캡처)는 확인이 꼭 필요한 것만 연다.
- 한 작업이 끝나면 다음 작업은 새 세션에서 `docs/codex/`의 해당 프롬프트로 시작한다.

## 끝낼 때 보고할 것
- 바뀐 것, 검증 결과(명령과 통과 수), 확인하지 못한 것(예: 실기기)
- 커밋 해시와 브랜치 이름. `main` 병합 여부
