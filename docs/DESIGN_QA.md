# BLORIQ 테마 · 클리어 연출 QA

2026-10-29 구현 검증 기록입니다. 게임 규칙과 스테이지 데이터는 그대로 유지하고 표시 계층과 설정을 변경했습니다.

## 최종 실행 결과

- `flutter analyze`: No issues found.
- `flutter test`: 84개 통과. 화면 캡처는 기본 실행에서 비활성입니다.
- opt-in 화면 캡처 테스트: 통과, 개선 전 1장 + Light/Dark 24장 생성.
- `python3 tools/validate_levels.py`: 25/25 해결 가능, 기록된 최소 이동 수와 BFS 결과 일치.
- `flutter build apk --debug`: 성공. `build/app/outputs/flutter-apk/app-debug.apk` 생성.
- `git diff --check`: 통과. domain 규칙, levels 데이터, pubspec 및 lock 파일 변경 없음.
- Android 기기 설치/실행은 이번 검증에 포함하지 않았습니다. APK 빌드 성공과 실기기 실행 검증은 구분합니다.

## 주요 변경 파일

| 파일 | 역할 |
|---|---|
| `lib/design/game_theme.dart` | GameColors, GameTheme, GameTypography, GameSpacing, GameEffects 및 대비 확보용 Ink 토큰 |
| `lib/settings/game_settings.dart` | System 기본값, 설정 복원과 순차 저장, 저장 실패 안내 상태 |
| `lib/settings/settings_dialog.dart` | 테마·모션·오디오 설정 UI |
| `lib/main.dart` | ThemeMode 연결, 단일 연출 타임라인, 스킵·watchdog·화면 전환 정리, 세로 드래그/스크롤 충돌 방지 |
| `lib/game/bloriq_game.dart` | Canvas 테마 주입, 최대 12개 burst + 4개 최고 기록 sparkle, blur 없는 연출 |
| `lib/game/victory_panel.dart` | 별 순차 표시, 결과 패널, 최고 기록 Gold 강조 |
| `lib/postcard/echo_postcard.dart` | 미리보기와 공유 이미지의 동일 테마 적용 |
| `lib/l10n/app_*.arb` | 한국어·영어 설정 및 건너뛰기 문구 |

별과 기록은 완료 순간 계산/저장하고 연출은 표시만 담당합니다. 기본 타임라인은 1.45초이며 ticker가 정지하면 1.65초 watchdog이 결과 UI를 복구합니다. Reduced Motion에서는 즉시 결과를 표시합니다. 주요 본문/버튼 및 Echo 문자 대비를 자동 검사합니다.

## 화면 비교

[Light/Dark 나란히 보기 및 개선 전후 비교](design-comparison.html)

- 390×844 논리 픽셀의 Flutter widget renderer에서 캡처합니다. Android 실기기 스크린샷은 아닙니다.
- 영어 UI, 캡처용 Arial Unicode 글꼴과 앱의 MaterialIcons를 사용합니다. 실제 Android의 한국어 글꼴 모양과 줄바꿈은 다를 수 있습니다.
- `before-stage-1.png`는 작업 시작 시 Git HEAD의 `main.dart`와 renderer를 임시 폴더에서 실행한 화면입니다. headless 테스트의 Ahem 사각형 글꼴을 피하기 위해 Canvas 라벨에만 캡처용 `Roboto` family를 지정했습니다. 게임 레이아웃·색상·규칙은 기존 코드입니다.
- 캡처 시 사운드/BGM 설정을 꺼서 headless 환경에 없는 native 오디오 플러그인을 호출하지 않습니다. 실제 사운드 출력은 이 캡처로 검증하지 않습니다.
- Stage 2는 지우개 칸에서 시작하는 일반 블록의 첫 이동 뒤 Echo가 없으므로, 해법의 두 번째 이동 후 Echo를 캡처합니다.
- 클리어 이미지는 약 1.45초 시퀀스의 다른 시점입니다. 최종 결과 화면은 버튼이 보이도록 스크롤한 상태입니다.

| 화면 | Light | Dark |
|---|---|---|
| Stage 1 | [보기](screenshots/light-stage-1.png) | [보기](screenshots/dark-stage-1.png) |
| Stage 2 Echo | [보기](screenshots/light-stage-2-echo.png) | [보기](screenshots/dark-stage-2-echo.png) |
| Stage 14 Switch/Gate | [보기](screenshots/light-stage-14-gate.png) | [보기](screenshots/dark-stage-14-gate.png) |
| Stage 14 열린 Gate | [보기](screenshots/light-stage-14-open-gate.png) | [보기](screenshots/dark-stage-14-open-gate.png) |
| Stage 20 | [보기](screenshots/light-stage-20.png) | [보기](screenshots/dark-stage-20.png) |
| Escape 확대 | [보기](screenshots/light-victory-escape.png) | [보기](screenshots/dark-victory-escape.png) |
| Echo Burst | [보기](screenshots/light-victory-burst.png) | [보기](screenshots/dark-victory-burst.png) |
| 순차 별 표시 | [보기](screenshots/light-victory-stars.png) | [보기](screenshots/dark-victory-stars.png) |
| 새 최고 기록 | [보기](screenshots/light-victory-new-best.png) | [보기](screenshots/dark-victory-new-best.png) |
| 일반 재클리어 | [보기](screenshots/light-victory-repeat.png) | [보기](screenshots/dark-victory-repeat.png) |
| 설정 | [보기](screenshots/light-settings.png) | [보기](screenshots/dark-settings.png) |
| 도움말 | [보기](screenshots/light-help.png) | [보기](screenshots/dark-help.png) |

## 자동 검증 범위

- `game_settings_test.dart`: System 기본값, Light/Dark/System 복원, Reduced Motion 복원, 손상된 설정과 저장 실패, 빠른 연속 저장.
- `game_theme_test.dart`: 두 테마의 팔레트 역할과 본문/버튼 색 대비.
- `canvas_appearance_test.dart`: 기존 `BloriqGame`에 팔레트 주입, 애니메이션/Reduced Motion과 퍼즐 상태 분리, 스킵 시 효과 종료.
- `theme_victory_flow_test.dart`: 게임 도중 설정 변경 시 동일 controller/state 유지, OS 밝기 변경과 명시적 선택 우선순위, 앱 위젯 재시작 후 설정 복원.
- 같은 흐름 테스트에서 Light/Dark 각각 완료 직후 기록 저장, 연출 스킵, 연속 드래그의 중복 완료 방지, 다음 스테이지 전환을 검증합니다.
- 320×568 화면·2배 글꼴에서 게임/설정/도움말의 overflow와 접근 가능한 스크롤을 확인합니다.
- 클리어 중 스테이지 변경, OS Reduced Motion 활성화, ticker 정지 시 독립 타이머의 결과 화면 복구를 검증합니다.
- 기존 domain, mechanic, solver, replay, postcard, progress 및 첫 10개 스테이지 드래그 회귀 테스트를 유지합니다.

Flutter 위젯 재생성/플랫폼 밝기 mock/SharedPreferences mock 검증은 Android 프로세스 강제 종료 및 실제 디스크 복원 테스트와 구분합니다.

## 재현 명령

SDK가 PATH에 있는 환경에서 프로젝트 루트에서 실행합니다.

```sh
flutter gen-l10n
flutter analyze
flutter test
python3 tools/validate_levels.py
```

화면 캡처는 별도 opt-in이며 일반 테스트는 이미지 파일을 생성하지 않습니다.

```sh
flutter test test/visual_capture_test.dart --dart-define=CAPTURE_DESIGN=true
```

macOS 기본 캡처용 글꼴 경로는 `/System/Library/Fonts/Supplemental/Arial Unicode.ttf`입니다. 다른 환경에서는 적절한 Unicode TTF 경로를 지정합니다. 캡처 글꼴은 앱 의존성에 포함하지 않습니다.

```sh
flutter test test/visual_capture_test.dart \
  --dart-define=CAPTURE_DESIGN=true \
  --dart-define=DESIGN_FONT=/absolute/path/to/unicode-font.ttf
```

## Android 실기기에서 남은 확인

- 저사양 Android에서 Stage 14/20 및 클리어 burst의 frame time, 발열, 배터리 소모.
- 효과음/BGM 실제 출력, 음소거 정책, 앱 background/foreground 복귀.
- 기기 OS Light/Dark 변경, 앱 강제 종료/재실행 후 테마 및 기록의 실제 디스크 복원.
- Android 시스템 Reduced Motion/애니메이션 설정과 TalkBack의 실제 전달·읽기 순서.
- 한국어 UI의 기기별 대체 글꼴, 최대 글꼴/디스플레이 배율, 매우 좁은 화면의 터치 편의성.

성능에 관한 현재 근거는 제한된 입자 수, blur 미사용 및 자동 상태/렌더링 검증입니다. 실기기 FPS 수치는 아직 측정하지 않았습니다.

기존 `share_plus`의 Kotlin Gradle Plugin 사용에 대한 향후 Flutter 호환성 경고가 빌드에 남습니다. 현재 debug 빌드는 성공했으며, SDK 업그레이드 전 플러그인 호환성을 재확인해야 합니다.
