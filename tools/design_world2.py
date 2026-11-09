"""기존 세계 2 명령을 공통 생성기에 연결한다."""
import sys

from tools.design_world import main


if __name__ == '__main__':
    main(['--world', '2', *sys.argv[1:]])
