# 새 세계 이야기 JSON

장과 정령이 하나씩 들어 있는 빈 틀을 `assets/story/worldN.json`으로 복사한다. 장을 5개, 정령을 25개로 늘리고 빈 값과 번호를 채운다. 세계 2의 첫 장은 `globalChapter`가 6이고, 첫 수호 정령 `s2-05`는 레벨 105에 연결된다. [빈 틀](../assets/story/TEMPLATE_world.json) · [세계 2 완성본](../assets/story/world2.json)

| 범위 | 필드 | 값 |
| --- | --- | --- |
| 세계 | `version`, `worldId` | 스키마 버전 `1`, 세계 id `wN` |
| 세계 | `title`, `prologue` | 사가와 같은 세계 이름, 지도 상단 도입문 |
| 세계 | `chapters`, `spirits` | 번호 순으로 장 5개와 정령 25개 |
| 장 | `number`, `globalChapter` | 세계 안 번호 `1..5`, 전체 사가 번호 `(N-1)*5 + number` |
| 장 | `power`, `family` | 소개할 권능 id 또는 `null`, 해당 장 정령의 공통 계열 id |
| 장 | `name`, `familyName`, `constellation` | 장 이름, 계열 이름, 별자리 이름 |
| 장 | `stars.nodes`, `stars.edges` | 레벨 순서대로 0..1 사이의 `[x, y]` 5개, 노드 인덱스 쌍 `[a, b]` 목록. 인덱스 4는 수호 정령이다. |
| 장 | `intro`, `endingTitle`, `ending` | 장의 도입문, 장을 마쳤을 때 보이는 제목과 본문 |
| 정령 | `id`, `levelId`, `chapter` | `sN-01`부터 `sN-25`, 레벨 `(N-1)*100 + 1`부터 25개, 세계 안 장 번호 |
| 정령 | `family`, `guardian` | 연결된 장의 계열 id, 각 장 다섯째 판만 `true` |
| 정령 | `asset`, `motionKind` | 번들에 포함할 그림 경로 또는 `null`, 움직임 이름(기본 `sway`) |
| 정령 | `name`, `levelTitle`, `appearance`, `personality`, `memory`, `quote` | 이름, 레벨 제목, 생김새, 성격, 기억, 대사 |

모든 문구는 `{"ko": "...", "en": "..."}` 형식으로 두 값을 채운다. `power`에는 `moonflower_leap`, `light_swap`, `seal`, `wind` 중 하나를 쓴다. 권능을 섞어 연습하는 장은 `null`로 둔다. 정령 그림이 준비되면 `pubspec.yaml`에 경로를 추가한다.

사가에 이야기와 레벨 경로를 등록하고 두 JSON을 번들에 넣은 뒤 `flutter test -r failures-only test/world_content_test.dart`를 실행한다. 이 테스트는 공개 세계의 이야기, 정령 연결, 에셋 번들, 저장된 최단 풀이를 확인한다. 세계 1은 기존 `season1.json`과 코드에 있는 별자리 정의를 사용한다.
