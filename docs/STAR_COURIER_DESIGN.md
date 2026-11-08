# 작은 별의 길 — 2번 시안 적용 결과

2026-10-29 · `codex/star-courier-design` · 기준 커밋 `4006bcd`.

## A. 현재 상태와 선택

선택한 이미지는 [2번 원본](design/star-courier-selected.png)이다. 밤하늘 숲, 잠든 새싹 정령, 보랏빛 Echo, 금빛 별 출구를 실제 Flutter·Flame 화면으로 옮겼다. 정적인 시안 전체를 배경으로 붙인 구현이 아니다. 텍스트·버튼·게임판·대화상자는 실제 위젯이며 게임판은 기존 엔진이 그린다.

## B. 적용 구조

| 영역 | 적용 |
|---|---|
| 공통 | 남색 숲 / 밝은 새벽 팔레트, 제목 Jua·본문 NanumGothic, 48px 이상 조작 영역 |
| 홈 | 작은 브랜드 → 이야기 제목 → 돌 위의 정령 → 큰 플레이 버튼 → 간단한 진행 요약 → Daily |
| 인트로 | 기존 4초 타임라인에 같은 정령·Echo·별 그림 재사용, 무음·건너뛰기·모션 줄이기 유지 |
| 게임 | 제목과 스테이지 선택을 상단에 모으고, 정령 일러스트·이동 배지·돌 테두리 게임판·Undo/Restart 순서로 구성 |
| 작은 화면 | 높이 700px 미만은 상단 장면을 접어 게임판을 우선한다. 큰 글꼴·가로 화면은 외부 스크롤을 제공한다. |
| 클리어 | 완료된 게임판을 작게 보여 결과와 다음 버튼 공간 확보. 다음 단계로 갈 때 스크롤을 처음으로 돌린다. |
| Daily·챕터 | 별 문양과 같은 표면·색상 적용. 날짜·7일 기록·기록 분리는 그대로 유지 |
| 설정·도움말·공유 | 같은 정령·서체·표면 사용. 포스트카드는 추상 도형 대신 실제 정령·Echo·별을 조합 |

## C. 실제 변경과 보존 경계

- 새 설치의 기본 화면 테마는 Dark다. 이미 저장된 Light/Dark/System 선택은 그대로 복원한다. 시스템 테마 옵션을 제거하지 않았다.
- 보라색 Echo는 속이 빈 정령 윤곽과 모래시계로 표시한다. 일반 친구는 푸른 색과 원형 배지, 목표 정령은 민트로 구분한다.
- 이동 시 작은 기울기 반응을 더한다. 앱/시스템의 모션 줄이기가 켜지면 기울기와 기존 이동 연출을 생략한다. 배경은 정적이다.
- 돌 프레임은 별도 투명 PNG를 9-slice 방식으로 배치한다. 좌표계 바깥 여백에 두고 `IgnorePointer`로 터치를 통과시킨다. 이미지가 이동 판정을 맡지 않는다.
- `lib/design/star_art.dart`가 스프라이트를 한 번 읽어 최대 폭 384px로 디코딩하고 Canvas에서 재사용한다. 이미지 준비와 게임 데이터 로딩은 분리한다.
- 튜토리얼 중 새 상단 스테이지 선택을 비활성화한다. 건너뛴 뒤 선택을 허용한다. 안내가 진행 중인 상태를 실수로 탈출하지 않게 했다.
- 기존 25개 배치·기믹·별 평가·revision·진행 저장·Daily 풀·분석 동의 정책은 변경하지 않았다. 새 production package, 광고 SDK, 서버, release 서명 변경은 없다.
- 새 그림 6개는 built-in ImageGen으로 제작한 원본 PNG다. [에셋 기록](../assets/art/star_courier/README.md)에 용도·프롬프트·라이선스 출처를 남겼다.

주요 변경: `lib/design/`, `lib/game/`, `lib/app/`, `lib/main.dart`, `lib/daily/daily_panel.dart`, `lib/postcard/echo_postcard.dart`, `lib/settings/`, KO/EN ARB, `pubspec.yaml`.

## D. 검증

- `flutter pub get`, `flutter gen-l10n`: 실행 완료. dependency/lockfile 변경 없음.
- `dart format lib test`: 변경 없음으로 마감.
- `flutter analyze --no-pub`: 문제 없음.
- `flutter test --no-pub`: **153개 통과**. 실제 드래그, Echo·Gate·Undo·Restart·Replay·Postcard·Daily·이전 기록 및 테마 변경 회귀를 포함한다.
- 신규 그림 테스트는 투명 PNG의 외곽 alpha와 Echo 내부 빈 공간, 목표/일반 친구의 시각 구분을 실제 디코딩한 이미지로 확인한다.
- `python tools/validate_levels.py`: **25/25 해결 가능·최단 이동 일치**.
- `python -m unittest tools.test_hybrid_tools -q`: **5개 통과**.
- `flutter build web --release --no-pub --dart-define=BUILD_TAG=star-courier-2026-10-29`: **성공** (`build/web`).
- 별도 캡처 테스트: `flutter test test/hybrid_visual_capture_test.dart --dart-define=CAPTURE_STAR=true`. Light/Dark × 한국어/영어 × 15개 상태, 실제 Flutter 렌더링 **60장**, 비교 자료 2장이다.
- 320px 화면·가로 화면·태블릿·200% 글꼴은 기존 위젯 회귀 테스트로 확인했다. 시안/구현의 직접 비교는 [design-qa.md](../design-qa.md)를 참고한다.

### 발견하고 고친 문제

1. 큰 글꼴에서 인트로 하단 문구가 넘쳤다. 스크롤 가능한 인트로 구성으로 고쳤다.
2. 높이가 작은 화면에서 그림과 게임판이 조작을 밀어냈다. 상단 장면을 접고 보드 크기를 계산하도록 바꿨다. 레벨 연속 드래그 테스트를 다시 통과했다.
3. 제목용 서체를 모든 문구에 적용하면 중간점 등 일부 글리프와 가독성이 좋지 않았다. 본문 서체와 제목 서체를 분리했다.
4. 생성 프레임이 블록에 겹치지 않게 외부 여백으로 옮겼다. 프레임은 이벤트를 받지 않는다.
5. 밝은 테마에서 Echo와 별 출구가 흐려 보였다. 해당 테마의 의미 색으로만 명도를 낮춰 윤곽을 구분한다. Dark의 원본 이미지 색은 유지했다.

브라우저 조작은 이전 접근 승인 거절 이후 재시도하거나 다른 경로로 우회하지 않았다. 화면 자료는 브라우저 캡처가 아니라 Flutter widget renderer의 출력이다. Android SDK/실기기 검증과 프레임 측정은 수행하지 않았다. 빌드와 자동 테스트를 사람의 플레이 검증이나 모바일 출시 검증으로 간주하지 않는다.

## E. 실행과 다음 검증

```powershell
flutter pub get
flutter gen-l10n
flutter run -d chrome
# Android SDK와 기기를 준비한 뒤
flutter run -d "YOUR_DEVICE_ID"
```

현재 PC의 Flutter는 PATH에 없으므로 실제 명령에는 SDK `bin/*.bat` 절대 경로를 사용했다. Android 기기가 연결되면 `flutter devices`에서 확인한 device ID로 실행한다.

[전체 화면 모음](star-courier-review.html) · [디자인 비교 결과](../design-qa.md) · [기존 플레이 관찰표](PLAYTEST_OBSERVATION.md)

다음 검증은 실제 휴대폰의 작은 캐릭터 식별, Echo와 일반 친구 구분, 저사양 기기의 이미지 메모리·시작 시간이다. 광고와 출시 서명은 이번 변경에 포함하지 않았다. 원격 푸시·main 병합도 하지 않았다.
