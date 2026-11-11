# BLORIQ

BLORIQ 1.0.0 후보는 리크와 룬석을 밀어 별문까지 길을 만드는 오프라인 퍼즐입니다. 블록이 떠난 칸에 한 턴 동안 남는 echo가 다음 이동의 길을 바꿉니다.

## 플레이 모드

| 모드 | 플레이 방식 |
| --- | --- |
| 다섯 등대의 빛길 | 일곱 세계를 잇는 캠페인 175판. 세계마다 25판과 별자리 5개를 완성합니다. |
| 별바다 항해 | 등불이 꺼질 때까지 연속으로 퍼즐을 풉니다. 달빛 숲 정원의 첫 별자리를 완성하면 열리고, 진행 중인 항해를 이어서 할 수 있습니다. |
| 오늘의 잔상 | 기기의 로컬 날짜에 배정된 퍼즐 한 판을 풉니다. 클리어와 연속 성공 기록은 캠페인과 별도로 집계합니다. |

별바다 항해는 4번째 바다부터 기믹이 등장하고, 23번째 바다부터 폭풍 바다로 이어집니다. [항해 난이도와 판 구성](docs/ENDLESS.md)

### 일곱 세계

| 세계 | 스테이지 | 주요 규칙 |
| --- | --- | --- |
| 달빛 숲 정원 | 1–25 | echo와 문, 민들레, 호박석, 물길, 클로버 |
| 구름바다 등대 | 101–125 | 기존 칸 규칙과 별자리 권능 |
| 거울 호수 등대 | 201–225 | 함께 움직이는 거울 짝 |
| 시계탑 등대 | 301–325 | 이동마다 방향이 바뀌는 시곗바늘 |
| 얼음 동굴 등대 | 401–425 | 얼음 위 미끄러짐 |
| 꿈의 서고 등대 | 501–525 | 같은 무늬를 잇는 책장 문 |
| 첫 별 | 601–625 | 다섯 등대의 규칙과 권능을 함께 쓰는 혼합 판 |

앞 세계의 별자리 5개를 완성하면 빛길 지도에서 다음 세계가 열립니다. 마지막 별자리를 완성한 뒤 결과에서 **빛길의 끝으로**를 눌러 엔딩을 볼 수 있습니다. 사가 완료 보상은 ‘첫 별의 잔상’ 칭호와 ‘첫 별빛’ 이동 잔영입니다. 설정에서 엔딩과 크레디트를 다시 열 수 있습니다. [엔딩 화면](docs/screenshots/ending/) · [첫 별 레벨 검토](docs/LEVEL_REVIEW_W7.md)

## 게임 방법

- 리크를 상하좌우로 드래그해 별문까지 이동합니다. 일반 이동이 끝나면 출발 칸에 echo가 남고, 이전 echo는 사라집니다. 스위치 위의 echo는 문을 열어 줍니다.
- 민들레에서 떠나면 echo가 사라지고, 호박석에서 떠나면 이전 echo가 유지됩니다. 물길에서는 화살표 방향으로 나갈 수 있고, 클로버에는 리크만 들어갑니다.
- 드래그 중에는 이동 가능 여부와 도착 칸을 확인할 수 있습니다. 되돌리기는 직전 위치와 echo, 시곗바늘 상태를 복원합니다.
- 캠페인에서 별과 최고 기록을 확인하고, 정령의 기억과 별자리를 도감에서 다시 볼 수 있습니다. 결과 화면에서 해결 과정을 리플레이하거나 정령 포스트카드를 공유할 수 있습니다.
- 설정에서 모션 줄이기, 효과음, 배경 음악을 조절할 수 있습니다. 모션 줄이기를 켜면 엔딩은 정지 장면과 페이드로 재생됩니다. 도움말에서 배운 규칙을 다시 연습할 수 있습니다. [퍼즐 규칙](docs/MECHANIC_RULES.md)

## 실행

검증 환경은 Flutter 3.47.8과 Dart 3.13.7입니다. Chrome에서는 마우스로 드래그해 플레이할 수 있습니다. [Flutter 설치 문서](https://docs.flutter.dev/get-started/install) · [다른 컴퓨터에서 이어서 작업하기](docs/HOME_HANDOFF.md)

```bash
flutter pub get
flutter gen-l10n
flutter run -d chrome
```

Android에서는 `flutter devices`로 기기를 확인한 뒤 `flutter run -d <기기_ID>`를 실행합니다. Android 테스트 APK의 버전 코드는 8이며, 빌드 결과는 `build/app/outputs/flutter-apk/app-release.apk`에 생성됩니다. `android/key.properties`가 없으면 기존 Gradle 설정이 테스트용 디버그 키로 서명합니다. [Android 휴대폰 테스트 안내](docs/ANDROID_PHONE_TEST.md)

## 검증

```bash
flutter gen-l10n
flutter analyze
flutter test -r failures-only
python3 tools/validate_levels.py
for world in 3 4 5 6 7; do python3 -m tools.level_audit --world "$world"; done
flutter build apk --release
```

엔딩 캡처 6장을 다시 생성하려면 다음 명령을 실행합니다.

```bash
flutter test -r failures-only test/world7_ending_test.dart --dart-define=CAPTURE_ENDING=true
```

엔딩 배경 음악과 게임 음원은 `python3 tools/generate_audio.py`로 합성합니다. 글꼴 주아, 감자꽃, 고운돋움, 나눔고딕의 SIL Open Font License 1.1 전문은 크레디트에서 읽을 수 있습니다.

## 기록과 데이터

진행 기록은 기기에 저장됩니다. 캠페인은 스테이지별 최고 별과 이동 수를 보존하고, 별바다 항해는 진행 중인 판과 점수, 등불을 복원합니다. 앱 데이터 삭제나 앱 제거 시 기기 기록이 사라질 수 있습니다.

선택형 플레이테스트 기록은 기본 꺼짐입니다. 설정에서 동의한 경우에만 기기에 기록하며, 파일을 선택해 직접 내보낼 수 있습니다. 내보낸 기록은 Git에서 제외한 `playtest-exports/`에 보관합니다. [오프라인 분석 예시](docs/HYBRID_EXECUTION.md)

캠페인 판은 `assets/levels/`에, 세계별 이야기와 정령은 `assets/story/`에 있습니다. 판을 추가할 때는 생성기에서 만든 뒤 독립 Python 검증기로 풀이와 최단 수를 확인합니다. [제작 순서](docs/ROADMAP_LIGHTROAD.md)
