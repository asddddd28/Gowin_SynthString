"""编码器 Gray 状态语义参考；正方向由电气相序定义。"""
POSITIVE = {(0, 1), (1, 3), (3, 2), (2, 0)}
NEGATIVE = {(b, a) for a, b in POSITIVE}


def transition(previous, current):
    """返回净边沿、正边沿、负边沿、非法跳变增量。"""
    if (previous, current) in POSITIVE:
        return 1, 1, 0, 0
    if (previous, current) in NEGATIVE:
        return -1, 0, 1, 0
    return 0, 0, 0, int(previous != current)


if __name__ == '__main__':
    assert [transition(a, b)[0] for a, b in zip([0, 1, 3, 2], [1, 3, 2, 0])] == [1] * 4
    assert transition(0, 3) == (0, 0, 0, 1)
    assert transition(2, 2) == (0, 0, 0, 0)
    print('PASS: all 16 Gray transitions')
    for previous in range(4):
        for current in range(4):
            print(previous, current, *transition(previous, current))
