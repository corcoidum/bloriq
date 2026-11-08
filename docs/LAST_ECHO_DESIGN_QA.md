이전 `affe391` 첫 챕터 구현 기록입니다. 최신 전체 시즌은 [달빛 석판 시즌 1](MOONSTONE_SEASON1.md)을 참고하세요.

# THE LAST ECHO — 첫 챕터 디자인 QA

**final result: passed**

판정 범위는 실제 Flutter 렌더링과 자동 화면/입력 검사다. 브라우저·Android 기기 실행·사람의 이해도나 프레임 성능 판정은 포함하지 않는다.

- 기준 시안: [2번 밤숲 원본](design/star-courier-selected.png). 남색 밤숲·따뜻한 Gold 제목·보라 Echo·별문·gouache 질감을 계승했다.
- 실제 기준 화면: [새 튜토리얼](screenshots/last-echo/dark-ko-tutorial.png), [홈](screenshots/last-echo/dark-ko-home.png), [도감](screenshots/last-echo/dark-ko-album.png), [수호 정령 발견](screenshots/last-echo/dark-ko-discovery-5.png), [밝은 영어 홈](screenshots/last-echo/light-en-home.png).
- 새 캡처 viewport는393×852 logical pixels, DPR1이다. [비교 PNG](screenshots/last-echo/board-comparison.png)는 기존390×844 화면과 새 화면의 종횡비를 보존해 나란히 놓았다. 원본·생산 아트는 변형하지 않았다.
- 리크/친구/룬석을 구분하는 역할 변경은 사용자가 확정한 새 브리프에 따른 의도적인 차이다. 홈은 동행·진행·이어하기를 중심으로 재구성했고, 원본의 돌 위 휴식 장면을 억지로 유지하지 않았다.

| 발견 | 수정 | 확인 |
|---|---|---|
| 실제 GameWidget 너비가 계산값보다2px 작음 | 중복 표면 테두리 제거, 공유 geometry | 72개 실화면/DPR·레벨 조합의 실제 입력 검사 통과 |
| 프레임이 게임판 위에 그려질 수 있음 | 프레임 먼저, 불투명 판은 그 뒤의 자식으로 렌더링; 여백24px | 판 가장자리·터치 비가림과 경계 검사 |
| 목표와 일반 블록이 둘 다 친구로 보임 | 크림 RIQ+민트 표식 / 얼굴 없는 Blue 룬석 / 범용 Purple Echo | 실제 1·5번 및 기존 특수 기믹 캡처·입력 회귀 |
| 긴 별문 제목이 좁은 그리드에서 넘침 | 첫5번은 높이가 내용에 맞는 세로 별문 목록 | KO/EN·320px·200% 글꼴 회귀 통과 |
| 발견 보상과 이야기 팝업이 겹칠 위험 | 결과 카드 하나, 즉시 다음/넘기기 | 첫5번 연속 플레이·Skip·재시도·도감 다시 읽기 통과 |
| 첫 생성 표정의 여백/정체성 차이 | 같은 RIQ를 참조한 얼굴만 수정, 공통 앵커 | 표정별 alpha 경계 약1px 차이, 정렬 유지 |
| 작은 화면에서 동행이 판을 밀어냄 | 높이700px 미만은44px 동행·대사 축소, 판 최소 셀과 외부 스크롤 | 320px/가로 화면·resize/Undo 회귀 통과 |

본문/제목 서체 분리와48px 조작 영역, 모션 줄이기·무음 정책은 유지했다. 발견 연출 중 화면이 어둡게 보이는 중간 전환 프레임을 최종 화면으로 사용하지 않도록 캡처 타이밍도 조정했다. 전체 증거는 [화면 모음](last-echo-review.html)과 [실행 기록](LAST_ECHO_CHAPTER1.md)에 있다.
