"""세계 2 구름바다 등대의 슬롯 설정."""

from tools.validate_levels import LEAP, SEAL, SWAP, WIND
from tools.worlds import Slot

# (목표 최소 수, (가로, 세로), 일반 블록 수, 바위 수 범위, 기믹, 강조 권능, 필수 여부, 의도, 쓸 수 있는 권능)
# 스테이지마다 쓸 수 있는 권능을 한두 개로 제한한다. 네 권능을 모두 주면 지름길이 너무 많아
# 5x5 에서도 8수 남짓에 그치므로, 장마다 한 권능(마지막 장은 두 권능)만 열어 퍼즐을 깊게 만든다.
# 목표 최소 수는 그 권능을 쓸 때의 최단 수다. 장마다 첫 판은 새 권능을 익히도록 7~12수로 쉽게 열고,
# 다섯째 수호 정령 판(15~19수)에서 정점을 찍는 톱니 곡선이다(월드 1 마지막은 16수).
SLOTS = (
    # 1장 구름 계단 — 달꽃 도약
    Slot(7, (4, 4), 2, (2, 4), (), LEAP, False, '바위를 뛰어넘으면 돌아가는 길이 짧아진다', (LEAP,), 'world2-easy'),
    Slot(10, (4, 4), 2, (2, 4), ('echoHold',), LEAP, False, 'Hold 와 도약 중 무엇이 먼저인지', (LEAP,), 'world2-easy'),
    Slot(11, (5, 4), 2, (3, 5), ('goalOnly',), LEAP, False, '전용 칸 너머로 착지하기', (LEAP,), 'world2-easy'),
    Slot(12, (5, 4), 2, (3, 5), ('echoEraser',), LEAP, False, '도약한 자리도 잔상이 된다', (LEAP,), 'world2-easy'),
    Slot(12, (5, 5), 2, (4, 7), (), LEAP, True, '수호 정령: 도약 없이는 닿지 않는 섬', (LEAP,), 'world2-easy'),
    # 2장 안개 항구 — 빛 교대
    Slot(8, (4, 4), 2, (2, 4), (), SWAP, False, '잔상 자리로 블록을 불러오기', (SWAP,), 'world2-medium'),
    Slot(11, (5, 4), 2, (2, 5), ('echoHold',), SWAP, False, 'Hold 로 남긴 잔상과 교대', (SWAP,), 'world2-medium'),
    Slot(12, (5, 4), 2, (3, 5), ('goalOnly',), SWAP, True, '리크만 갈 수 있는 길에서 잔상과 바꾸기', (SWAP,), 'world2-medium'),
    Slot(12, (5, 4), 2, (3, 5), ('echoEraser',), SWAP, False, '지우개로 잔상을 고르고 교대', (SWAP,), 'world2-medium'),
    Slot(13, (5, 5), 2, (4, 7), ('echoGate',), SWAP, True, '수호 정령: 문 앞 잔상과 자리를 바꾼다', (SWAP,), 'world2-medium'),
    # 3장 등대지기의 계단 — 봉인
    Slot(9, (4, 4), 2, (1, 4), ('echoGate',), SEAL, False, '봉인으로 문을 한 턴 더 열어 두기', (SEAL,), 'world2-hard'),
    Slot(13, (5, 4), 2, (2, 5), ('echoGate',), SEAL, True, '두 번 지나가야 하는 문', (SEAL,), 'world2-hard'),
    Slot(14, (5, 4), 2, (2, 5), ('echoGate', 'goalOnly'), SEAL, False, '봉인과 전용 칸의 순서', (SEAL,), 'world2-hard'),
    Slot(13, (4, 4), 2, (1, 4), ('echoGate', 'echoEraser'), SEAL, False, '지우개를 피해 잔상 붙잡기', (SEAL,), 'world2-hard'),
    Slot(15, (5, 4), 2, (2, 5), ('echoGate', 'echoHold'), SEAL, True, '수호 정령: Hold 와 봉인의 이중 잠금', (SEAL,), 'world2-hard'),
    # 4장 바람의 회랑 — 바람
    Slot(10, (5, 4), 2, (2, 5), (), WIND, False, '바람으로 긴 복도를 한 번에', (WIND,), 'world2-hard'),
    Slot(13, (5, 5), 2, (3, 6), ('oneWay',), WIND, False, '화살표 칸에서 멈추는 바람', (WIND,), 'world2-hard'),
    Slot(14, (5, 5), 2, (4, 7), ('goalOnly',), WIND, False, '바람이 멈출 벽 만들기', (WIND,), 'world2-hard'),
    Slot(15, (5, 5), 2, (3, 6), ('oneWay', 'echoEraser'), WIND, False, '바람과 지우개의 통로', (WIND,), 'world2-hard'),
    Slot(16, (5, 5), 2, (4, 7), ('oneWay', 'echoGate'), WIND, True, '수호 정령: 바람만 닿는 문', (WIND,), 'world2-hard'),
    # 5장 등불의 꼭대기 — 두 권능 조합
    Slot(12, (5, 4), 2, (2, 5), ('echoGate', 'echoHold'), SEAL, False, '봉인과 도약, 무엇을 먼저 쓸까', (LEAP, SEAL), 'world2-master'),
    Slot(15, (5, 5), 2, (3, 6), ('oneWay',), WIND, False, '교대한 뒤 바람에 실어 보내기', (SWAP, WIND), 'world2-master'),
    Slot(16, (5, 5), 2, (4, 7), ('echoEraser', 'goalOnly'), SWAP, True, '교대 없이는 닫힌 꼭대기', (LEAP, SWAP), 'world2-master'),
    Slot(16, (5, 4), 2, (2, 5), ('echoHold', 'oneWay'), WIND, False, '두 권능을 아껴 쓰기', (SEAL, WIND), 'world2-master'),
    Slot(18, (5, 5), 2, (4, 7), ('echoGate', 'goalOnly'), LEAP, True, '수호 정령: 등불을 켜는 마지막 길', (LEAP, SWAP), 'world2-master'),
)
