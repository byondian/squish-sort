#!/usr/bin/env python3
"""Generates the Squish Sort 1.0 levels into Levels/<world>/<nn>.json.

Deterministic (fixed seeds), so re-running reproduces the same files. Levels 1-3
and 5 are hand-built from the game design doc; the rest are chosen from random
candidates by target par for their beat. CI re-solves every level in Swift.

Usage: python3 tools/levelgen.py [--only toyshop-07] [--world christmas] [--world endless 1 240]
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
    # Added after the others so the indexes above stay put. On the path they follow Starlight Stage.
    ("bubblebath", ["quacky", "soapy", "bubbly", "starla", "shelly", "fizzy"], "frozen"),   # bubbles: the frozen rule
    ("junglejam", ["bongo", "tuki", "pina", "leafy", "dotty", "nana"], None),               # vine jars
]
# Worlds grow as the game goes on. The last level of a world is always a boss.
LENGTHS = {"toyshop": 15, "sweetfactory": 20, "starlight": 25, "christmas": 20, "bubblebath": 30, "junglejam": 35}
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
WORLD_BUMP = {0: 0, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1}
# Santa's Grotto is a side world that opens after main level 10, so it is
# tuned like main levels 12 to 35: Toy Shop sizes for its first half.
SIDE_WORLD = 3


def squeeze(world, pos, beat):
    """Where the game gets properly hard (Ian, 16 Nov: three stars on everything by level 33).
    Returns (kinds to add, spare jars) or None to leave the level's shape alone.
    One spare jar instead of two is what makes dead ends real, so Undo and Restart matter."""
    late = world in ("starlight", "bubblebath", "junglejam")
    tier = 1 if (world == "sweetfactory" and pos >= 14) else 2 if (late and pos >= 4) else 0
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
    "bubblebath": ["minty", "strawbie"],
    "junglejam": ["blu", "grapey"],
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


def random_board(rng, names, empties, mech, mcount, mix_hidden=0, mix_frozen=0, vines=None):
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
        if vines:
            # a vine ties a jar of mixed squishies shut until `tag` jars are finished; never a jar with a duet
            free = [j for j in range(len(jars)) if not any(sj == j for sj, _ in sticky)]
            if len(free) < len(vines):
                continue
            picked = sorted(rng.sample(free, len(vines)))
            mechanics["vines"] = [[j, tag] for j, tag in zip(picked, vines)]
            closed = closed + picked
        if mix_hidden:
            # wrapped pieces mixed into a duet world: never a duet piece, never the top of a jar,
            # never behind a curtain
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            spots = [[j, i] for j in range(len(jars)) for i in range(CAP - 1) if (j, i) not in taken and j not in closed]
            mechanics["hidden"] = sorted(rng.sample(spots, min(mix_hidden, len(spots))))
        if mix_frozen:
            # frozen pieces mixed in (Keep Squishing): one a jar at most, never a duet piece,
            # never wrapped as well, never behind a curtain
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            taken |= {(j, i) for j, i in mechanics.get("hidden", [])}
            spots = [[j, i] for j in range(len(jars)) for i in range(CAP) if (j, i) not in taken and j not in closed]
            picks, used = [], set()
            for sp in rng.sample(spots, len(spots)):
                if sp[0] not in used:
                    picks.append(sp); used.add(sp[0])
                if len(picks) == mix_frozen:
                    break
            mechanics["frozen"] = sorted(picks)
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


def choose(rng, level, names, empties, mech, mcount, target, mix_hidden=0, mix_frozen=0, tries=None, states=600_000, vines=None):
    """Best solvable random candidate: first one whose every opening move can still be won from,
    then by distance to target par (lowest par if no target)."""
    best = None
    for _ in range(tries or int(os.environ.get("LEVELGEN_TRIES", "80"))):
        cand = random_board(rng, names, empties, mech, mcount, mix_hidden, mix_frozen, vines)
        if cand is None:
            continue
        jars_c, mech_c = cand
        b, _ = board_from_level(dict(level, jars=jars_c, mechanics=mech_c))
        if tries:
            # Keep Squishing: a quick, greedy look first throws out the boards that would be slow to settle.
            quick, _ = solve(b, 6_000, weight=3)
            if quick is None:
                continue
        sol, _ = solve(b, states)
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


def late_rules(world, pos):
    """Bubble Bath and Jungle Jam: (main rule, wrapped mixed in, bubbles mixed in, vine tags)."""
    if world == "bubblebath":
        # bubbles alone at first; duets and wrapped squishies mix in from level 16
        if pos < 16:
            return "frozen", 0, 0, None
        return ("sticky", 0, 2, None) if pos % 2 == 0 else ("frozen", 3, 0, None)
    # Jungle Jam: one vine with a 1 on its tag, then a 2, then two vines; everything earlier mixes in from 18
    tags = [1] if pos < 8 else [2] if pos < 14 else [1, 2] if pos < 26 else [2, 2]
    if pos < 18:
        return None, 0, 0, tags
    return [(None, 4, 0, tags), ("sticky", 0, 0, tags), (None, 0, 2, tags)][pos % 3]


def make_level(world_idx, pos, salt=0):
    world, own, mech = WORLDS[world_idx]
    last = LENGTHS[world]
    finale = pos == last and pos % 10 != 0
    beat = "boss" if pos == last else BEATS[(pos - 1) % 10]
    # past level 25 a world keeps cycling its last ten sizes
    base_k, empties, mult = FINALE if finale else SHAPE[pos if pos <= 25 else 16 + (pos - 16) % 10]
    if world == "junglejam" and pos <= 3:
        # a vine needs a jar that can be finished without it: three kinds from the first level
        base_k, empties = (3, 2) if pos == 1 else (4, 2)
    bump = WORLD_BUMP[world_idx] if pos > 3 else 0
    if world_idx == SIDE_WORLD and pos <= 10:
        bump = 0
    k = min(8, base_k + bump)
    showpiece = pos in (5, 15) and not finale
    late = world in ("bubblebath", "junglejam")
    late_hidden = late_frozen = 0
    vines = None
    if late:
        mech, late_hidden, late_frozen, vines = late_rules(world, pos)
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
    rng = random.Random(f"{world}-{pos}" if salt == 0 else f"{world}-{pos}-{salt}")
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
        mix_hidden = mix_hidden or late_hidden
        if late and mech == "sticky":
            mcount = 2
        if pos == CURTAINS_FROM.get(world, 99):
            mix_hidden = 0  # the first curtain level shows the curtain alone
        # Duets need room: if no board can be solved, ask for fewer duets, then for one more spare jar.
        tries = [(mcount, empties)]
        if mech in ("sticky", "curtain"):
            tries += [(m, empties) for m in range(mcount - 1, 0, -1)] + [(1, empties + 1)]
        elif late:
            tries += [(mcount, empties + 1)]
        # the two late worlds mix rules, so their boards get the quicker Keep Squishing search
        quick = dict(tries=60, states=40_000) if late else {}
        for n, (mc, em) in enumerate(tries):
            try:
                jars, mechanics = choose(rng, level, names, em, mech, mc, target, mix_hidden, late_frozen, vines=vines, **quick)
                if late:
                    # no level ships with an opening move that loses it: one more spare jar instead
                    b0, _ = board_from_level(dict(level, jars=jars, mechanics=mechanics))
                    if killing_first_moves(b0) > 0 and n < len(tries) - 1:
                        continue
                break
            except SystemExit:
                if n == len(tries) - 1:
                    raise
        if mech == "curtain":
            # A curtain and a single spare jar leave openings that lose on the spot. Rather than
            # ship one, the level gets a second spare jar.
            b0, _ = board_from_level(dict(level, jars=jars, mechanics=mechanics))
            if killing_first_moves(b0) > 0:
                jars2, mech2 = choose(rng, level, names, em + 1, mech, mc, target, mix_hidden)
                b2, _ = board_from_level(dict(level, jars=jars2, mechanics=mech2))
                if killing_first_moves(b2) == 0:
                    jars, mechanics = jars2, mech2
    level["jars"] = jars
    level["mechanics"] = {"hidden": mechanics.get("hidden", []),
                          "sticky": mechanics.get("sticky", []),
                          "frozen": mechanics.get("frozen", [])}
    if mechanics.get("curtains"):
        level["mechanics"]["curtains"] = mechanics["curtains"]
    if mechanics.get("vines"):
        level["mechanics"]["vines"] = mechanics["vines"]
    if late and showpiece and vines:
        # the showpiece keeps its staircase, with one vine on a jar that is not the first to finish
        level["mechanics"]["vines"] = [[max(range(len(jars)), key=lambda j: (len(jars[j]) == 4, j)), 1]]
    b, _ = board_from_level(level)
    sol, explored = solve(b, 3_000_000)
    if sol is None and level["mechanics"].get("vines") and showpiece:
        del level["mechanics"]["vines"]
        b, _ = board_from_level(level)
        sol, explored = solve(b, 3_000_000)
    if sol is None:
        raise SystemExit(f"{level['id']}: unsolvable or too big ({explored} states)")
    level["par"] = len(sol)
    level["solution"] = [list(m) for m in sol]
    level["capsule"] = capsule_level(pos, last)
    level["softenAfterFails"] = 2 if beat in ("tension", "boss") else None
    return level


# Keep Squishing: the path carries on after Starlight Stage. Blocks of ten rotate through the
# worlds and mix their new things; sizes are the late-world ones.
ENDLESS = "endless"
ENDLESS_LENGTH = 240
# (world whose squishies appear, the block's main rule). Must match LevelCatalog.endlessLooks.
ENDLESS_SKINS = [(1, "hidden"), (2, "sticky"), (0, "frozen"), (2, "curtain")]


def endless_mix(block, mech):
    """Rules mixed into a block (benchmark pass 2): two rules from level 81 on, three from 141 on.
    Returns (wrapped pieces, frozen pieces) added on top of the block's main rule."""
    hidden = 3 if mech in ("sticky", "curtain") else 0   # as in Starlight Stage
    frozen = 0
    if block >= 2:
        if mech == "hidden":
            frozen = 2
        if mech == "frozen":
            hidden = 3
    if block >= 8:
        frozen = max(frozen, 2) if mech != "frozen" else 0
        hidden = max(hidden, 4) if mech != "hidden" else 0
    return hidden, frozen


def endless_capsule(pos):
    """A capsule every fifth level."""
    return pos % 5 == 0


def make_endless(pos):
    # A position whose first deal cannot be made fair is dealt again with a new seed.
    for salt in range(12):
        try:
            return make_endless_once(pos, salt)
        except SystemExit as e:
            last = e
    raise last


def make_endless_once(pos, salt):
    block, p = (pos - 1) // 10, (pos - 1) % 10 + 1
    world_idx, mech = ENDLESS_SKINS[block % len(ENDLESS_SKINS)]
    mix_hidden, mix_frozen = endless_mix(block, mech)
    beat = BEATS[p - 1]
    k, empties, mult = SHAPE[15 + p]
    if beat in ("tension", "boss", "medium", "bonus"):
        empties, k, mult = 1, min(k, 7), None
    names = kinds_for(world_idx, k)
    rng = random.Random(f"{ENDLESS}-{pos}" if salt == 0 else f"{ENDLESS}-{pos}-{salt}")
    level = {"schema": 1, "id": f"{ENDLESS}-{pos:02d}", "world": ENDLESS, "index": pos, "beat": beat, "capacity": CAP}
    mcount = {"hidden": 5 + p // 2, "sticky": 2 if p < 6 else 3, "frozen": 2 if p < 6 else 3,
              "curtain": 1 if p < 6 else 2}[mech]
    target = mult * k if mult else None
    tries = [(mcount, empties)]
    if mech in ("sticky", "curtain"):
        tries += [(m, empties) for m in range(mcount - 1, 0, -1)]
    tries += [(mcount, 2), (1, 2)]
    jars = None
    for mc, em in tries:
        try:
            # Boards the search can settle quickly: mixed rules make the others slow to check, here and on a phone.
            jars_c, mech_c = choose(rng, level, names, em, mech, mc, target, mix_hidden, mix_frozen, tries=60, states=40_000)
        except SystemExit:
            continue
        b0, _ = board_from_level(dict(level, jars=jars_c, mechanics=mech_c))
        if jars is None:
            jars, mechanics = jars_c, mech_c
        # No level ships with an opening move that loses it.
        if killing_first_moves(b0) == 0:
            jars, mechanics = jars_c, mech_c
            break
    else:
        if jars is None:
            raise SystemExit(f"{level['id']}: no solvable candidate")
        b0, _ = board_from_level(dict(level, jars=jars, mechanics=mechanics))
        if killing_first_moves(b0) > 0:
            raise SystemExit(f"{level['id']}: every candidate has a losing first move")
    level["jars"] = jars
    level["mechanics"] = {"hidden": mechanics.get("hidden", []), "sticky": mechanics.get("sticky", []),
                          "frozen": mechanics.get("frozen", [])}
    if mechanics.get("curtains"):
        level["mechanics"]["curtains"] = mechanics["curtains"]
    b, _ = board_from_level(level)
    sol, explored = solve(b, 3_000_000)
    if sol is None:
        raise SystemExit(f"{level['id']}: unsolvable or too big ({explored} states)")
    level["par"] = len(sol)
    level["solution"] = [list(m) for m in sol]
    level["capsule"] = endless_capsule(pos)
    level["softenAfterFails"] = 2 if beat in ("tension", "boss") else None
    return level


def write_endless(first, last):
    d = os.path.join(ROOT, "Levels", ENDLESS)
    os.makedirs(d, exist_ok=True)
    for pos in range(first, last + 1):
        lv = make_endless(pos)
        with open(os.path.join(d, f"{pos:03d}.json"), "w") as f:
            f.write(dump(lv))
        kinds = len({q for jar in lv["jars"] for q in jar})
        print(f"{lv['id']:16} {lv['beat']:10} jars={len(lv['jars']):2} kinds={kinds} par={lv['par']:2} capsule={lv['capsule']}", flush=True)


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
    if m.get("vines"):
        extra += f', "vines": {json.dumps(m["vines"])}'
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
    if world == ENDLESS:
        # python3 tools/levelgen.py --world endless [first last]
        i = sys.argv.index("--world") + 2
        nums = [int(x) for x in sys.argv[i:i + 2]]
        write_endless(nums[0] if nums else 1, nums[1] if len(nums) > 1 else ENDLESS_LENGTH)
        return
    # python3 tools/levelgen.py --world junglejam [first last]
    span = []
    if world:
        i = sys.argv.index("--world") + 2
        span = [int(x) for x in sys.argv[i:i + 2] if x.isdigit()]
    for w in range(len(WORLDS)):
        if world and WORLDS[w][0] != world:
            continue
        for pos in range(span[0] if span else 1, (span[1] if len(span) > 1 else LENGTHS[WORLDS[w][0]]) + 1):
            lid = f"{WORLDS[w][0]}-{pos:02d}"
            if only and only != lid:
                continue
            lv = make_level(w, pos)
            if WORLDS[w][0] in ("bubblebath", "junglejam"):
                # A level whose first deal has an opening move that loses it is dealt again with a new seed.
                for salt in range(1, 9):
                    b0, _ = board_from_level(lv)
                    if killing_first_moves(b0) == 0:
                        break
                    try:
                        lv = make_level(w, pos, salt)
                    except SystemExit:
                        continue
                b0, _ = board_from_level(lv)
                if killing_first_moves(b0) > 0:
                    raise SystemExit(f"{lid}: every deal has a losing first move")
            d = os.path.join(ROOT, "Levels", WORLDS[w][0])
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, f"{pos:02d}.json"), "w") as f:
                f.write(dump(lv))
            kinds = len({p for jar in lv["jars"] for p in jar})
            print(f"{lid:16} {lv['beat']:10} jars={len(lv['jars']):2} kinds={kinds} par={lv['par']:2} capsule={lv['capsule']}")


if __name__ == "__main__":
    main()
