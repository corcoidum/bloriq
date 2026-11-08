# BLORIQ 시작 경험·아케이드 디자인 검증

검증일: 2026-10-29. 기준 코드: `37841b2`에서 이어진 로컬 변경사항.

## 구현된 흐름

```text
앱 시작 → 4초 무음 인트로 → 홈 → 플레이 / 스테이지 선택 → 게임
                       ↓
          완료 수·별 합계·첫 미완료 단계 표시
```

- 앱을 새로 실행하면 인트로를 다시 보여준다. 첫 프레임부터 건너뛸 수 있다.
- 0–0.6초 격자 등장 → 0.6–1.6초 첫 이동과 Echo → 1.6–2.6초 출구 도달 → 2.6–3.3초 파동·입자 → 3.3–4초 로고로 구성한다.
- 인트로는 게임과 같은 `BlockArt`로 그리며 실제 진행 기록을 수정하지 않는다. 영상·이미지 다운로드와 새 production dependency는 없다.
- 앱/시스템 모션 줄이기를 적용하면 인트로를 생략한다. 연출 중 모션 줄이기를 켜도 즉시 종료한다. Ticker가 멈추면 4.2초 watchdog이 홈으로 전환한다.
- 인트로 중 백그라운드로 이동하면 종료한다. 게임 도중 백그라운드 복귀는 현재 보드와 Undo를 보존한다.
- 플레이 버튼은 **배열에 정의된 스테이지 순서**에서 첫 미완료 단계를 고른다. 모두 완료하면 첫 단계로 돌아간다. 기록에 없는 옛 코스 ID는 요약에 합산하지 않는다.
- 홈 복귀 시 완료 수·별·다음 단계가 갱신된다. 미완료 판에 이동이 있으면 홈 버튼과 시스템 뒤로 가기 모두 초기화 확인을 표시한다.
- 설정의 인트로 다시 보기는 현재 게임을 바꾸지 않는다. 홈과 인트로에서는 오디오 설정을 저장 변경하지 않고 재생만 중단한다. 플레이 입력 이후 기존 설정대로 음악을 시작한다.
- 데이터 로딩은 인트로와 독립적이다. 늦어지면 홈에서 준비 상태를 보여주고, 실패하면 재시도할 수 있다.

## 화면과 구조

- Light/Dark 공통으로 Mint 목표·Purple Echo·Gold 출구를 유지한다. 블록 하이라이트·그림자, 공통 표면·버튼·배지, 정적인 배경 그라데이션을 사용한다.
- 홈, HUD, 결과 패널, 스테이지 그리드, 설정·도움말·포스트카드 대화상자의 스타일을 통일했다. 효과음과 BGM 토글은 설정에 모았다.
- 스테이지 선택은 번호·최고 별·현재 단계 표시가 있는 스크롤 그리드다. 25개 단계 모두 바로 선택할 수 있다.
- 앱 세션이 스테이지·진행 저장소·오디오를 소유한다. 게임 화면은 공유 세션과 진입할 `levelId`를 받는다. `BloriqApp`의 `loadLevels`·`settings` 주입은 유지했다.
- 퍼즐 규칙, 코스 JSON, 기록 저장 키와 schemaVersion을 변경하지 않았다. 미완료 판은 앱을 종료하면 보존되지 않는다.

## 실제 검증 결과

| 확인 | 결과 |
|---|---|
| Flutter / Dart | 3.47.8 / 3.13.7 실행 확인 |
| `flutter analyze --no-pub` | 오류·경고 없음 |
| `flutter test --no-pub --reporter expanded` | 114개 통과 |
| `python tools/validate_levels.py` | 25/25 해결 가능, BFS 최단 이동 수 일치 |
| `flutter build web --release --no-pub` | 성공, `build/web` 생성 |
| 별도 화면 캡처 | 46개 PNG 생성, 주요 화면 시각 확인 |
| 실제 브라우저 조작 | 로컬 주소 접근에 대한 브라우저 도구 승인 거절로 미실행 |
| Android profile·실기기 오디오·프레임 | 연결된 Android 기기가 없어 미실행 |

위젯 테스트는 자동 완료·연속 건너뛰기·느린 로딩·재시도·앱 재실행·첫 미완료 선택·전체 완료·홈 요약 갱신·이탈 확인·인트로 다시 보기·OS 복귀·모션 줄이기·Ticker 중단을 포함한다. 기존 드래그·Undo·Restart·Gate·별 평가·리플레이·공유·설정 저장 회귀 테스트도 함께 통과했다.

화면 적합성 테스트는 Light/Dark × 한국어/영어 × 320×568 / 390×844 / 768×1024에서 글자 크기 200%로 홈·스테이지 선택·게임·설정·도움말을 확인한다. 터치 버튼은 최소 48 logical pixels다.

웹 빌드에는 Flutter의 선택적 Cupertino font 관련 안내가 출력된다. 빌드는 성공했으며 새 패키지를 추가하지 않았다. 생성 PNG는 Flutter 위젯 렌더러의 결과다. 브라우저 및 Android 실기기 성능 자료로 해석하지 않는다.

## 화면 확인과 재현

[테마·개선 전후·인트로 프레임 비교](arcade-design-review.html)를 브라우저에서 열 수 있다. 캡처는 `screenshots/arcade/`에 있으며 기존 스크린샷은 비교용으로 유지했다.

```powershell
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
python tools/validate_levels.py
flutter run -d chrome
```

생성된 release 웹을 실행하려면 다음 명령 후 `http://127.0.0.1:8877`을 연다. 개발 서버가 이미 실행 중이면 다시 시작할 필요가 없다.

```powershell
flutter build web --release
python -m http.server 8877 --bind 127.0.0.1 --directory build/web
```

캡처 파일 쓰기는 일반 테스트에서 비활성화한다. Windows에서는 한국어를 포함한 실제 글꼴을 명시한다.

```powershell
flutter test test/visual_capture_test.dart --dart-define=CAPTURE_DESIGN=true --dart-define=DESIGN_FONT=C:/Windows/Fonts/malgun.ttf
```

## 남은 실기기 확인

1. Android 연결 후 `flutter run --profile -d <deviceId>`로 시작·건너뛰기·드래그·앱 전환·오디오를 확인한다.
2. 60Hz 기기에서 DevTools로 인트로 UI/raster 프레임을 측정하고 16.7ms 예산을 넘는 프레임을 기록한다.
3. 네트워크를 끈 상태에서 콜드 스타트, 기록·설정 복원, 음소거, 모션 줄이기를 확인한다.

커밋·푸시·스토어 배포는 이번 작업에 포함하지 않았다.
