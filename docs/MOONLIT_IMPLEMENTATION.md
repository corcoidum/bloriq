# BLORIQ 0.3.0+3 — 달빛 동화 정원 제작 결과

2026-10-29 · 작업 브랜치 `codex/bloriq-v5-1`

## 결과와 보존 범위

선택한 1번 시안의 달빛 정원, 아이보리 석재, 월석·비취 블록과 보랏빛 Echo를 기존 Flutter + Flame 게임에 적용했다. 전체 화면을 한 장의 그림으로 덮지 않고, 원화·프레임·타일·블록·정령을 각각 렌더링한다. UI 문자는 실제 한국어·영어 텍스트다.

기존 미커밋 작업을 보존했으며 퍼즐 규칙, 두 코스의 레벨 JSON, 진행 저장 키와 보상 구조를 변경하지 않았다. 기존 별·최고 기록·Undo·Restart·Preview·Replay·공유와 모션/사운드 설정을 유지했다. UI 상단은 도감·설정·도움말로 정리했고 효과음/BGM은 기존 설정 화면에서 조절한다. 공개 배포·push·main 병합은 수행하지 않았다.

## 제작 산출물

| 구분 | 내용 | 위치 |
|---|---|---|
| 배경 5개 | 정원, 수문, 우체국, 회랑, 관측소 | `assets/art/moonlit/backgrounds/` |
| 보드·장식 13개 | 프레임, 빈 칸, 월석·비취·장애물, 별문, Echo, 버튼, 등불, 꽃·안개·반딧불·꽃잎 | `assets/art/moonlit/tiles/` |
| 정령 26개 | 리크 + 25종, 개별 생성한 투명 PNG | `assets/art/moonlit/spirits/` |
| 출처·제작 정보 | 생성 결과 ID/원본 경로, 원본 프레임, 추가 생성 정보 | `assets/art/moonlit/sources/` |
| 선택 시안 | 원본 보존 | `docs/art/moonlit-selected-reference.png` |
| 글꼴 | Cormorant Garamond, SIL OFL 라이선스 원문 포함 | `assets/art/moonlit/fonts/` |

44개 PNG 원본은 약55.6MiB다. PNG 원본을 보존하고 런타임에서 타일256px, 리크·정령384px, 프레임768px, 배경1024px 너비로 디코딩한다. 현재·다음 지역 배경만 캐시에 유지한다. 원화 제작에는 imagegen과 Product Design의 이미지 적용 흐름을 사용했다. 코드로 캐릭터나 배경을 대신 그린 가짜 에셋은 production 경로에서 사용하지 않는다.

## 구현 파일과 동작

- `lib/art/game_art_assets.dart`: 공통 이미지 디코딩·재사용, 현재/다음 지역 캐시, 개별 정령 로딩, 실패 후 재시도. 테스트에서 AssetBundle을 주입할 수 있다.
- `lib/art/moonlit_scene.dart`: 지역 배경과 단계별 꽃·등불·안개·별빛 조합, 완료 기록에 따른 빛 복원, 700ms 인트로 밝아짐, 실제 터치 영역 바깥의 석조 프레임. 모션 줄이기에서는 정적 최종 장면을 표시한다.
- `lib/game/bloriq_game.dart`: 실제 이미지로 타일·블록·Echo·별문을 렌더링한다. 규칙은 domain에 위임한다. 기존 독립 renderer 테스트에는 기존 색상 렌더링 경로를 보존한다.
- `lib/game/board_geometry.dart`: 셀·입력의 단일 기준을 유지하고 블록의 시각 크기를 셀의0.86으로 조정했다. 프레임은14px의 외부 여백이며 실제 GameWidget에는 포함하지 않는다.
- `lib/main.dart`: 원화 준비/오류 재시도, 간결한 헤더, 보드 아래의 동행·인트로 안내, 실제 버튼판, 이미지 캐시 주입.
- `lib/companions/`: 도감·획득·동행·정령 카드에 같은 개별 원화를 사용한다. 미획득 정령은 원화의 알파 실루엣으로 표시한다.
- `lib/game/victory_panel.dart`, `lib/postcard/echo_postcard.dart`: 석재 결과 패널, 밝은 별, 실제 지역 원화와 리크를 사용한 공유 카드. 기존 결과 데이터와 공유 경로는 보존한다.
- `pubspec.yaml`, `lib/l10n/`: 로컬 에셋·글꼴 등록, 버전0.3.0+3, 이미지 오류와 재시도 한·영 문구. 새로운 production package는 없다.

공유 카드는 같은 캐시를 사용한다. 퍼즐 도전 카드는 실제 초기 상태의 이미지 renderer를 사용하며 해답 경로를 포함하지 않는다. 기존 Echo Postcard에는 결과만 전달한다.

## 검증

| 항목 | 결과 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 144개 통과 |
| `python3 tools/validate_levels.py` | 25/25 해결 가능, BFS 최단 이동 수 일치 |
| `python3 tools/validate_art.py` | 44/44 PNG 유효, 투명 에셋 RGBA·해상도·누락 검증 |
| 원화 전용 테스트 | 이미지 재사용, frame/Echo 중앙 투명, 실패 로드 재시도, 배경 캐시 경쟁 요청, 첫5 renderer 좌표, 25종 원화 및 카드 렌더링 통과 |
| 첫5 수직 슬라이스 | 실제 드래그·보상·도감·동행·재실행 복원 통과 |
| 전체25 플레이 | 실제 widget 드래그와 각 단계의 수집 개수 검증 통과 |
| 화면 캡처 실행 | 별도12개 테스트 통과, 기본 실행의 캡처 전용 테스트는 파일을 쓰지 않음 |
| 화면 크기 | 320×568,360×800,393×852,412×915,600×960; 단계1/6/14/25; Light/Dark 총40장 |
| 접근성 | 한국어·영어, 글꼴2배, DPR2.625/3, 앱/시스템 모션 줄이기 회귀 통과 |
| 브라우저 | 실제 한국어 이동·Echo·클리어·도감1/25·동행 선택·새로고침 복원 확인; 검증 중 console error/warn 없음 |
| 빌드 | Android debug APK 및 Web 빌드 성공 |

이미지 디코딩은 native 비동기 작업이므로 기존 widget 테스트에는 가상 시계 바깥에서 **production과 같은 실제 원화를 준비하는 helper**를 추가했다. 게임 상태·규칙에 대한 assertion은 유지했다.

## 화면과 비교

- [시안/실제 브라우저 비교](moonlit-comparison.html)
- [디자인 QA](../design-qa.md)
- [첫 단계](screenshots/moonlit/light-stage-1.png)
- [Echo](screenshots/moonlit/light-echo.png)
- [수호 정령 보상](screenshots/moonlit/light-reward-5.png)
- [도감](screenshots/moonlit/light-collection.png)
- [리크와25종 원화 시트](screenshots/moonlit/matrix/character-sheet.png)
- [4×4 기믹·Dark](screenshots/moonlit/matrix/dark-393-stage-14.png)
- [Stage25](screenshots/moonlit/matrix/light-393-stage-25.png)
- [브라우저 재실행 후 동행 복원](screenshots/moonlit/browser-restored.jpg)

선택 시안은 가상4×4 배치를 포함한다. 실제 Stage1은 기존3×3를 보존했으므로 픽셀 단위 복제로 평가하지 않으며, 같은393×852 화면에서 아트·가독성·배치의 충실도를 비교한다. 기믹은 이미지 시안의 잘못된 배치를 복제하지 않고 실제 domain 상태를 따른다.

## 실행·설치·재검증

```sh
cd /Users/corcoidum/CCD/bloriq
export PATH="/tmp/bloriq-flutter/bin:$PATH"
export PUB_CACHE=/tmp/bloriq-pub-cache
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
python3 tools/validate_levels.py
python3 tools/validate_art.py
flutter run -d chrome
```

검증 화면 재생성(macOS의 지정 Unicode 글꼴 필요):

```sh
flutter test test/moonlit_capture_test.dart test/responsive_board_test.dart --dart-define=CAPTURE_MOONLIT=true
```

Android SDK가 준비된 환경:

```sh
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

`-r`은 기존 앱 위에 업데이트 설치한다. 기존 기록 보호를 위해 테스트 시 앱 데이터 삭제나 기존 앱 제거를 먼저 하지 않는다. 서명이 다른 기기에서는 설치가 거부될 수 있으므로 삭제로 우회하지 말고 서명부터 확인한다.

## 남은 검증과 제한

연결된 Android 실기기가 없어 실기기의 터치 감도·음원 출력·프레임 성능·비행기 모드·시스템 공유 시트는 미검증이다. 자동 화면 캡처는 Golden 기준 통과나 실기기 성능 측정으로 표시하지 않는다. APK는 debug 테스트용이며 스토어 출시용 서명·최적화는 포함하지 않는다.

기존 `share_plus` Kotlin Gradle Plugin 관련 향후 호환성 경고와 Web Cupertino 폰트 탐색 경고는 빌드 로그에 남지만 현재 빌드는 성공했다. 원본 PNG 용량과 저사양 기기 메모리/로딩 속도는 실기기 결과를 기준으로 후속 최적화한다.
