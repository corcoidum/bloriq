# BLORIQ v5.1 제작 지시 적용 보고서

검증일: 2026-10-29 (Asia/Seoul). 앱 버전 **0.2.0+2**. 기준 커밋 `37841b2`, 작업 브랜치 `codex/bloriq-v5-1`.

## 현재 상태와 변경 범위

원격 `origin/main`을 fetch해 시작 시 동기화 상태를 확인했고, 기존 작업 트리는 깨끗했다. 별도 브랜치에서 기존 Flutter + Flame 프로젝트를 확장했다. 공개 배포, push, main 병합, 기존 파일 삭제는 수행하지 않았다. 모든 변경은 검토 가능한 작업 트리에 있다.

기존 25개 퍼즐, Echo 규칙, 기존 별·최고 기록·완료 횟수, Undo/Restart, Preview/Replay, Echo Postcard, Light/Dark/System, 한·영, 오디오 설정을 보존했다. `lib/domain/puzzle.dart`, 두 코스의 레벨 JSON, `pubspec.lock`은 변경하지 않았다. 새 production dependency는 없다.

## Phase별 결과

| Phase | 기존 상태 / 이번 구현 | 실제 변경 파일 | 검증 / 남은 작업 |
|---|---|---|---|
| 0 — 좌표 | 별도 셀 계산과 고정 타일 inset을 단일 `BoardGeometry`로 통합. DPR 반올림, 보드 origin, 타일·블록 크기, 셀 중심, 입력·preview 임계값 연결 | `lib/game/board_geometry.dart`, `lib/game/bloriq_game.dart`, `lib/main.dart`, `test/board_geometry_test.dart`, `test/responsive_board_test.dart` | 5개 화면 × 2테마 × 4단계 검증, DPR 1/2.625/3 좌표 검증과 실제 widget 드래그 통과. 보고된 물리 기기의 문제는 직접 재현하지 못했으므로 원인을 특정 기기나 DPR로 단정하지 않음 |
| 1 — 캐릭터 기반 | 리크 + 25종 고유 정령, 5계열, 일반20/수호5, 한·영 설정. 공통 둥근 체형에 귀·날개·수정·꼬리·왕관 차별화 | `assets/story/season1.json`, `lib/companions/season.dart`, `lib/companions/spirit_art.dart`, `docs/CHARACTER_BIBLE.md`, `docs/STORY_BIBLE.md` | 고유 ID/단계/기억, 필수 한·영 필드, 수호 단계5/10/15/20/25 검증. Canvas 캐릭터 시트 생성 |
| 2 — 첫5 수직 슬라이스 | 실제 이동·Echo에 반응하는 인트로, 건너뛰기·다시 보기, 확정 획득, 도감, 동행, 저장 | `lib/main.dart`, `lib/companions/collection_dialog.dart`, `lib/progress/progress_repository.dart`, `test/collection_flow_test.dart` | 1~5단계 실제 드래그 → 보상 → 도감 → 동행 선택 → 앱 재시작 → 복원 통과 |
| 3 — 전체 수집 | 25종 전체 도감, 미획득 실루엣/스포일러 숨김, 진행률, 상세/동행 선택, 기존 기록 보상 복구 | `lib/companions/collection_dialog.dart`, `lib/progress/progress_repository.dart`, `test/collection_test.dart`, `test/new_course_playthrough_test.dart` | 전체25 연속 실제 드래그와 각 단계 보상 개수, 재클리어 중복 방지, 동시 저장 직렬화, 미래 버전 보존 통과 |
| 4 — 이야기/월드맵 | 다섯 지역의 단계 선택, 25개 제목과 기억 조각, 기록으로 읽는 세계 역사, 25단계 시즌 결말 | `assets/story/season1.json`, `lib/companions/season.dart`, `lib/companions/collection_dialog.dart`, `docs/STORY_BIBLE.md` | 수호자 공동 결정이라는 시즌1 복선 회수. 다음 시즌의 리크 과거 질문 연결. 스토리 열람 없이 계속 플레이 가능 |
| 5 — 아트/UX | 작은 보드 밖 리크·동행, 떠 있기·시선·막힘·Echo·축하 반응. 기존 타임라인에 구체→정령 공개와 수호 광파 추가. 챕터별 배경 색조. 수호 획득 원본 합성 cue | `lib/companions/spirit_art.dart`, `lib/main.dart`, `lib/audio/game_audio.dart`, `assets/audio/guardian.wav`, `tools/generate_audio.py` | 모션 줄이기/시스템 접근성, 큰 글꼴, 기존 승리 타이머 회귀 통과. 정교한 지역 삽화·지역별 BGM은 후속 아트 고도화 범위 |
| 6 — 공유 | 기존 PNG/시스템 공유 경로 재사용. 정령/수호/컬렉션/실제 초기 퍼즐 도전 카드. 새 카드 정사각·세로 규격 선택 | `lib/companions/spirit_postcard.dart`, `lib/companions/collection_dialog.dart`, `lib/main.dart`, `test/spirit_postcard_test.dart` | 네 유형 × 1080×1080/1080×1920 실제 PNG 렌더링 검증. 기존 Replay 유지. 동영상 인코딩/내보내기는 미구현, 실제 기기 공유 시트 확인은 필요 |
| 7 — 출시 검증 | 분석·전체 테스트·독립 BFS·Android debug APK·Web 빌드·브라우저 직접 플레이 | `test/collection_accessibility_test.dart`, 전체 기존 테스트, `tools/validate_levels.py` | 자동 검증 결과는 아래 참조. 연결된 Android 기기가 없어 실기기/비행기 모드/스토어 출시 검증은 미완료 |

## 자동 검증 결과

- `flutter analyze`: **No issues found**.
- `flutter test`: **138개 통과**. 일반 실행의 캐릭터 시트 캡처 전용 테스트는 파일을 쓰지 않고 반환한다. 이미지 생성 실행은 별도로 수행했다.
- `python3 tools/validate_levels.py`: **25/25 valid and solvable**, 기록된 최단 이동 수가 BFS와 일치.
- `flutter build apk --debug`: 성공. `build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter build web`: 성공. `build/web/`.
- `git diff --check`: 통과. 레벨 JSON/domain/lockfile 변경 없음.
- 실제 in-app browser: 한국어 첫 단계에서 두 번 드래그, Echo 생성과 이동2, 별3, 루미 획득 및 도감1/25 등록을 직접 확인했다. 이 브라우저 데모의 진행은 테스트용 로컬 진행이다.
- 브라우저·widget 검증은 Android 실기기 성능 측정이 아니다.

빌드에 기존 `share_plus` Kotlin Gradle 호환성의 향후 변경 경고와 Web의 Cupertino 폰트 탐색 경고가 나온다. 현재 빌드는 성공했다. 의존성 전체를 일괄 업그레이드하지 않았으며, Flutter/Gradle을 다음 버전으로 올릴 때 해당 플러그인 호환성은 다시 확인해야 한다.

## 보드 정렬과 입력 검증

화면: 320×568, 360×800, 393×852, 412×915, 600×960. 대표 단계: 1, 6, 14, 25. 두 테마 총40개 화면을 캡처했다.

`cellSize`는 가용 너비/열과 높이/행 중 작은 값이다. 셀 크기 하나를 물리 픽셀 기준으로 내림한 뒤 전체 너비·높이와 중앙 origin을 계산한다. 이미 계산된 크기를 다시 전달할 때 부동소수점 오차로 한 물리 픽셀을 더 내리지 않도록 허용 오차를 둔다. 블록과 shadow는 셀 안쪽 여백을 유지한다. 기존 승리 파티클은 의도적으로 셀 경계 밖으로 퍼질 수 있다.

- 비정사각형 viewport의 letterbox 터치 제외, 셀 중심의 역변환, 마지막 경계 제외 검증.
- 실제 GameWidget 크기와 Flame geometry 크기 일치 검증.
- 대표 화면에서 실제 drag preview의 선택 셀과 그림 좌표 일치 검증.
- DPR2.625/3에서 Flutter → Flame 재계산 및 실제 한 칸 이동 검증.
- 한국어·큰 글꼴2배·320×568 도감 상세와 동행 선택 검증.
- 작은 화면의 긴 이야기·결과·메뉴는 스크롤로 접근한다. 보드 위에 캐릭터를 겹치지 않는다.

## 수집/기존 기록 호환성 및 실패 복구

완료 기록이 보상의 원장이다. 보상용 목록을 별도 순서로 쓰지 않고, 현재 코스의 완료 레코드와 기존 코스의 유효한 완료 레코드에서 고정 정령/기억 ID 집합을 계산한다. 세트로 계산하므로 중복될 수 없다. 연출을 닫거나 앱을 종료해도 **완료 저장이 성공했다면** 다음 실행에서 같은 보상이 복원된다.

- 현재 저장 키 `bloriq.progress.course2.v1`, 기존 키 `bloriq.progress.v1` 유지.
- 기존 코스의 최고 이동·별은 새 코스 기록과 혼합하지 않고 정령/기억만 복구.
- envelope `version:1` 유지, 수집 메타데이터는 `collectionVersion:1`로 구분.
- 한 JSON 스냅샷에 완료/별/최고 기록, spiritIds, memoryIds, companionId, introSeen 기록. 수집률은 ID 개수에서 계산.
- 저장 요청을 직렬화하여 늦게 끝난 오래된 쓰기로 되돌아가지 않게 함.
- 알려지지 않은 진행/수집 버전은 덮어쓰지 않음. 선택된 정령이 획득 목록에 없으면 안전하게 기본 리크로 복원.
- 손상된 JSON/envelope는 `.corruptBackup` 키에 원본을 보존한 뒤 새 진행 허용. 백업 저장도 실패하면 기존 원본을 덮어쓰지 않음. 백업의 사용자 자동 복원 화면은 아직 없음.
- 실패한 저장은 결과 화면 또는 선택 동작의 알림으로 표시. 저장 성공 전 강제 종료, OS의 저장장치 오류, 앱 삭제까지 내구성을 보장하는 서버 백업은 없음. 로그인/서버는 이번 범위에서 도입하지 않음.

## 화면·디자인 산출물

- [실제 브라우저 한국어 도감](screenshots/v51/browser-collection.jpg)
- [리크 + 25종 캐릭터 시트](screenshots/v51/character-sheet.png)
- [첫 획득](screenshots/v51/reward-stage-1.png)
- [수호 정령 획득](screenshots/v51/reward-stage-5.png)
- [첫5 도감](screenshots/v51/collection-first-five.png)
- [정령 상세](screenshots/v51/spirit-detail.png)
- [320 Light Stage1](screenshots/v51/light-320-stage-1.png)
- [393 Dark Stage14](screenshots/v51/dark-393-stage-14.png)
- [600 Light Stage25](screenshots/v51/light-600-stage-25.png)

위 PNG는 widget renderer 캡처이며 JPG 한 장은 실제 브라우저 캡처다. 실제 기기 Golden 기준 이미지를 확보하지 못했으므로 Golden 통과로 보고하지 않는다.

## 실행과 재검증

일반 Flutter 개발 환경:

```sh
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
python3 tools/validate_levels.py
flutter run -d chrome
flutter build apk --debug
```

이 작업 환경에서 SDK가 PATH에 없는 경우:

```sh
export PATH="/tmp/bloriq-flutter/bin:$PATH"
export PUB_CACHE=/tmp/bloriq-pub-cache
flutter run -d chrome
```

화면 재생성(macOS, 지정 Unicode 폰트 필요):

```sh
flutter test test/responsive_board_test.dart test/collection_flow_test.dart --dart-define=CAPTURE_V51=true
```

## 남은 작업과 다음 우선순위

1. Android 실기기에서 APK 설치 → 비행기 모드 첫 실행 → 첫5 클리어 → 강제 종료/재실행 → 도감/동행 복원 → 작은 화면 드래그 → 실제 공유 시트 검증.
2. 실제 사용자에게 인트로 이해도·난이도·수집 만족감을 확인. 지역별 전문 삽화·음악과 정령별 더 세밀한 동작은 이 결과를 기준으로 고도화.
3. 출시용 아이콘, 서명, 버전 정책, 접근성·성능 계측과 스토어 검토. 현재 APK는 debug 테스트용이며 스토어 출시 완료가 아님.
4. Replay 동영상 내보내기는 Flutter/Android별 인코딩·저장 권한과 비용을 별도로 검토한 뒤 진행.
