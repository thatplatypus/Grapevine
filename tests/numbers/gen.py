# Writes the numbers that tests/numbers.sh checks: literals to read and reals to write, each with
# what Python makes of it. Python's conversions between text and reals are correctly rounded.
#   python3 tests/numbers/gen.py SEED FOLDER
import math, os, random, struct, sys
random.seed(int(sys.argv[1]))
folder = sys.argv[2]

def parts(x):
    if x == 0.0:
        return (0, 0)
    m, e = math.frexp(x)
    M = int(m * (1 << 53)); E = e - 53
    while M % 2 == 0:
        M //= 2; E += 1
    return (M, E)

def shortest(x):
    for n in (15, 16, 17):
        s = '%.*e' % (n - 1, x)
        if float(s) == x:
            return s
    return '%.16e' % x

def written(x):
    if x == 0:
        return '0.0'
    sign = '-' if x < 0 else ''
    mant, exp = shortest(abs(x)).split('e')
    digits = mant.replace('.', '').rstrip('0') or '0'
    e10 = int(exp)
    if -5 <= e10 < 15:
        if e10 >= 0:
            whole = digits[:e10 + 1].ljust(e10 + 1, '0')
            frac = digits[e10 + 1:] or '0'
            return sign + whole + '.' + frac
        return sign + '0.' + '0' * (-e10 - 1) + digits
    return sign + digits[0] + '.' + (digits[1:] or '0') + 'e' + str(e10)

def random_double():
    while True:
        bits = random.getrandbits(64)
        x = struct.unpack('<d', struct.pack('<Q', bits))[0]
        if x == x and x not in (float('inf'), float('-inf')) and x != 0:
            return x

lits = []
def add(kind, lit):
    x = float(lit)
    if x in (float('inf'), float('-inf')):
        return
    lits.append((kind, lit, x))

for _ in range(40000):
    n = random.randint(1, 15)
    d = str(random.randint(1, 9)) + ''.join(random.choice('0123456789') for _ in range(n - 1))
    p = random.randint(0, n)
    lit = (d[:p] or '0') + ('.' + d[p:] if p < n else '')
    if lit.startswith('0') and len(lit.split('.')[0]) > 1:
        lit = lit.lstrip('0') or '0'
        if lit.startswith('.'): lit = '0' + lit
    add('plain', lit)
for _ in range(40000):
    add('repr', repr(abs(random_double())))
for _ in range(30000):
    x = random.uniform(0, 1) * 10 ** random.randint(-20, 20)
    add('repr-mid', repr(x))
for _ in range(30000):
    n = random.randint(16, 19)
    d = str(random.randint(1, 9)) + ''.join(random.choice('0123456789') for _ in range(n - 1))
    e = random.randint(-40, 40)
    add('long-mantissa', d[0] + '.' + d[1:] + 'e' + str(e))
for _ in range(20000):
    n = random.randint(1, 15)
    d = str(random.randint(1, 9)) + ''.join(random.choice('0123456789') for _ in range(n - 1))
    e = random.randint(-330, 300)
    add('big-exponent', d + 'e' + str(e))
for _ in range(20000):
    k = random.randint(53, 62)
    v = (1 << k) + random.randint(0, (1 << k) - 1)
    add('big-integer', str(v))
for _ in range(10000):
    n = random.randint(20, 60)
    d = str(random.randint(1, 9)) + ''.join(random.choice('0123456789') for _ in range(n - 1))
    p = random.randint(1, n - 1)
    add('very-long', d[:p] + '.' + d[p:])
for _ in range(10000):
    # Halfway between two neighbours, written out exactly.
    k = random.randint(53, 60)
    v = ((1 << 52) + random.randint(0, (1 << 52) - 1)) * 2 + 1
    v <<= (k - 53)
    add('tie-integer', str(v))

with open(os.path.join(folder, 'reads.txt'), 'w') as f:
    for kind, lit, x in lits:
        M, E = parts(x)
        f.write('%s %s %d %d\n' % (kind, lit, M, E))

with open(os.path.join(folder, 'writes.txt'), 'w') as f:
    for i in range(100000):
        if i % 4 == 0:
            x = random_double()
        elif i % 4 == 1:
            x = random.uniform(-1, 1) * 10 ** random.randint(-30, 30)
        elif i % 4 == 2:
            x = round(random.uniform(0, 100000), random.randint(0, 6))
        else:
            x = float(random.randint(1, 10**15)) / 10 ** random.randint(0, 15)
        if x == 0: x = 1.0
        M, E = parts(abs(x))
        f.write('%s %d %d %s\n' % ('-' if x < 0 else '+', M, E, written(x)))
