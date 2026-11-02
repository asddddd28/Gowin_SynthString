"""Check ordered route accumulation with descriptor/operand/product pipeline."""
import random

def signed(value, width):
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value

def clamp(value):
    return min(2147483647, max(-2147483648, value))

def check():
    rng = random.Random(20261102)
    for trial in range(10000):
        routes = [(rng.randrange(15), rng.randrange(-2**31, 2**31),
                   rng.randrange(-2**31, 2**31), rng.choice([False, True]))
                  for _ in range(8)]
        if trial % 2 == 0:
            routes = [(0, value, depth, enabled) for _, value, depth, enabled in routes]
        expected = [0] * 15
        for target, value, depth, enabled in routes:
            contribution = signed((value * depth) >> 26, 36) if enabled else 0
            expected[target] = signed(expected[target] + contribution, 36)
        actual = [0] * 15
        descriptor = operand = product = None
        for cycle in range(11):
            if product is not None:
                target, contribution = product
                actual[target] = signed(actual[target] + contribution, 36)
            product = None if operand is None else (operand[0], signed((operand[1] * operand[2]) >> 26, 36))
            operand = None if descriptor is None else (descriptor[0], descriptor[1] if descriptor[3] else 0, descriptor[2])
            descriptor = routes[cycle] if cycle < 8 else None
        assert list(map(clamp, actual)) == list(map(clamp, expected))
        assert descriptor is None and operand is None and product is None
    print('PASS route_pipeline cases=10000 same_target=5000 signed36_and_clamp=exact')

if __name__ == '__main__':
    check()
