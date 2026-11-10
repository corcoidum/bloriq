# 기믹 탐색 비용

## 세계 4-A 시곗바늘 칸

### 표본과 측정 방법

- 생성 시드 `442026`으로 뽑은 첫 200판을 비용 표본으로 사용했다. 모두 5×5이며 리크 외 블록 2–3개, 시곗바늘 칸 2–4개, 추가 기믹 1개가 있다. 추가 기믹은 민들레, 호박석, 물길, 클로버, 달 수정 문, 거울 짝을 33–34판씩 섞었다. 100판은 권능 없이, 나머지는 권능 4종을 하나씩 25판에 넣어 탐색했다. 해의 유무나 난이도로 표본을 선별하지 않았다.
- Python은 시작 상태부터 첫 최단 해까지 발견한 고유 상태 수와 전체 호출 시간을 쟀다. 탐색 상태 한도는 200만 개다. 비교군은 공개 세계 2의 25판과, 비용 표본 200판에서 시곗바늘 판정 및 상태 키만 비활성화한 짝 표본이다. 두 비교 모두 판마다 지정된 권능을 유지했다.
- Flutter는 같은 판에서 저장된 풀이를 비우고 앱의 기본 `HintSearch.solve`를 순차 호출했다. `compute` isolate 생성과 결과 전달을 포함해 호출부터 응답까지 쟀다. 앱과 동일하게 탐색은 1.5초 및 20만 상태로 제한된다.
- 측정 환경은 Windows 11 x64, AMD Ryzen 5 8500G, Python 3.13.7, Flutter 3.47.8 및 Dart 3.13.7이다. Flutter 수치는 데스크톱 테스트 러너의 JIT 실행에서 측정했다.

### Python BFS

| 표본 | 해를 찾은 판 | 평균 상태 수 | 최대 상태 수 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5×5 시곗바늘 | 200/200 | 2,973.4 | 80,063 | 41.67 ms | 1,500.39 ms |
| 같은 판, 시곗바늘 비활성화 | 200/200 | 1,760.9 | 67,064 | 20.00 ms | 1,026.28 ms |
| 세계 2 공개판 | 25/25 | 9,963.6 | 32,611 | 205.28 ms | 892.22 ms |

같은 판에서 시곗바늘을 켜면 평균 상태 수가 1.69배였다. 시곗바늘 표본의 최대 상태 수와 최대 시간은 모두 표본 1152번에서 나왔다. 세계 2는 출시용으로 구성한 판이며, 시곗바늘 자체의 비용은 같은 판의 두 행으로 비교할 수 있다.

### 앱 isolate 힌트

| 표본 | 해를 찾은 판 | 1.5초 이내 응답 | 제한 종료 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5×5 시곗바늘 | 200/200 | 200/200 | 0 | 11.30 ms | 360.75 ms |
| 세계 2 공개판 | 25/25 | 25/25 | 0 | 41.82 ms | 190.17 ms |

5×5 표본의 최대 80,063개는 200만 상태 기준보다 낮아서 이 단계에서 판 크기나 타일 수에 별도 상한을 추가하지 않았다. 위 시간은 이 PC의 실측치다. 모바일 실기기와 웹에서의 응답 시간은 측정하지 않았다.

### 재현

```sh
python -m tools.clock_arrow_fixture --benchmark-output build/design_logs/clock-arrow-python.json
flutter test -r failures-only test/clock_arrow_solver_agreement_test.dart
flutter test -r failures-only test/clock_arrow_solver_agreement_test.dart --dart-define=BENCH_CLOCK_ARROW=true
```

`test/fixtures/clock_arrow_fuzz.json`은 320판과 Python 풀이를 고정한다. Dart는 거울 짝 혼합 93판을 포함한 320판 모두에서 Python과 일치했다. 해결 가능한 319판은 최단 수와 수순이 같았고, 나머지 1판은 양쪽 모두 해가 없었다. isolate 실측 원본은 `build/design_logs/clock-arrow-isolate.json`에 출력한다.

## 세계 5-A 미끄럼 얼음

생성 시드 `552026`의 첫 200판을 비용 표본으로 삼았다. 모두 5×5이며 리크 외 블록 2–3개와 얼음 2–4칸을 배치했다. 민들레, 호박석, 물길, 클로버, 달 수정 문, 거울 짝, 시곗바늘 중 하나를 판마다 섞었다. 100판은 권능 없이, 100판은 권능 4종을 각각 25판씩 넣어 측정했다. 해의 유무와 난이도로 표본을 선별하지 않았다.

### Python BFS

첫 최단 해까지 발견한 고유 상태 수와 전체 호출 시간을 쟀다. 한도는 200만 상태다. 같은 판의 비교에서는 얼음 이동만 껐다.

| 표본 | 해를 찾은 판 | 평균 상태 수 | 최대 상태 수 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5×5 얼음 | 200/200 | 2,404.4 | 66,783 | 31.74 ms | 1,089.08 ms |
| 같은 판, 얼음 비활성화 | 200/200 | 2,764.3 | 82,031 | 38.29 ms | 1,728.59 ms |

이 표본에서는 얼음을 켰을 때 발견한 상태가 평균 13.0% 줄었다. 두 행에서 상태 수와 시간이 가장 큰 판은 2023번이다. 얼음은 고정 칸의 규칙이라 상태 키에 새 값을 추가하지 않는다.

### 앱 isolate 힌트

같은 200판에 저장 풀이 없이 앱의 기본 `HintSearch.solve`를 순차 호출했다. 호출부터 결과를 돌려받기까지 isolate 실행과 전달 시간을 포함했다. 앱의 시간 제한은 1.5초이며 상태 제한은 20만 개다.

| 표본 | 해를 찾은 판 | 1.5초 이내 응답 | 제한 종료 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5×5 얼음 | 200/200 | 200/200 | 0 | 9.70 ms | 357.08 ms |

환경은 Windows 11 x64, AMD Ryzen 5 8500G, Python 3.13.7, Flutter 3.47.8 및 Dart 3.13.7이다. 앱 수치는 데스크톱 Flutter 테스트 러너의 JIT 실측이다. 모바일 실기기와 웹의 응답 시간은 측정 대상에서 제외했다.

### 재현

```sh
python -m tools.ice_fixture --benchmark-output build/design_logs/ice-python.json
flutter test -r failures-only test/ice_solver_agreement_test.dart
flutter test -r failures-only test/ice_solver_agreement_test.dart --dart-define=BENCH_ICE=true
flutter test -r failures-only test/ice_widget_test.dart --dart-define=CAPTURE_ICE_RULE=true
```

`test/fixtures/ice_fuzz.json`의 320판에는 거울 짝과 시곗바늘을 둘 다 섞은 판 30개가 있다. 319판에서 두 solver의 최단 수와 수순이 같았고, 1판은 양쪽 모두 해가 없었다. isolate 측정 원본은 `build/design_logs/ice-isolate.json`에 출력한다.

## 세계 6-A 책장 문

생성 시드 `662026`의 첫 200판을 측정했다. 5×5 160판과 6×5 40판에 리크 외 블록 2–3개와 책장 문 1–2쌍을 배치했다. 얼음이 있는 판 100개, 거울 짝이 있는 판 75개, 얼음·거울 짝·시곗바늘을 함께 쓰는 판 25개를 포함한다. 100판은 권능 없이, 100판은 권능 4종을 각각 25판씩 넣었다. 해의 유무와 난이도로 표본을 선별하지 않았다.

### Python BFS

첫 최단 해까지 발견한 고유 상태 수와 전체 호출 시간을 쟀다. 상태 한도는 200만 개다. 비교군은 같은 200판에서 책장 문 변환만 껐다.

| 표본 | 해를 찾은 판 | 평균 상태 수 | 최대 상태 수 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 책장 문 전체 | 200/200 | 2,052.7 | 119,884 | 39.56 ms | 3,297.50 ms |
| 책장 문 5×5 | 160/160 | 1,497.8 | 52,655 | 22.98 ms | 882.58 ms |
| 책장 문 6×5 | 40/40 | 4,272.1 | 119,884 | 105.90 ms | 3,297.50 ms |
| 같은 200판, 책장 문 비활성화 | 200/200 | 2,306.5 | 106,141 | 45.69 ms | 2,813.70 ms |

이 표본에서는 책장 문을 켰을 때 평균 상태 수가 11.0% 줄었다. 최대 상태와 시간은 6×5 얼음·시곗바늘 혼합판 3197번에서 나왔다. 책장 문은 위치만 바꾸므로 solver 상태 키에는 값을 추가하지 않는다. 6×5 표본도 200만 상태 기준 이내였다.

### 앱 isolate 힌트

같은 200판을 저장된 풀이 없이 `HintSearch.solve`로 순차 호출했다. 호출부터 응답까지 isolate 생성과 결과 전달을 포함한다. 앱의 제한은 1.5초와 20만 상태다.

| 표본 | 해를 찾은 판 | 1.5초 이내 응답 | 제한 종료 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 책장 문 전체 | 200/200 | 200/200 | 0 | 7.01 ms | 487.32 ms |
| 책장 문 5×5 | 160/160 | 160/160 | 0 | 4.95 ms | 171.61 ms |
| 책장 문 6×5 | 40/40 | 40/40 | 0 | 15.27 ms | 487.32 ms |

Windows 11 x64, AMD Ryzen 5 8500G, Python 3.13.7, Flutter 3.47.8, Dart 3.13.7에서 측정했다. 앱 수치는 데스크톱 테스트 러너의 JIT 실측이며 모바일 실기기·웹 측정은 남아 있다.

### 재현

```sh
python -m tools.shelf_door_fixture --benchmark-output build/design_logs/shelf-door-python.json
flutter test -r failures-only test/shelf_door_solver_agreement_test.dart
flutter test -r failures-only test/shelf_door_solver_agreement_test.dart --dart-define=BENCH_SHELF_DOOR=true
flutter test -r failures-only test/shelf_door_widget_test.dart --dart-define=CAPTURE_SHELF_RULE=true
```

`test/fixtures/shelf_door_fuzz.json`의 무작위 320판 모두에서 두 solver의 최단 수와 수순이 일치했다. 얼음·거울 짝·시곗바늘을 모두 섞은 판은 40개다. isolate 측정 원본은 `build/design_logs/shelf-door-isolate.json`에 출력한다.

## 세계 7-A 혼합 판

### 표본과 측정 방법

- 시드 `772027`로 서로 다른 기믹 36쌍에 권능 4종을 하나씩 조합했다. 5×5와 6×5에서는 조합당 무작위 판을 하나씩 뽑았다. 6×6에서는 같은 무작위 표본에 리크와 별문을 대각선 맞은편에 두고 룬석 3개와 바위 3~5개를 놓은 표본을 조합당 하나씩 더했다. 총 576판을 해의 유무와 관계없이 측정했다.
- Python은 20만 상태 한도로 처음부터 독립 BFS를 실행했다. 표의 시간은 4개 워커로 생성할 때 각 호출의 벽시계 시간이다. 한도를 넘긴 후보를 포함한 상태 수의 최대는 200,001개다.
- Flutter는 저장 풀이 없이 앱의 기본 `HintSearch.solve`를 순차 호출했다. 첫 호출로 준비한 뒤 isolate 시작·결과 전달을 포함해 576개 초기 상태를 측정했다. 6×6 대각선 표본 144개는 클리어하지 않는 첫 일반 수를 적용하고 권능을 들고 있는 상태도 측정했다.
- 실측 환경은 macOS 26.5.2 arm64, Apple M4, Python 3.14.3, Flutter 3.47.8 및 Dart 3.13.7이다. Flutter는 데스크톱 테스트 러너의 JIT 실측이다.

### Python BFS

| 크기 | 해를 찾은 판 | 상태 제한 | 평균 상태 수 | 최대 상태 수 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 5×5 | 144/144 | 0 | 2,211.8 | 66,181 | 15.40 ms | 506.24 ms |
| 6×5 | 144/144 | 0 | 3,986.6 | 117,031 | 24.12 ms | 868.73 ms |
| 6×6 | 238/288 | 50 | 60,010.6 | 200,001 | 609.02 ms | 3,179.53 ms |

### 앱 isolate 힌트

| 표본 | 해를 찾은 상태 | 상태 제한 | 1.5초 이내 응답 | 평균 시간 | 최대 시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5×5 초기 | 144/144 | 0 | 144/144 | 4.70 ms | 148.72 ms |
| 6×5 초기 | 144/144 | 0 | 144/144 | 6.54 ms | 233.23 ms |
| 6×6 초기 | 238/288 | 50 | 288/288 | 153.11 ms | 825.06 ms |
| 6×6 일반 수 이후 | 100/144 | 44 | 144/144 | 256.19 ms | 853.00 ms |

1.5초를 넘겨 응답한 표본은 0개였다. 6×6에서는 상태 한도로 풀이를 돌려주지 못한 **53개 조합**을 [생성기 금지 목록](../tools/worlds/large_board_limits.py)에 기록했다. 초기 상태에서 50개, 한 수 진행 상태에서만 추가로 3개가 나왔다. 예를 들어 `clockArrow + shelfDoor + seal`은 8564번의 초기 상태와 8565번의 일반 수 이후 상태에서 한도에 걸렸다. 6×6에서 세 번째 기믹을 넣어도 금지된 기믹 쌍과 권능을 함께 쓰지 않는다.

6×6 생성은 빠른 풀이를 **12만 상태**, 효과 제거·권능 재검증을 **20만 상태**로 제한한다. 한 후보의 풀이와 재검증에 슬롯 남은 시간 중 최대 **8초**를 쓴다. `Slot`에 더 작은 상태 한도나 전체 슬롯 시간을 줄 수 있다. 측정한 조합은 시작 상태와 일반 수 한 번을 적용한 상태의 표본이다. 모바일 실기기·웹과 임의의 후속 수순은 추가 검증 대상이다.

`Slot.mechanics`는 고정 기믹이다. `mechanic_candidates`에서 서로 다른 `mechanic_count`개를 골라 더한다. 예를 들어 고정 기믹 없이 등대 기믹 넷 중 셋을 쓰려면 `mechanics=()`, `mechanic_candidates=('mirrorPair', 'clockArrow', 'ice', 'shelfDoor')`, `mechanic_count=3`을 준다. 생성과 `--check` 모두 각 기믹을 하나씩 비활성화해 최단 수가 달라지는지 다시 푼다. 효과가 없는 기믹이 하나라도 있으면 통과하지 않는다.

캠페인 초기 상태에서는 `HintSearch.storedSolution`이 현재 권능과 시작 상태를 확인하고 저장된 풀이를 반환한다. 세계 6 공개판 25개와 권능이 있는 혼합 표본에서 시간 0, 상태 1을 설정해도 저장 풀이를 얻는 것을 테스트했다.

### 재현

```sh
python3 -m tools.mixed_fixture --workers 4
flutter test -r failures-only test/mixed_solver_agreement_test.dart
python3 -m tools.mixed_fixture --benchmark --workers 4
flutter test -r failures-only test/mixed_solver_agreement_test.dart --dart-define=BENCH_MIXED=true
```

`test/fixtures/mixed_fuzz.json`에는 시드 `772026`의 500판을 담았다. 2기믹 360판에서 모든 기믹 쌍과 권능 선택(0개 또는 4종 중 1개)을 각각 두 번 다루고, 3기믹 140판에는 가능한 84개 삼중 조합을 모두 넣었다. 두 solver는 497판의 최단 수와 수순, 3판의 해 없음 판정에서 일치했다. 비용 원본은 `build/design_logs/w7-mixed-python.json`과 `build/design_logs/w7-mixed-isolate.json`에 생성된다.
