# 첫 챕터 아트 제작 기록

2026-10-30 · 선택한 [2번 밤숲 시안](../../../docs/design/star-courier-selected.png)의 색감·종이 질감 계승. OpenAI built-in ImageGen으로 생성/수정한 원본 PNG다. 다른 게임의 캐릭터는 참조하지 않았다. 모리는 기존 `../star_courier/courier.png`를 재사용한다.

## 실제 파일

| 파일 | 역할 | 제작 상태 |
|---|---|---|
| riq.png | 크림색 플레이 주인공, 별 표식·짧은 보라 꼬리 | 실제 사용 |
| riq_happy.png | 반달 눈과 작은 미소 | 보상·길 열림 반응 |
| riq_thinking.png | 살짝 올라간 눈썹·생각하는 입 | Echo 차단 반응 |
| riq_surprised.png | 둥근 눈·작은 O 입 | Echo 생성 반응 |
| pomi.png | 꽃봉오리 관·꽃잎 발·짧은 손 흔들기 포즈 | 2번 친구 |
| doto.png | 도토리 모자·둥근 귀·모은 앞발 | 3번 친구 |
| lulu.png | 이슬 장식·작은 잎 날개 | 4번 친구 |
| lunabel.png | 달꽃·잎 관·친구를 감싸는 잎 부채 | 5번 수호 정령 |
| rune_stone.png | 얼굴 없는 Blue 룬석·원형 문양 | 일반 퍼즐 블록 |
| echo.png | 속 빈 Purple 점선 사각 윤곽·모래시계 | 모든 블록의 범용 잔상 |

모두 실제 **1254×1254 RGBA**이며 투명 모서리를 확인했다. 원본을 임의 크롭/리사이즈하지 않았다. Canvas는 최대 폭 384px로 디코딩해 재사용하며 Flutter 이미지도 캐시 폭을 제한한다. 외곽 미세 반투명 픽셀과 실제 실루엣은 다르므로 전체 alpha>0 경계만으로 중심을 잡지 않는다.

RIQ 네 표정의 alpha>128 경계는 x 약100~1119, y297~1055로 1px 수준 차이다. 공통 시각 앵커 `(0.486, 0.539)`를 보드 셀 중심에 맞춘다. 목표 받침·외곽선은 민트로 별도 렌더링한다. 룬석은 중심 앵커이며 모든 표시 영역은 공통 셀의 84% 이내다.

루루는 첫 결과의 날개 여백을 ImageGen으로 보정했다. alpha>16 경계 `(134,253)–(1125,1053)`. 루나벨은 `(139,170)–(1128,1088)`. Echo는 외부와 내부가 투명하며 귀·얼굴·잎이 없어 친구와 혼동하지 않는다. 포미와 도토는 실루엣과 높이가 다르며, 도감은 동일 정사각형 안에서 자연스러운 크기 차이를 유지한다.

## 디자인 지시 요약

아래는 긴 생성/수정 프롬프트를 제작 재현용으로 줄인 요약이다. 원문 전체와 동일하다고 간주하지 않는다.

**공통:** `One isolated original character; front orthographic view, matte hand-painted cozy gouache/paper texture matching selected night-forest family, navy eyes and soft cheeks, full silhouette centered with generous transparent margins. Genuine transparent RGBA square. No background, platform, text, UI or additional character.`

**RIQ:** `Cream-white rounded slightly square body, tiny round top nubs and paws, warm-gold five-point star beside character-left/viewer-right eye, short lavender tail tucked at viewer-left. No leaf, sprout or triangular ears. Friendly dot eyes and tiny mouth.`

Framing 수정은 정체성·질감·색을 유지하고 시각 중심과 상하 여백을 조정했다. 표정 수정은 `Change ONLY face; preserve silhouette, body, star, tail, paws, source framing and alpha`를 지시했다. Happy는 closed crescent eyes, Thinking은 mild puzzlement/raised brow/sideways mouth, Surprised는 friendly larger round eyes/tiny O mouth다.

**포미:** `Warm cream and pale peach rounded seedlike body, pink flowerbud crown, small petal feet, large navy eyes, joyful tiny mouth, one stubby hand waving. Distinct from Mori, no cat ears or leafsprout.`

**도토:** `Warm cream and chestnut rounded body, fitted acorn cap with short stem, round ears and short tail. Shy thoughtful head tilt, paws held close to chest. No flower, leafsprout or cat ears.`

**루루:** `Round cream forest friend, soft teal accents, one round dew ornament, two small raised leaf wings, shy expression and tiny paws. Complete body with generous alpha margins, readable at48px.`

**루나벨:** `Compact round ivory guardian, forest-green leaf crown, small crescent-moon flower atop, short soft tail, tiny paws, gently raised leafy wing fans. Calm kind eyes, small cute guardian, not humanoid queen.`

**룬석 디자인 기준:** 얼굴·귀·발 없이 둥근 푸른 돌, 원형 룬 문양, 과도한 광택 없이 기존 숲의 gouache 소재와 맞춘다. 친구가 아닌 이동 가능한 장애물로 읽혀야 한다.

**Echo:** `Universal hollow rounded-square lavender dotted contour and one tiny centered hourglass. Restrained local glow, no ears, leaves, face, paws or tail. Interior/exterior genuinely transparent except contour and hourglass. No solid tile.`

## 범위

현재는 정면 PNG·얼굴 교체·작은 위젯 상하/회전 반응이다. 관절·날개별 sprite animation, 25종 아트 전체, 영상 파일을 제작했다고 표현하지 않는다. 모션 줄이기에서는 정적이며 배경은 항상 정적이다. 폰트 라이선스는 기존 `assets/fonts/*-OFL.txt`와 앱 라이선스 화면에 보존했다.
