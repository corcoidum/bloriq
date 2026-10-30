# 시즌 1 아트 — 신규 20종

OpenAI built-in ImageGen으로 제작한 20개 개별 투명 PNG 원본이다. 기존 5종은 `../last_echo/`와 `../star_courier/`의 원본을 유지했다. 실제 파일 크기·alpha·실루엣 경계·SHA256·표시 앵커는 [manifest.json](manifest.json)에 있다.

## 공통 제작 지시 요약

One isolated original cozy-fantasy spirit, front-facing complete silhouette, matte hand-painted gouache/paper texture matching Lulu and Lunabel references, kind navy eyes and soft cheeks. Genuine transparent RGBA, square canvas, generous transparent margins. No text, UI, scene, ground platform, detached effects or additional character.

위 문구와 아래 표는 재현용 생성 지시 요약이며 전체 원문과 동일하다고 주장하지 않는다. 여백이 부족한 결과는 ImageGen으로 구도만 보정했다. 픽셀 편집·크롭·리사이즈로 생산 원본을 수정하지 않았다.

| ID·이름 | 실루엣·포즈 지시 | 원본 |
|---|---|---|
| s1-06 Lumi | Small round body with little star antenna; Gentle sway. Always finds the first light in the dark. | [lumi.png](lumi.png) |
| s1-07 Pico | Small round body with star cheek mark; Curious tilt. Collects tiny sparks to share. | [pico.png](pico.png) |
| s1-08 Tori | Small round body with crescent ears; Little wave. Listens carefully to sounds beyond the gates. | [tori.png](tori.png) |
| s1-09 Mio | Small round body with sparkling ribbon tail; Short float. An eager explorer who scouts new paths. | [mio.png](mio.png) |
| s1-10 Lumen | Small round body with small five-star crown; Welcoming bow. Opens gates slowly and waits for every friend. | [lumen.png](lumen.png) |
| s1-11 Pepi | Small round body with folded paper ears; Gentle sway. Makes sure every last letter is delivered. | [pepi.png](pepi.png) |
| s1-12 Ribon | Small round body with ribbon tail; Curious tilt. Keeps forgotten promises in little knots. | [ribon.png](ribon.png) |
| s1-13 Coco | Small round body with envelope chest patch; Little wave. Reads slowly but understands feelings quickly. | [coco.png](coco.png) |
| s1-14 Noti | Small round body with small paper wings; Short float. Stays beside friends who are unsure how to reply. | [noti.png](noti.png) |
| s1-15 Ello | Small round body with letter-seal mark; Welcoming bow. Keeps every friend’s letters safe. | [ello.png](ello.png) |
| s1-16 Poff | Small round body with fluffy cloud cap; Gentle sway. Curious about every message on the wind. | [poff.png](poff.png) |
| s1-17 Suu | Small round body with short wind tail; Curious tilt. Never misses a quiet sound or hidden signal. | [suu.png](suu.png) |
| s1-18 Momo | Small round body with puffy cloud cheeks; Little wave. Easygoing, and always looks after the last friend. | [momo.png](momo.png) |
| s1-19 Wiri | Small round body with feather-like ears; Short float. Quickly gathers wandering winds. | [wiri.png](wiri.png) |
| s1-20 Hamo | Small round body with wind-ring pattern; Welcoming bow. Listens until different voices find harmony. | [hamo.png](hamo.png) |
| s1-21 Miru | Small round body with small crystal; Gentle sway. Finds familiar feelings in unfamiliar places. | [miru.png](miru.png) |
| s1-22 Veil | Small round body with rounded violet tail; Curious tilt. Patiently waits for faded memories. | [veil.png](veil.png) |
| s1-23 Or | Small round body with constellation ear marks; Little wave. Calmly puts scattered fragments in order. | [or.png](or.png) |
| s1-24 Luche | Small round body with dewdrop crystal; Short float. Shines a light on faint forgotten marks. | [luche.png](luche.png) |
| s1-25 Aster | Small round body with little star crown with three crystals; Welcoming bow. Quiet, but remembers every friend’s name. | [aster.png](aster.png) |

## 투명 여백과 앱 표시

20종은 모두1254×1254 RGBA이며 alpha0–255, 모서리 alpha≤8을 확인했다. 극히 희미한 가장자리 alpha 잔여는 원본에 보존했다. 소형 표시에서는 각 실루엣의 alpha≥128 경계로 표시 배율과 중심을 정규화한다. 앱은 같은 정규화 값을 도감·동행·공유에 사용하며 실제 파일을 잘라 저장하지 않는다.

25종을 실제48px 슬롯에 렌더링한 [검토 화면](../../../docs/screenshots/moonstone-season1/dark-ko-portraits-48.png)에서 확인했다. 서로 다른 모자·귀·꼬리·수정·몸 무늬를 사용한다. 일부 미세한 별자리 선은 작은 화면에서 약해지므로 실루엣과 색을 함께 구분 기준으로 삼는다.

RIQ는 퍼즐 주인공으로 별도 유지한다. 일반 블록은 얼굴 없는 코드 렌더링 Blue 룬석이다. 친구 아트를 퍼즐 장애물로 사용하지 않는다. 모든 친구 반응은 짧은 상하·기울기·부유·인사 변형이며, 모션 줄이기에서는 정적이다.
