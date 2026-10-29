# BLORIQ — 마지막 Echo 오프닝

## 결과

- 버전: 0.3.1+4
- 영상: `assets/video/bloriq-opening.mp4` — 720×1280, 9:16, 24fps, 12초, H.264 / AAC, 약 2.6MB.
- 원본 음악: `assets/audio/opening.wav` — 직접 합성한 celesta와 ambient pad. 외부 음원/보이스 없음.
- 미리보기: 실행 서버의 `/opening-preview.html`.
- 공개 배포, Git push, main 병합은 하지 않았다.

## 연출

| 시간 | 장면 | 자막 |
|---|---|---|
| 0–3.8초 | 달빛 정원과 먼 등대, 천천히 다가가는 카메라, 흐르는 안개와 빛 | 기억의 등대가 잠든 밤… |
| 3.8–7.8초 | 리크가 한 발 나아가며 속이 빈 보랏빛 Echo가 남고 사라짐 | 작은 전령 리크의 발걸음에 잊힌 빛의 잔상이 남았습니다. |
| 7.8–12초 | 기억의 빛이 별문으로 이동하고 타이틀 등장 | 별문 너머, 당신을 기다리는 기억이 있습니다. |

시즌 결말의 등대 정지 이유와 리크의 과거를 공개하지 않는다. 기존 게임 원화의 리크/정원/별문을 사용한 **모션 그래픽 영상**이다. 자유로운 캐릭터 동작을 새로 생성한 AI 영상은 아니다. Higgsfield Seedance 생성 시도는 `Requires plus plan or higher`로 작업 제출 전 실패했으며, 클라우드 영상 작업 ID/결과는 없다.

## 게임 연결

- 실제 앱 진입점 `main()`에서 OpeningGate를 활성화한다. 시작 포스터에서 ‘이야기 시작’을 누르면 재생하고, 종료 후 ‘모험 시작’으로 보드에 진입한다.
- 건너뛰기는 로딩 중에도 가능하다. 영상 시청으로 진행 기록이나 보상을 변경하지 않는다.
- 앱 내부에서는 MP4 디코더 대신 **동일한 OpeningFilmPainter 타임라인**을 직접 렌더링한다. 네트워크/비디오 코덱/추가 production dependency가 필요 없다. MP4는 같은 painter를 288프레임 렌더링한 배포용 결과물이다.
- 게임 내 도움말의 ‘인트로 다시 보기’에서 영상을 재생하고, 기존 첫 이동 튜토리얼로 이어진다.
- 기존 BGM 음소거를 읽는다. 재생 중 음악 버튼은 해당 영상에만 적용한다. 재시청 중 게임 BGM은 잠시 중지한다.
- 앱/시스템 모션 줄이기에서는 정적인 최종 장면과 ‘모험 시작’을 바로 표시한다. 백그라운드 전환은 타임라인과 소리를 일시 정지한다.
- 한국어/영어 자막과 버튼을 지원한다. 다운로드용 MP4는 한국어다.

## 수정 파일

- `lib/intro/opening_film.dart`: 공통 painter, 타이머, 재생/음악/건너뛰기/복귀.
- `lib/main.dart`: 시작 gate와 도움말의 다시 보기 연결.
- `tools/generate_opening_audio.py`: 음원 생성기(표준 Python만 사용).
- `test/opening_film_test.dart`: 진입/저장 독립, 모션 줄이기, 12초 재생과 lifecycle, 선택적 MP4 내보내기.
- `test/collection_flow_test.dart`: 다시 보기에서 영상 건너뛰기 검증 추가.
- `web/opening-preview.html`: HTML video로 MP4 감상/다운로드.
- `pubspec.yaml`: 버전 및 오프라인 MP4 asset 등록. production dependency 변경 없음.

## 검증

- `flutter analyze`: No issues found.
- 전체 `flutter test`: **148개 통과**.
- 영상 생성 포함 전용 테스트: 4개 통과.
- 재생 후 실제 보드 진입, 한국어 종료 장면: in-app browser에서 확인, console warning/error 없음.
- FFmpeg로 MP4 전체 288프레임/12초와 오디오 스트림 디코딩 정상 확인.
- HTML video도 브라우저에서 duration 12초, 720×1280, ended=true까지 재생 확인.
- Android debug APK, Web 빌드 성공.
- Android 실기기 재생/음량은 연결 기기가 없어 확인하지 못했다.

## 재실행

```sh
export PATH="/tmp/bloriq-flutter/bin:$PATH"
export PUB_CACHE=/tmp/bloriq-pub-cache
python3 tools/generate_opening_audio.py
flutter analyze
flutter test
flutter build web
python3 -m http.server 8890 --bind 127.0.0.1 --directory build/web
```

MP4 재생성에는 개발 도구 FFmpeg가 필요하다. 현재 임시 개발 venv의 imageio-ffmpeg(게임 dependency 아님)를 사용했다.

```sh
flutter test test/opening_film_test.dart \
  --dart-define=EXPORT_OPENING=true \
  --dart-define=FFMPEG=/private/tmp/bloriq-video-tools/lib/python3.14/site-packages/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1
```

내보내기 한글 폰트 테스트는 macOS의 Arial Unicode를 사용한다. 다른 OS에서는 해당 테스트의 폰트 로더 경로를 로컬 한글 폰트로 변경한다. 앱은 플랫폼 폰트로 렌더링한다.
