# 별배달부 아트 에셋

2026-10-29. 사용자가 선택한 2번 시안 `docs/design/star-courier-selected.png`를 실제 참조로 첨부해 built-in ImageGen으로 생성했다. 원본은 별도로 보존했고 이 폴더에는 프로젝트에서 소비하는 PNG를 복사했다. 코드 도형이나 스크린샷 잘라내기로 캐릭터를 대체하지 않았다.

| 파일 | 원본 픽셀 | 소비 영역 |
|---|---|---|
| night_forest.png | 856×1838 RGB | 공통 정적 배경·Postcard |
| courier.png | 1254×1254 RGBA | 실제 목표/일반 블록·인트로·완료·대화상자 |
| courier_rest.png | 1536×1024 RGBA | 홈·일반 휴대폰 게임 상단 |
| echo.png | 1254×1254 RGBA | 한 턴 Echo·Preview·인트로·Postcard |
| star_portal.png | 1254×1254 RGBA | 출구·Daily·인트로·Postcard |
| board_frame.png | 1254×1254 RGBA | 게임판 외부 9-slice 프레임 |

캐릭터·Echo·출구·프레임은 실제 alpha를 가진다. Echo는 내부가 비어 있어 같은 크기의 정령과 구분된다. 원본 생성 픽셀은 요청한 목표 크기와 다를 수 있다. Canvas 스프라이트는 실행 시 최대 폭 384px로 디코딩하며, 원본 파일을 매 프레임 디코딩하지 않는다.

폰트는 이 폴더의 생성물이 아니다. `assets/fonts/`의 [Jua](https://fonts.google.com/specimen/Jua), [Nanum Gothic](https://fonts.google.com/specimen/Nanum+Gothic)은 각 OFL 원문을 동봉했다. 앱 설정의 ‘글꼴 및 오픈소스’에서 확인할 수 있다.

## 최종 생성 프롬프트

### night_forest.png

```text
Asset type: full-bleed portrait environment background for a live mobile Flutter puzzle game. Create ONE text-free original illustrated background matching the attached visual reference's exact painterly matte storybook forest-night atmosphere, navy/indigo/dusk violet and subdued warm tiny cottage windows. Target composition 1024x2200 portrait (~390x844 logical pixels). The attachment is style and environment reference ONLY; REMOVE all UI, text, numbers, controls, board/grid, characters, sprites, stars/portals/coins. A few soft forest canopy branches frame UPPER CORNERS, small warm crescent moon at upper-right near y10%, tiny distant warm cottage window group around upper20% along far edges. Very important: keep the central width80% from y25%-85% almost empty calm solid-deep-navy painterly sky/shadow, low texture, low contrast, no prominent objects, no paths, no lights, no stones, no canopy across center, because real interactive puzzle UI will overlay there. Quiet non-busy background; no shiny bloom, neon or plastic. Along bottom5%-10% soft foreground blue-green leaves and low mossy framing only around corners; bottom center stays open navy. Opaque background. No character of any kind, no grid, no text, no gold exit or star icons, no mockup or device. Produce usable clean production game background artwork, not a UI screenshot.
```

### courier.png

```text
Use case: stylized-concept. Asset type: ONE production game sprite, genuine transparent RGBA background. Generate a single isolated original mint forest-spirit star-courier character matching the mint character inside the attached BLORIQ gameplay reference. Dimensions 1024 x1024 square. This is a sprite asset, NOT a UI screen. Frontal orthographic view, rounded-square soft square body, TWO small triangular catlike ear tips, tiny two-leaf sprout growing from top-center, tiny paws, small peach circular cheeks, two sleepy-but-OPEN dark dot eyes, tiny dark oval mouth. It must have friendly slightly drowsy expression but eyes visible and open for directional game feedback. Soft hand-painted matte gouache texture and subtle pale-mint rim light, no glossy plastic/3D toy shine, no thick contour, same painterly midnight-storybook aesthetic as reference. Entire silhouette fits comfortably inside frame, centered, fills about85% width/height including sprout, square body footprint must remain legible when displayed48px. No leaf or ear cropped. Body mint, cheeks peach, eyes ink-navy. Isolate character ONLY, no rock, forest, scene, UI, lettering, grid, portal, stars, extra characters, opaque square or colored backdrop. Fully transparent alpha outside sprite; very subtle local contact shadow allowed only at tiny feet.
```

### courier_rest.png

```text
Use case stylized-concept. Generate ONE separate HERO illustration asset for Flutter mobile game header, LANDSCAPE3:2 composition about1536x1024, genuinely transparent RGBA background. Reference1 is selected BLORIQ night forest game design; reference2 is production mint courier sprite whose identity must remain consistent. Depict SAME original mint rounded-square cat forest spirit with two small triangular ears, two-leaf sprout, peach round cheeks, tiny dark mouth, this time gently CLOSED sleepy eyes as reference1. Character is resting chin/paws on a low wide blue SLATE mossy rock, sleepy and cozy, with tiny delicate sprigs and one small cream flower at outer rock edges. Match original mockup hero resting upon rock, not whole game UI. Rock is broad low irregular mound, dark midnight navy/purple slate with restrained moss strokes, some soft warm rimlight. Character occupies central upper55% and rock lower25%; subject entire silhouette fully in frame with transparent margin. Painterly matte gouache/paper texture, delicate brushwork, no glossy plastic, no digital neon, original small cute game illustration. Asset intended display240x140 game and330x200home, ensure clear simplified shapes and no excessively tiny details. Isolate ONLY sleeping mint creature+rock+small edge sprigs. NO background forest, no rectangle, no ground plane beyond rock, no stars, no text, no UI, no grid, no exit portal, no extra characters. All outside irregular hero silhouette must be fully transparent alpha, not white/black background. Keep mint hue/face/bodyproportions/leaf identity from reference2. Do not crop ears or sprout.
```

### echo.png

```text
Use case: stylized-concept. Asset type: ONE standalone transparent Echo afterimage sprite for BLORIQ. Reference image1 is the selected game concept; reproduce only the HOLLOW LAVENDER OUTLINE in middle-left board cell. Reference image2 is the current mint courier sprite and gives the identity silhouette: a wide rounded-square body, two small triangular cat ears, tiny two-leaf sprout atop, tiny front paws. Generate that same character's departed-location contour only, in muted bright LAVENDER, with a soft hand-painted gouache paper edge matching the storybook reference. Use a spaced dotted/dashed thin lavender perimeter, sparse restrained local violet glow, and ONE small simple lavender hourglass centered inside. Make the shape instantly recognizable at48px. The CENTER MUST BE EMPTY AND GENUINELY TRANSPARENT, except the hourglass. NO solid body, no face, eyes, cheeks, filled head, mint pixels, tile, background, grid, frame, text, extra object or second character. Front-facing orthographic silhouette centered, fills85% of a1024x1024 square canvas. Render genuine transparent alpha both outside contour and inside body. This is an empty imprint marking a temporary blocked cell, must never read as another live character. Preserve true transparency without an opaque square.
```

### star_portal.png

```text
Use case: stylized-concept. Asset type: standalone transparent game sprite for the gold exit portal in the attached BLORIQ mobile gameplay concept. Reference image role: style and exact portal design source; recreate only the middle-right cell's golden circular star doorway as its own isolated sprite. Frame1024x1024, genuine transparent background alpha. ONE warm honey-gold five-point star, softly lit and hand-painted matte gouache paper texture, enclosed inside a thin gold circular doorway ring. Orthographic straight front view, star centered, ring circular and complete. Ring diameter about80% of canvas, with generous clean transparency beyond. Very restrained warm local radiance and three or four tiny sparkles near ring only. The silhouette must be instantly recognisable when rendered at48px. Match storybook nocturnal star-courier atmosphere and pale cream-gold edge highlights, NOT shiny metallic casino coin, NOT embossed currency, NOT a badge or reward coin. No text, letters, numbers, background, landscape, grid, tile, frame, character or extra objects. No dark opaque square behind the object. Preserve all genuine alpha transparency.
```

### board_frame.png

```text
Use case: stylized-concept. Asset type: transparent game UI board border only, intended 9-slice Flutter board-frame overlay. Create ONE square 1024x1024 transparent PNG asset. Use the attached selected BLORIQ screenshot ONLY as material/style reference for the slate stone outer board frame. Generate a THIN worn matte midnight blue/slate rounded-square stone RING, subtle lavender bevel, restrained hand-painted gouache grain matching that original reference. Front orthographic no perspective. Outer rounded square nearly fills canvas, outer bounds approximately15px from edges, corner radius80px, consistent THIN approximately32px edge thickness. Flat straight repeatable middle edges for 9-slice stretching; sparse tiny fine cracks/material flecks on border only, no deep shadows. All central opening MUST be COMPLETELY TRANSPARENT alpha0: enormous empty see-through rounded-square opening, no solid center, no background, no black fill. Canvas outside ring also genuinely transparent. No grid lines, no cells, no UI, no text, no character, no star, no coin, no vines/flowers/plants, no plinth/base, no cast shadow panel. Only one simple thin elegant stone outline-frame asset. The game will independently render tiles and sprites inside it, so absolutely no artwork across transparent opening. Preserve restrained midnight indigo/pale violet rim tones, not shiny plastic or bright neon.
```
