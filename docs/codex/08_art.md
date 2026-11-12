# 08 그림 — 정령 초상화와 세계 보드 스킨

일반 정령 초상화는 해당 판을 깨면, 수호 정령 원화는 별자리의 다섯 별을 모두 켜면 열린다. 세계 2~7의 일반 정령 120장, 수호 정령 30장과 보드 스킨 40장은 내장 ImageGen으로 만들었다. [에셋별 프롬프트](../art/world2-7-imagegen-prompts.md)

## 분량
| 세계 | 수호 정령 원화 | 일반 정령 | 보드 스킨 |
|---|---|---|---|
| 2 구름바다 | 5 | 20 | 바닥 4, 바위 2 |
| 3~6 각 세계 | 5 | 20 | 바닥 4, 바위 2, 새 기믹 칸 1~2 |
| 7 첫 별 | 5 | 20 | 바닥 4, 바위 2 |
| 합계 | **30** | **120** | **40** |

## 스타일 기준 (지금 그림과 맞추기)
- 참고: `assets/art/season1/*.png`(세계 1 정령), `assets/art/moon_garden/*.png`(보드 타일), 별자리 도감의 수호 정령 원화.
- 동화책 같은 부드러운 수채·파스텔, 둥근 실루엣, 큰 눈, 밤하늘 배경에서도 읽히는 밝은 윤곽.
- 정령: 정사각 1024×1024, 투명 배경(배경 제거), 캐릭터가 화면의 70% 안쪽.
- 타일: 정사각 256×256 이상, 위에서 내려다본 시점, 이음새 없이 반복되는 바닥 4종.

## 이미지 생성 프롬프트 틀
```text
A cute storybook spirit character for a cozy night-sky puzzle game, soft watercolor and pastel, rounded silhouette, big gentle eyes, glowing outline readable on a dark navy background, centered, full body, plain background for easy cutout, no text.
Character: {정령 appearance 영어 문구 그대로}. Personality: {personality 영어 문구}. World motif: {세계 모티프}.
```
세계 모티프:
- 세계 2: cloud sea, lighthouse stairs, mist harbor, wind corridor, lantern top
- 세계 3: moonlit mirror lake, water lilies, mist bridge, upside-down tower reflection, shadow
- 세계 4: brass clockwork, gears, bell loft, pendulum, midnight
- 세계 5: ice cave, frost crystals, icicles, snowstorm, frozen memory machine
- 세계 6: dream library, floating books, paper birds, ink, hourglass
- 세계 7: starry sky, five lighthouses' colors, first star

타일 프롬프트:
```text
Top-down seamless game floor tile, {세계 모티프} theme, soft storybook watercolor, muted night palette with {세계 강조 색} highlights, subtle texture, no objects, no text, square.
```

## 넣는 법 (그림이 생기면 Codex에게)
```text
BLORIQ 저장소에서 세계 {N} 그림을 연결해 줘. AGENTS.md를 따르고, origin/main에서 codex/w{N}-art를 만든다.
- assets/art/world{N}/spirits/s{N}-NN.png(정령), assets/art/world{N}/board/{floor_1..4,rock_1..2}.png(타일)를 받았다.
- assets/story/world{N}.json의 각 정령 asset에 경로를 넣고, saga.json 세계 {N}의 theme.floor/rock에 기본 타일을 넣는다. floorVariants/rockVariants에는 추가 변형을 넣고, mechanicArt는 기믹 ID를 타일과 연결한다. pubspec assets에 폴더 추가.
- 그림은 1024px 정령은 512px webp 또는 png로 줄여 앱 용량을 아낀다(세계당 15MB 이하). 원본은 저장소에 넣지 않는다.
- 별자리 도감 수호 정령 공개, 정령 도감, 보드 화면 캡처를 docs/screenshots/world{N}/art/에 남긴다.
검증 명령 통과 후 커밋·푸시·보고.
```

세계 지도 상단의 정령 도감에서 수집 현황을 볼 수 있다. 아래 명령으로 세계별 보드, 수호 정령 공개, 정령 도감 캡처를 다시 만든다.

```bash
flutter test -r failures-only test/world_art_test.dart --dart-define=CAPTURE_WORLD_ART=true
```
