# 달빛 숲 정원 보드 에셋

2026-11-07. 게임판·장애물·기믹 칸이 코드 도형이라 캐릭터·배경 일러스트와 어울리지 않던 문제를 고치기 위해 만들었다. 먼저 보드 전체 시안 3장을 만들어 사용자가 1번(밝은 이끼 판석 + 고목 테두리)을 골랐고, 그 시안을 스타일 레퍼런스로 개별 스프라이트를 생성했다.

- 생성: Magnific(Freepik) 이미지 생성 Auto 모델, 레퍼런스 `night_forest.png`·`riq.png`·`star_portal.png`·`rune_stone.png`와 선택한 시안. 단색 배경 위에 그리게 했다.
- 배경 제거·자르기: `python3 tools/process_moon_garden.py <원본 폴더>` (Pillow). 원본 생성 PNG는 저장소에 넣지 않았다.
- 밀 수 있는 블록은 기존 `assets/art/last_echo/rune_stone.png`, 잔상은 리크 그림을 보라색으로 물들여 그린다. 열린 덩굴 문은 닫힌 문 그림을 코드로 양옆으로 젖혀 그린다.
- 그림이 하나라도 없으면 해당 요소만 기존 코드 그림으로 그린다(`StarArt.garden`).

| 파일 | 크기 | 쓰임 |
|---|---|---|
| floor_1~4.png | 384×384 | 바닥 판석 4종. 칸 위치로 고정 선택, 밤에는 달빛 남색을 곱한다 |
| plank.png | 384×96 | 테두리 판자 결. 색은 실행 시 고목 갈색으로 입힌다 |
| rock.png, stump.png | 384×384 | 장애물(이끼 바위·그루터기), 칸 위치로 고정 선택 |
| riq_cushion.png | 384×384 | 리크가 앉는 민트 이끼 방석 |
| tile_dandelion.png | 384×384 | 잔상 지우개 칸(×) |
| tile_amber.png | 384×384 | 잔상 유지 칸(Ⅱ) |
| tile_stream.png | 384×가변 | 한쪽 방향 칸. 오른쪽으로 흐르는 그림을 방향대로 회전 |
| tile_clover.png | 384×384 | 리크 전용 칸(▶) |
| switch_crystal.png | 384×384 | 달 수정 스위치 |
| gate_closed.png | 384×384 | 덩굴 문(닫힘). 열림은 코드 변형 |

## 생성 프롬프트 (요지)

공통 접미: painterly matte gouache storybook style matching the reference, cool moonlight from upper left, readable at 48 pixels, no text, isolated on a plain flat solid white (또는 dark navy) background.

- 보드 시안: Mobile puzzle game screenshot concept … 4x4 board framed by an old mossy wooden border with tiny glowing mushrooms … mossy flagstones … moonlight rune stones … mossy boulder and tree stump obstacles … violet ghost afterimage of Riq … dandelion cell … hexagonal amber cell … stream with leaf arrow … moon crystal plate connected by a glowing vine line to a thorny vine gate … gold star portal.
- floor: ONE single square flagstone floor tile seen straight from above, pale blue-grey weathered stone with hairline cracks and moss along the edges.
- rock / stump: ONE mossy grey boulder / short cut tree stump obstacle, 3/4 top view.
- riq_cushion: ONE empty soft mint-green moss cushion with tiny white flowers on its rim.
- tile_dandelion: small round patch of grass with three white dandelion seed puffs.
- tile_amber: ONE flat hexagonal polished amber resin gem plate.
- tile_stream: short straight stream flowing LEFT to RIGHT with a golden leaf pointing RIGHT.
- tile_clover: round patch of mint-green four-leaf clovers with tiny white flowers.
- switch_crystal: diamond-shaped pale cyan quartz crystal in a round mossy stone socket.
- gate_closed: CLOSED gate of dark twisted thorny vines woven into vertical bars.
- plank: 상자 그림(frame 생성 실패본)의 세로 판자 한 장을 잘라 결 재료로 썼다.
