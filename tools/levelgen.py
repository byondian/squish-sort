#!/usr/bin/env python3
"""Generates the Squish Sort 1.0 levels into Levels/<world>/<nn>.json.

Deterministic (fixed seeds), so re-running reproduces the same files. Levels 1-3
and 5 are hand-built from the game design doc; the rest are chosen from random
candidates by target par for their beat. CI re-solves every level in Swift.

Usage: python3 tools/levelgen.py [--only toyshop-07] [--world christmas]
"""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from squishlib import board_from_level, solve

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAP = 4

WORLDS = [
    ("toyshop", ["strawbie", "tango", "sunny", "minty", "blu", "grapey"], None),
    ("sweetfactory", ["macaron", "donut", "jelly", "cupcake", "gummy-bear", "lolly"], "hidden"),
    ("starlight", ["lumi", "riff", "zuzu", "pip", "nova", "coco"], "sticky"),
    ("christmas", ["santa", "elfie", "reindeer", "snowbo", "ginger", "waddles"], "frozen"),
]
# Worlds grow as the game goes on. The last level of a world is always a boss.
LENGTHS = {"toyshop": 15, "sweetfactory": 20, "starlight": 25, "christmas": 20}
BEATS = ["intro", "easy", "easy", "medium", "showpiece", "breather", "bonus", "tension", "calm", "boss"]

# (kinds, empty jars, target par as a multiple of kinds) for world positions 1..20.
SHAPE = {
    1: (2, 1, None), 2: (2, 1, None), 3: (3, 2, None), 4: (4, 2, 2.5), 5: (7, 2, None),
    6: (3, 2, 2.0), 7: (5, 2, 2.6), 8: (6, 2, 2.8), 9: (4, 2, 2.2), 10: (8, 2, 3.0),
    11: (4, 2, 2.4), 12: (5, 2, 2.4), 13: (5, 2, 2.5), 14: (6, 2, 2.8), 15: (8, 2, None),
    16: (4, 2, 2.2), 17: (6, 2, 3.0), 18: (7, 2, 3.2), 19: (5, 2, 2.3), 20: (8, 2, 3.4),
    21: (5, 2, 2.6), 22: (6, 2, 2.8), 23: (6, 2, 3.0), 24: (7, 2, 3.2), 25: (8, 2, 3.6),
}
# A world's last level when it is not on a tenth: a boss this size.
FINALE = (8, 2, 3.2)
# From this level of a world on, an earlier world's new thing mixes back in.
MIX = {"starlight": (13, "hidden")}
# Starlight Stage changes its twist half way: mixed duets up to level 12, Curtain Call jars from 13
# (Ian, 17 Nov). Curtain levels have no duets.
CURTAINS_FROM = {"starlight": 13}
# Later worlds start a little bigger at the same positions.
WORLD_BUMP = {0: 0, 1: 1, 2: 1, 3: 1}
# Santa's Grotto is a side world that opens after main level 10, so it is
# tuned like main levels 12 to 35: Toy Shop sizes for its first half.
SIDE_WORLD = 3


def squeeze(world, pos, beat):
    """Where the game gets properly hard (Ian, 16 Nov: three stars on everything by level 33).
    Returns (kinds to add, spare jars) or None to leave the level's shape alone.
    One spare jar instead of two is what makes dead ends real, so Undo and Restart matter."""
    tier = 1 if (world == "sweetfactory" and pos >= 14) else 2 if (world == "starlight" and pos >= 4) else 0
    if not tier:
        return None
    if beat == "boss":
        return (-1, 1)          # 7 kinds, one spare jar
    if beat == "tension":
        return (-1 if tier == 1 else 0, 1)
    if tier == 2 and beat in ("medium", "bonus"):
        return (0, 1)
    return (1, 2)               # the rests between get one more kind


def capsule_level(pos, last=20):
    """Every 3rd level of a world, plus its last level."""
    return pos % 3 == 0 or pos == last


# Commons borrowed for 7- and 8-kind levels, picked so no two pieces on a
# board share a colour.
BORROW = {
    "toyshop": ["macaron", "donut"],
    "sweetfactory": ["strawbie", "tango"],
    "starlight": ["strawbie", "tango"],
    "christmas": ["jelly", "cupcake"],
}


def kinds_for(world_idx, n):
    own = WORLDS[world_idx][1]
    if n <= len(own):
        return own[:n]
    return own + BORROW[WORLDS[world_idx][0]][: n - len(own)]


def mechanic_count(mech, pos):
    if mech == "hidden":
        return min(2 + pos // 2, 10)
    if mech == "sticky":
        # mixed duets: one a level at first, then up to two, up to three from level 15
        return 1 if pos <= 5 else (2 if pos < 15 else 3)
    if mech == "frozen":
        return min(1 + pos // 8, 3)
    if mech == "curtain":
        # one curtain at first, two from level 18
        return 1 if pos < 18 else 2
    return 0


def random_board(rng, names, empties, mech, mcount, mix_hidden=0):
    """Returns (jars, mechanics) or None."""
    units = []
    if mech == "sticky":
        # a duet is two different kinds placed as one 2-piece unit (bottom, top)
        pool = [n for n in names for _ in range(CAP)]
        for _ in range(mcount):
            a, b = rng.sample(names, 2)
            if a in pool and b in pool:
                pool.remove(a); pool.remove(b)
                units.append((a, b))
        units += [(p,) for p in pool]
    else:
        units = [(n,) for n in names for _ in range(CAP)]
    for _ in range(200):
        rng.shuffle(units)
        jars, sticky, cur = [], [], []
        ok = True
        for u in units:
            if len(cur) + len(u) > CAP:
                ok = False
                break
            if len(u) == 2:
                sticky.append([len(jars), len(cur)])
            cur.extend(u)
            if len(cur) == CAP:
                jars.append(cur)
                cur = []
        if not ok or cur:
            continue
        if any(len(set(j)) == 1 for j in jars):
            continue
        # avoid boards that open with 3-of-a-kind already stacked at the top
        if sum(1 for j in jars if j[-1] == j[-2] == j[-3]) > 0:
            continue
        mechanics = {}
        if sticky:
            mechanics["sticky"] = sticky
        if mech == "hidden":
            spots = [[j, i] for j in range(len(jars)) for i in range(CAP - 1)]
            mechanics["hidden"] = sorted(rng.sample(spots, min(mcount, len(spots))))
        if mech == "frozen":
            spots = [[j, i] for j in range(len(jars)) for i in range(CAP)]
            # not more than one frozen piece per jar, keeps it readable
            picks, used = [], set()
            for s in rng.sample(spots, len(spots)):
                if s[0] not in used:
                    picks.append(s); used.add(s[0])
                if len(picks) == mcount:
                    break
            mechanics["frozen"] = sorted(picks)
        closed = []
        if mech == "curtain":
            # a curtain hides a full jar; the spare jars are never behind one
            closed = sorted(rng.sample(range(len(jars)), min(mcount, len(jars))))
            mechanics["curtains"] = closed
        if mix_hidden:
            # wrapped pieces mixed into a duet world: never a duet piece, never the top of a jar,
            # never behind a curtain
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            spots = [[j, i] for j in range(len(jars)) for i in range(CAP - 1) if (j, i) not in taken and j not in closed]
            mechanics["hidden"] = sorted(rng.sample(spots, min(mix_hidden, len(spots))))
        jars = jars + [[] for _ in range(empties)]
        return jars, mechanics
    return None


def staircase(rng, names):
    """Fake-hard board: lots of kinds, but every move finishes a jar."""
    n = len(names)
    order = names[:]
    rng.shuffle(order)
    a = order
    jars = [[a[1], a[0], a[0], a[0]], [a[0]]]
    for i in range(1, n - 1):
        jars.append([a[i + 1], a[i], a[i], a[i]])
    jars.append([a[n - 1]] * 3)
    jars.append([])
    rng.shuffle(jars)
    return jars


def killing_first_moves(b):
    """How many opening moves leave the board with no way to win (Ian, level 42: one move in and
    the level was already lost). Levels are picked so that there are none."""
    dead = 0
    for (f, t) in b.moves():
        nb = b.apply(f, t)
        if nb.won():
            continue
        sol, _ = solve(nb, 40_000, weight=3)
        if sol is None:
            dead += 1
    return dead


def choose(rng, level, names, empties, mech, mcount, target, mix_hidden=0):
    """Best solvable random candidate: first one whose every opening move can still be won from,
    then by distance to target par (lowest par if no target)."""
    best = None
    for _ in range(int(os.environ.get("LEVELGEN_TRIES", "80"))):
        cand = random_board(rng, names, empties, mech, mcount, mix_hidden)
        if cand is None:
            continue
        jars_c, mech_c = cand
        b, _ = board_from_level(dict(level, jars=jars_c, mechanics=mech_c))
        sol, _ = solve(b, 600_000)
        if sol is None:
            continue
        score = abs(len(sol) - target) if target else len(sol)
        if best is not None and best[0][0] == 0 and score >= best[0][1]:
            continue
        rank = (killing_first_moves(b), score)
        if best is None or rank < best[0]:
            best = (rank, jars_c, mech_c)
        if target and best[0][0] == 0 and best[0][1] <= 1:
            break
        if not target and best[0][0] == 0 and _ >= 20:
            break
    if best is None:
        raise SystemExit(f"{level['id']}: no solvable candidate")
    if best[0][0] > 0:
        print(f"  {level['id']}: {best[0][0]} opening move(s) still lose the level", file=sys.stderr)
    return best[1], best[2]


def make_level(world_idx, pos):
    world, own, mech = WORLDS[world_idx]
    last = LENGTHS[world]
    finale = pos == last and pos % 10 != 0
    beat = "boss" if pos == last else BEATS[(pos - 1) % 10]
    base_k, empties, mult = FINALE if finale else SHAPE[pos]
    bump = WORLD_BUMP[world_idx] if pos > 3 else 0
    if world_idx == SIDE_WORLD and pos <= 10:
        bump = 0
    k = min(8, base_k + bump)
    showpiece = pos in (5, 15) and not finale
    if showpiece or finale:
        k = base_k
    hard = None if (showpiece or pos <= 3) else squeeze(world, pos, beat)
    if hard:
        k = max(4, min(8, k + hard[0]))
        empties = hard[1]
        if empties == 1:
            k = min(k, 7)
            mult = 9  # no target: the longest answer found wins
    names = kinds_for(world_idx, k)
    if pos >= CURTAINS_FROM.get(world, 99):
        mech = "curtain"
    rng = random.Random(f"{world}-{pos}")
    level = {
        "schema": 1, "id": f"{world}-{pos:02d}", "world": world, "index": pos,
        "beat": beat, "capacity": CAP,
    }
    mechanics = {}
    if world_idx == 0 and pos == 1:
        r, b = names
        jars = [[r, r, r], [b, b, b, r], [b]]
    elif world_idx == 0 and pos == 2:
        r, b = names
        jars = [[r, r, b, b], [b, b, r, r], []]
    elif world_idx == 0 and pos == 3:
        r, y, b = own[0], own[2], own[4]
        names = [r, y, b]
        jars = [[r, y, y, b], [y, b, b, r], [b, r, r, y], [], []]
    elif showpiece:
        jars = staircase(rng, names)
        if mech:
            # a light touch of the world's mechanic on the showpiece
            if mech == "hidden":
                # hide the bottom piece of two jars that hold 4
                full = [j for j, jar in enumerate(jars) if len(jar) == 4][:2]
                mechanics["hidden"] = [[j, 0] for j in full]
    else:
        mcount = mechanic_count(mech, pos)
        target = mult * k if mult else None
        if world_idx > 0 and pos <= 3 and mech:
            # intro levels of a mechanic world keep the mechanic gentle
            mcount = 1 if pos == 1 or (world_idx == SIDE_WORLD and pos == 2) else 2
        mix_from, mix_mech = MIX.get(world, (99, None))
        mix_hidden = min(2 + (pos - mix_from) // 2, 6) if pos >= mix_from and mix_mech == "hidden" else 0
        if pos == CURTAINS_FROM.get(world, 99):
            mix_hidden = 0  # the first curtain level shows the curtain alone
        # Duets need room: if no board can be solved, ask for fewer duets, then for one more spare jar.
        tries = [(mcount, empties)]
        if mech in ("sticky", "curtain"):
            tries += [(m, empties) for m in range(mcount - 1, 0, -1)] + [(1, empties + 1)]
        for n, (mc, em) in enumerate(tries):
            try:
                jars, mechanics = choose(rng, level, names, em, mech, mc, target, mix_hidden)
                break
            except SystemExit:
                if n == len(tries) - 1:
                    raise
    level["jars"] = jars
    level["mechanics"] = {"hidden": mechanics.get("hidden", []),
                          "sticky": mechanics.get("sticky", []),
                          "frozen": mechanics.get("frozen", [])}
    if mechanics.get("curtains"):
        level["mechanics"]["curtains"] = mechanics["curtains"]
    b, _ = board_from_level(level)
    sol, explored = solve(b, 3_000_000)
    if sol is None:
        raise SystemExit(f"{level['id']}: unsolvable or too big ({explored} states)")
    level["par"] = len(sol)
    level["solution"] = [list(m) for m in sol]
    level["capsule"] = capsule_level(pos, last)
    level["softenAfterFails"] = 3 if beat in ("tension", "boss") else None
    return level


def dump(level):
    """Stable, diff-friendly JSON: one jar per line."""
    lines = ["{"]
    keys = ["schema", "id", "world", "index", "beat", "capacity"]
    for k in keys:
        lines.append(f'  "{k}": {json.dumps(level[k])},')
    lines.append('  "jars": [')
    for i, jar in enumerate(level["jars"]):
        comma = "," if i < len(level["jars"]) - 1 else ""
        lines.append(f"    {json.dumps(jar)}{comma}")
    lines.append("  ],")
    m = level["mechanics"]
    extra = f', "curtains": {json.dumps(m["curtains"])}' if m.get("curtains") else ""
    lines.append(f'  "mechanics": {{"hidden": {json.dumps(m["hidden"])}, "sticky": {json.dumps(m["sticky"])}, "frozen": {json.dumps(m["frozen"])}{extra}}},')
    lines.append(f'  "par": {level["par"]},')
    lines.append(f'  "solution": {json.dumps(level["solution"])},')
    lines.append(f'  "capsule": {json.dumps(level["capsule"])},')
    lines.append(f'  "softenAfterFails": {json.dumps(level["softenAfterFails"])}')
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
    world = None
    if "--world" in sys.argv:
        world = sys.argv[sys.argv.index("--world") + 1]
    for w in range(len(WORLDS)):
        if world and WORLDS[w][0] != world:
            continue
        for pos in range(1, LENGTHS[WORLDS[w][0]] + 1):
            lid = f"{WORLDS[w][0]}-{pos:02d}"
            if only and only != lid:
                continue
            lv = make_level(w, pos)
            d = os.path.join(ROOT, "Levels", WORLDS[w][0])
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, f"{pos:02d}.json"), "w") as f:
                f.write(dump(lv))
            kinds = len({p for jar in lv["jars"] for p in jar})
            print(f"{lid:16} {lv['beat']:10} jars={len(lv['jars']):2} kinds={kinds} par={lv['par']:2} capsule={lv['capsule']}")


if __name__ == "__main__":
    main()
