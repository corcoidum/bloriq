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
