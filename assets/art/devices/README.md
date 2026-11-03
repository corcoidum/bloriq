# 정령 장치 그림 슬롯

이 폴더에 아래 이름의 PNG를 넣으면 앱을 다시 빌드할 때 코드 그림 대신 자동으로 쓰인다. 없는 파일은 코드 그림이 유지되므로 한 장씩 넣어도 된다.

**공통 규격**: 정사각형 RGBA(투명 배경), 512×512 이상, 정면(orthographic), 칸을 거의 가득 채우되 여백 4% 이내. 글자·격자·캐릭터 없음.

| 파일 | 장치 | 그림 |
|---|---|---|
| `gate_closed.png` | 덩굴 달문 (닫힘) | 돌 아치 입구를 굵은 덩굴이 X자로 엮어 막음 |
| `gate_open.png` | 덩굴 달문 (열림) | 덩굴이 양쪽 기둥으로 물러나고 입구가 빛남 |
| `switch_bud.png` | 달빛 꽃판 (닫힘) | 둥근 돌판 위 닫힌 꽃봉오리 |
| `switch_bloom.png` | 달빛 꽃판 (핌) | 같은 돌판, 활짝 핀 달꽃과 금빛 수술 |
| `eraser.png` | 별먼지 샘 | 돌 테두리 안 라벤더 소용돌이 샘 |
| `hold.png` | 호박 이슬 | 모래시계가 굳어 있는 호박 물방울 |
| `oneway.png` | 바람 잎길 | **오른쪽을 가리키는** 잎 화살촉 3개. 게임에서 회전시킨다 |
| `goal_only.png` | 리크 이끼 | 민트 이끼 쿠션 위 크림색 발자국과 작은 금빛 별 |
| `wall.png` | 이끼 돌 | 이끼 덮인 둥근 바위. 움직일 수 없어 보여야 한다 |

## 생성 프롬프트

기존 `assets/art/last_echo/riq.png`를 스타일 참조로 첨부하고, 공통 문장 뒤에 항목별 문장을 붙인다.

**공통**

```text
Use the attached BLORIQ sprite as the style reference: matte hand-painted cozy gouache and paper texture, soft storybook night-forest palette of deep navy, mint green, soft purple, warm gold and moonlight blue. One isolated game board object, front orthographic view, centered, filling about 96% of a square canvas, readable at 48 pixels. Genuine transparent RGBA background. No text, grid, tile, character, frame or extra objects. Not glossy, not neon, not metallic.
```

**항목별**

- `gate_closed`: `A small mossy stone archway with a crescent moon keystone in moonlight blue. Thick green vines weave across the dark opening in an X and completely block it.`
- `gate_open`: `The same stone archway with the crescent moon keystone. The vines have drawn back around both pillars and the open doorway glows with soft mint and moonlight blue.`
- `switch_bud`: `A round carved stone plate with a thin moonlight-blue ring, a single closed lavender flower bud in the center.`
- `switch_bloom`: `The same round stone plate, the flower now fully open with six lavender petals fading to pale blue and a warm gold center, soft glow.`
- `eraser`: `A small round spring with a stone rim, lavender water swirling in a spiral with tiny gold stardust specks.`
- `hold`: `A large amber dew drop resting on a small mint moss patch, with a dark hourglass silhouette frozen inside the amber.`
- `oneway`: `Three leaf-shaped chevrons in mint green pointing to the RIGHT in a row along a soft moonlight-blue breeze lane.`
- `goal_only`: `A rounded mint moss cushion with a cream paw print in the center and one tiny warm-gold five-point star at the upper right.`
- `wall`: `A rounded immovable grey-blue boulder with a patch of green moss on top and one small crack, heavy and solid.`
