"""Reference implementation of the Squish Sort rules and solver, used by the
level generator. The Swift SquishCore/SquishLevels modules are the shipping
implementation; CI re-solves every level in Swift and fails if par differs."""
import heapq
from dataclasses import dataclass

# A piece is a tuple (kind, hidden, frozen, bonded_above).


def rows(n):
    if n <= 6:
        return [list(range(n))]
    top = (n + 1) // 2
    return [list(range(top)), list(range(top, n))]


def neighbours_table(n):
    t = {j: [] for j in range(n)}
    for r in rows(n):
        for i, j in enumerate(r):
            if i > 0:
                t[j].append(r[i - 1])
            if i < len(r) - 1:
                t[j].append(r[i + 1])
    return t


@dataclass
class Board:
    cap: int
    jars: list  # list of tuples of pieces
    neigh: dict
    curtains: frozenset = frozenset()  # jars still behind a closed curtain

    def complete(self, j):
        jar = self.jars[j]
        return len(jar) == self.cap and all(p[0] == jar[0][0] for p in jar)

    def won(self):
        return all(len(self.jars[j]) == 0 or self.complete(j) for j in range(len(self.jars)))

    def run_length(self, j):
        jar = self.jars[j]
        if not jar or self.complete(j) or j in self.curtains:
            return 0
        top = jar[-1]
        if top[1] or top[2] > 0:
            return 0
        if len(jar) >= 2 and jar[-2][3]:
            # a duet on top moves as a pair, and only as a pair
            low = jar[-2]
            return 0 if (low[1] or low[2] > 0) else 2
        n = 1
        i = len(jar) - 2
        while i >= 0:
            p = jar[i]
            if p[0] != top[0] or p[1] or p[2] > 0:
                break
            n += 1
            i -= 1
        while n > 0 and splits(jar, n):
            n -= 1
        return n

    def to_move(self, f, t):
        if f == t:
            return 0
        n = self.run_length(f)
        if n == 0 or self.complete(t) or t in self.curtains:
            return 0
        dest = self.jars[t]
        room = self.cap - len(dest)
        if room <= 0:
            return 0
        src = self.jars[f]
        if len(src) >= 2 and src[-2][3]:
            # a duet needs two spaces, and lands in an empty jar or on its bottom member's kind
            if room < 2 or (dest and dest[-1][0] != src[-2][0]):
                return 0
            return 2
        if dest and dest[-1][0] != self.jars[f][-1][0]:
            return 0
        k = min(n, room)
        while k > 0 and splits(self.jars[f], k):
            k -= 1
        return k

    def apply(self, f, t):
        k = self.to_move(f, t)
        assert k > 0
        jars = list(self.jars)
        src = list(jars[f])
        moved = src[-k:]
        if k == 2 and moved[0][3] and jars[t]:
            # landing on its own kind, the duet lets go
            p = moved[0]
            moved = [(p[0], p[1], p[2], False), moved[1]]
        del src[-k:]
        if src and src[-1][1]:
            p = src[-1]
            src[-1] = (p[0], False, p[2], p[3])
        dst = list(jars[t]) + moved
        jars[f] = tuple(src)
        jars[t] = tuple(dst)
        # thaw neighbours of from/to (each frozen jar counted once per move)
        touched = set()
        for j in (f, t):
            for nb in self.neigh.get(j, []):
                touched.add(nb)
        for j in touched:
            if any(p[2] > 0 for p in jars[j]):
                jars[j] = tuple((p[0], p[1], max(0, p[2] - 1), p[3]) for p in jars[j])
        b = Board(self.cap, jars, self.neigh, self.curtains)
        if b.complete(t):
            jars[t] = tuple((p[0], False, 0, p[3]) for p in jars[t])
            # a finished jar raises the curtain on the jars next to it
            up = [nb for nb in self.neigh.get(t, []) if nb in self.curtains]
            if up:
                b.curtains = self.curtains - frozenset(up)
                for nb in up:
                    if jars[nb] and jars[nb][-1][1]:
                        p = jars[nb][-1]
                        jars[nb] = jars[nb][:-1] + ((p[0], False, p[2], p[3]),)
        return b

    def moves(self):
        out = []
        n = len(self.jars)
        for f in range(n):
            if self.run_length(f) == 0:
                continue
            for t in range(n):
                if self.to_move(f, t) > 0:
                    out.append((f, t))
        return out


def splits(jar, k):
    lowest = len(jar) - k
    return lowest > 0 and jar[lowest - 1][3]


def heuristic(b, kind_jars):
    runs = 0
    for jar in b.jars:
        prev = None
        for p in jar:
            if p[0] != prev:
                runs += 1
                prev = p[0]
    return runs - kind_jars


def key(b, canonical):
    parts = [tuple((p[0], p[1], p[2], p[3]) for p in jar) for jar in b.jars]
    if canonical and not b.curtains:
        parts = sorted(parts)
    # while a curtain is closed, which jar stands next to which matters
    return (tuple(sorted(b.curtains)), tuple(parts))


def solve(b, max_states=3_000_000, weight=1, max_nodes=None):
    """A* with the run-count heuristic (admissible: a move removes at most one run)."""
    canonical = not any(p[2] > 0 for jar in b.jars for p in jar)
    counts = {}
    for jar in b.jars:
        for p in jar:
            counts[p[0]] = counts.get(p[0], 0) + 1
    kind_jars = sum((c + b.cap - 1) // b.cap for c in counts.values())
    start = key(b, canonical)
    nodes = [(b, -1, None)]
    best = {start: 0}
    heap = [(weight * heuristic(b, kind_jars), 0, 0)]
    explored = 0
    while heap:
        fval, negg, idx = heapq.heappop(heap)
        g = -negg
        cur = nodes[idx][0]
        if best.get(key(cur, canonical), 1 << 30) < g:
            continue
        if cur.won():
            path = []
            while idx > 0:
                path.append(nodes[idx][2])
                idx = nodes[idx][1]
            return list(reversed(path)), explored
        explored += 1
        if explored > max_states or (max_nodes and len(nodes) > max_nodes):
            return None, explored
        for (f, t) in cur.moves():
            if canonical and not cur.curtains and len(cur.jars[t]) == 0 and cur.run_length(f) == len(cur.jars[f]):
                continue  # pouring a whole jar into an empty one changes nothing
            nb = cur.apply(f, t)
            k = key(nb, canonical)
            ng = g + 1
            if ng < best.get(k, 1 << 30):
                best[k] = ng
                nodes.append((nb, idx, (f, t)))
                heapq.heappush(heap, (ng + weight * heuristic(nb, kind_jars), -ng, len(nodes) - 1))
    return None, explored


def board_from_level(level):
    kinds = []
    for jar in level["jars"]:
        for name in jar:
            if name not in kinds:
                kinds.append(name)
    mech = level.get("mechanics") or {}
    hidden = {tuple(x[:2]) for x in mech.get("hidden", [])}
    frozen = {tuple(x[:2]): (x[2] if len(x) > 2 else 2) for x in mech.get("frozen", [])}
    sticky = {tuple(x[:2]) for x in mech.get("sticky", [])}
    jars = []
    for j, jar in enumerate(level["jars"]):
        pieces = []
        for i, name in enumerate(jar):
            pieces.append((kinds.index(name), (j, i) in hidden and i != len(jar) - 1,
                           frozen.get((j, i), 0), (j, i) in sticky))
        jars.append(tuple(pieces))
    n = len(jars)
    return Board(level["capacity"], jars, neighbours_table(n), frozenset(mech.get("curtains", []))), kinds
