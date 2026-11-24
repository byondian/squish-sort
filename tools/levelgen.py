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
    ("bubblebath", ["quacky", "soapy", "bubbly", "starla", "shelly", "fizzy"], None),       # floaters and golden ride bubbles
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
    """Every 3rd level of a world, every boss (each 10th level), plus its last level."""
    return pos % 3 == 0 or pos % 10 == 0 or pos == last


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


def random_board(rng, names, empties, mech, mcount, mix_hidden=0, mix_frozen=0, vines=None, bubbles=None,
                 keys=0, morphs=0, cap=None):
    """Returns (jars, mechanics) or None. `bubbles` is (floaters, golden ride bubbles) for Bubble Bath.
    `keys` key jars, `morphs` morph pieces and jars of `cap` are the Keep Squishing twists."""
    cap = cap or CAP
    units = []
    if mech == "sticky":
        # a duet is two different kinds placed as one 2-piece unit (bottom, top)
        pool = [n for n in names for _ in range(cap)]
        for _ in range(mcount):
            a, b = rng.sample(names, 2)
            if a in pool and b in pool:
                pool.remove(a); pool.remove(b)
                units.append((a, b))
        units += [(p,) for p in pool]
    else:
        units = [(n,) for n in names for _ in range(cap)]
    for _ in range(200):
        rng.shuffle(units)
        jars, sticky, cur = [], [], []
        ok = True
        for u in units:
            if len(cur) + len(u) > cap:
                ok = False
                break
            if len(u) == 2:
                sticky.append([len(jars), len(cur)])
            cur.extend(u)
            if len(cur) == cap:
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
            spots = [[j, i] for j in range(len(jars)) for i in range(cap - 1)]
            mechanics["hidden"] = sorted(rng.sample(spots, min(mcount, len(spots))))
        if mech == "frozen":
            spots = [[j, i] for j in range(len(jars)) for i in range(cap)]
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
        if keys:
            # a padlock shuts a jar of mixed squishies until a jar of its key kind is finished: never a
            # jar with a duet, and never a jar that holds the key kind itself
            free = [j for j in range(len(jars)) if j not in closed and not any(sj == j for sj, _ in sticky)]
            if len(free) < keys:
                continue
            picked = sorted(rng.sample(free, keys))
            mechanics["keys"] = [{"jar": j, "kind": rng.choice([n for n in names if n not in jars[j]])} for j in picked]
            closed = closed + picked
        if mix_hidden:
            # wrapped pieces mixed into a duet world: never a duet piece, never the top of a jar,
            # never behind a curtain
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            spots = [[j, i] for j in range(len(jars)) for i in range(cap - 1) if (j, i) not in taken and j not in closed]
            mechanics["hidden"] = sorted(rng.sample(spots, min(mix_hidden, len(spots))))
        if mix_frozen:
            # frozen pieces mixed in (Keep Squishing): one a jar at most, never a duet piece,
            # never wrapped as well, never behind a curtain
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            taken |= {(j, i) for j, i in mechanics.get("hidden", [])}
            spots = [[j, i] for j in range(len(jars)) for i in range(cap) if (j, i) not in taken and j not in closed]
            picks, used = [], set()
            for sp in rng.sample(spots, len(spots)):
                if sp[0] not in used:
                    picks.append(sp); used.add(sp[0])
                if len(picks) == mix_frozen:
                    break
            mechanics["frozen"] = sorted(picks)
        if morphs:
            # A morph piece is a plain piece in an open jar. Two of them swap the same two kinds, so the
            # board comes out whether both flip an even or an odd number of times.
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            taken |= {(j, i) for j, i in mechanics.get("hidden", [])} | {(j, i) for j, i, *_ in mechanics.get("frozen", [])}
            spots = [(j, i) for j in range(len(jars)) for i in range(cap) if (j, i) not in taken and j not in closed]
            rng.shuffle(spots)
            first = spots[0]
            a = jars[first[0]][first[1]]
            if morphs == 1:
                mechanics["morph"] = [{"jar": first[0], "at": first[1], "kind": rng.choice([n for n in names if n != a])}]
            else:
                second = next((sp for sp in spots[1:] if jars[sp[0]][sp[1]] != a and sp[0] != first[0]), None)
                if second is None:
                    continue
                b = jars[second[0]][second[1]]
                mechanics["morph"] = sorted([{"jar": first[0], "at": first[1], "kind": b},
                                             {"jar": second[0], "at": second[1], "kind": a}], key=lambda m: (m["jar"], m["at"]))
        if bubbles:
            # A bubble goes on the top squishy of a jar, one a jar, never on a duet, never on a squishy
            # that already sits on its own kind (it would pop at once). The squishy under it is not wrapped.
            taken = {(j, i) for j, i in sticky} | {(j, i + 1) for j, i in sticky}
            tops = [j for j in range(len(jars)) if jars[j][-1] != jars[j][-2] and (j, cap - 1) not in taken and j not in closed]
            if len(tops) < sum(bubbles):
                continue
            picked = rng.sample(tops, sum(bubbles))
            mechanics["frozen"] = sorted([j, cap - 1, 1] for j in picked[:bubbles[0]]) + sorted([j, cap - 1, 2] for j in picked[bubbles[0]:])
            if "hidden" in mechanics:
                mechanics["hidden"] = [h for h in mechanics["hidden"] if not (h[0] in picked and h[1] >= cap - 2)]
        jars = jars + [[] for _ in range(empties)]
        return jars, mechanics
    return None


def playout_wins(b, rng, games=40, limit=160):
    """How often a player who moves at random (never straight back, never a whole jar into an empty one)
    wins the board. A rough but honest measure of how much a board punishes careless moves."""
    wins = 0
    for _ in range(games):
        cur, last = b, None
        for _ in range(limit):
            if cur.won():
                wins += 1
                break
            ms = [m for m in cur.moves() if not (last and m[1] >= 0 and (m[1], m[0]) == last)
                  and not (m[1] >= 0 and len(cur.jars[m[1]]) == 0 and cur.run_length(m[0]) == len(cur.jars[m[0]]))]
            if not ms:
                break
            last = rng.choice(ms)
            cur = cur.apply(*last)
    return wins / games


# Bubble Bath: how often a careless player should win a level of each beat.
BUBBLE_EASE = {"intro": 0.9, "easy": 0.8, "medium": 0.5, "showpiece": 1.0, "breather": 0.7, "bonus": 0.4,
               "tension": 0.2, "calm": 0.6, "boss": 0.12}


def bubble_plan(pos, beat):
    """Bubble Bath: (kinds, floaters, golden ride bubbles) for a level. Two spare jars throughout:
    the floaters are what make it tight. The first three levels teach the floater, level 4 the ride."""
    if pos <= 4:
        return [(2, 1, 0), (3, 1, 0), (3, 2, 0), (4, 2, 1)][pos - 1]
    tier = (pos - 1) // 10
    kinds = {"intro": 5, "easy": 5, "medium": 6, "showpiece": 6, "breather": 5, "bonus": 6, "tension": 7, "calm": 5, "boss": 7}[beat] + (1 if tier >= 1 and beat not in ("tension", "boss") else 0)
    floaters = {"intro": 2, "easy": 3, "medium": 3, "showpiece": 3, "breather": 2, "bonus": 3, "tension": 4, "calm": 2, "boss": 3}[beat] + (1 if tier == 2 else 0)
    rides = {"intro": 0, "easy": 0, "medium": 1, "showpiece": 1, "breather": 1, "bonus": 1, "tension": 0, "calm": 1, "boss": 1}[beat]
    if pos == 30:
        rides = 2
    return min(kinds, 8), floaters, rides


def choose_bubbles(rng, level, names, mech, mcount, mix_hidden, bubbles, ease):
    """Bubble Bath: the solvable deal with no losing first move whose careless-win rate is nearest `ease`."""
    best = None
    for _ in range(int(os.environ.get("LEVELGEN_TRIES", "60"))):
        cand = random_board(rng, names, 2, mech, mcount, mix_hidden, 0, None, bubbles)
        if cand is None:
            continue
        jars_c, mech_c = cand
        b, _ = board_from_level(dict(level, jars=jars_c, mechanics=mech_c))
        if sum(1 for jar in b.jars for p in jar if p[2] > 0) != sum(bubbles):
            continue
        sol, _ = solve(b, 40_000)
        if sol is None:
            continue
        if bubbles[1] and not any(m[1] < 0 for m in sol) and rng.random() < 0.7:
            continue  # prefer deals where the best answer takes the ride
        if killing_first_moves(b) > 0:
            continue
        rank = abs(playout_wins(b, rng) - ease)
        if best is None or rank < best[0]:
            best = (rank, jars_c, mech_c)
        if rank <= 0.05:
            break
    if best is None:
        raise SystemExit(f"{level['id']}: no solvable candidate")
    return best[1], best[2]


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
        # floaters alone at first; duets and wrapped squishies mix in from level 16
        if pos < 16:
            return None, 0, 0, None
        return ("sticky", 0, 0, None) if pos % 2 == 0 else (None, 3, 0, None)
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
    hard = None if (showpiece or pos <= 3 or world == "bubblebath") else squeeze(world, pos, beat)
    bubbles = None
    if world == "bubblebath" and not showpiece:
        k, nf, nr = bubble_plan(pos, beat)
        bubbles, empties = (nf, nr), 2
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
    elif bubbles:
        # a level 25 that is not a staircase is an ordinary medium level
        ease = 0.5 if beat == "showpiece" else BUBBLE_EASE[beat]
        jars, mechanics = choose_bubbles(rng, level, names, mech, 2 if mech == "sticky" else 0, late_hidden, bubbles, ease)
    elif showpiece:
        jars = staircase(rng, names)
        if world == "bubblebath":
            # The showpiece is a chain of golden bubbles: each one rides onto three of its own kind and
            # finishes a jar, which frees the next. The last squishy hops home the ordinary way.
            order = names[:]
            rng.shuffle(order)
            jars = [[order[0]] * 3] + [[order[i]] * 3 + [order[i - 1]] for i in range(1, len(order))] + [[order[-1]]]
            marks = list(range(len(jars)))
            rng.shuffle(marks)
            jars = [jars[m] for m in marks] + [[]]
            mechanics = {"frozen": sorted([j, CAP - 1, 2] for j, jar in enumerate(jars) if len(jar) == CAP)}
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
# Keep Squishing (refresh, 23 Nov 2026: Ian found it boring and repetitive). Blocks of ten rotate
# through six skins: the five story worlds, each with its own rule, and a Grand Mix. Every block has
# a main rule and, from the second time round, a guest rule from another world.
# (world whose squishies and room the block borrows, main rule, guest rule). The first entry of each
# row must match LevelCatalog.endlessLooks.
# Blocks 2, 3 and 4 bring in the three Keep Squishing twists (key jars, morph pieces, jars of 5), each on
# its own; later rounds mix them with the worlds' rules.
ENDLESS_BLOCKS = [
    # first time round
    (0, "ice", None), (1, "keys", None), (2, "morph", None), (4, "big", "wrapped"), (5, "vines", None), (2, "duets", "ice"),
    # second
    (0, "ice", "duets"), (1, "wrapped", "keys"), (2, "curtains", None), (4, "floaters", "duets"), (5, "morph", "vines"), (4, "floaters", "vines"),
    # third
    (0, "ice", "vines"), (1, "wrapped", "duets"), (2, "duets", "floaters"), (4, "big", "floaters"), (5, "keys", "duets"), (5, "vines", "wrapped"),
    # fourth
    (0, "ice", "curtains"), (1, "morph", "wrapped"), (2, "curtains", "ice"), (4, "floaters", "wrapped"), (5, "big", "vines"), (0, "duets", "floaters"),
]
# Kinds for each place in a block. Places 5 and 10 are the Expert boards.
ENDLESS_KINDS = [5, 5, 6, 6, 8, 6, 7, 7, 6, 8]
# How often a careless player should win each place, first time round. It drops a little every round.
ENDLESS_EASE = [0.7, 0.6, 0.5, 0.4, 0.1, 0.5, 0.35, 0.25, 0.45, 0.06]


def endless_rule(rule, p, lap, guest):
    """What one rule adds to a board at place p (1 to 10) of a block. A guest rule comes in lighter."""
    late = p > 5
    if rule == "ice":
        return dict(mix_frozen=2 if guest else 2 + late + (lap >= 2))
    if rule == "wrapped":
        return dict(mix_hidden=3 if guest else 5 + p // 2)
    if rule == "duets":
        return dict(mech="sticky", mcount=1 if guest else 2 + (late and lap >= 1))
    if rule == "curtains":
        return dict(mech="curtain", mcount=1 if (guest or not late) else 2)
    if rule == "vines":
        return dict(vines=[1] if guest and not late else [2] if guest or p < 4 else [1, 2] if p < 8 else [2, 2])
    if rule == "floaters":
        return dict(bubbles=(2, 1 if late else 0) if guest else (2 + late + (p in (5, 8, 10)), 0 if p in (1, 2, 8) else 1))
    if rule == "keys":
        # one padlock already halves how often a careless player wins; two only late in the block
        return dict(keys=1 if guest or p < 9 else 2)
    if rule == "morph":
        return dict(morphs=1 if guest or p < 3 else 2)
    if rule == "big":
        return dict(cap=5)
    raise ValueError(rule)


def endless_plan(pos):
    block, p = (pos - 1) // 10, (pos - 1) % 10 + 1
    lap = block // 6
    world_idx, main, guest = ENDLESS_BLOCKS[block % len(ENDLESS_BLOCKS)]
    plan = dict(mech=None, mcount=0, mix_hidden=0, mix_frozen=0, vines=None, bubbles=None, keys=0, morphs=0, cap=CAP)
    plan.update(endless_rule(main, p, lap, False))
    # the guest joins from the third level of its block, so the block opens on its main rule alone
    if guest and p >= 3:
        plan.update(endless_rule(guest, p, lap, True))
    expert = p in (5, 10)
    k = min(8, ENDLESS_KINDS[p - 1] + (1 if lap >= 2 and not expert else 0))
    # one spare jar is what makes an Expert board bite; floaters already seal jars, so those keep two
    empties = 1 if (expert or (p == 8 and lap >= 1)) and not plan["bubbles"] else 2
    if empties == 1:
        k = min(k, 7)
    if plan["cap"] > CAP:
        k = min(k - 1, 6)  # jars of 5 make a board longer, so it gets fewer kinds
    ease = max(0.04, ENDLESS_EASE[p - 1] - 0.05 * lap)
    return world_idx, k, empties, ease, plan


def lighter(plan):
    """The same rules with less of each, for a place where no fair board could be dealt."""
    out = dict(plan)
    out["mcount"] = max(1, plan["mcount"] - 1) if plan["mech"] else 0
    out["mix_hidden"] = max(0, plan["mix_hidden"] - 2)
    out["mix_frozen"] = min(plan["mix_frozen"], 2)
    if plan["vines"]:
        out["vines"] = plan["vines"][:1]
    if plan["bubbles"]:
        out["bubbles"] = (max(1, plan["bubbles"][0] - 1), plan["bubbles"][1])
    out["keys"] = min(plan["keys"], 1)
    out["morphs"] = min(plan["morphs"], 1)
    return out


def choose_endless(rng, level, names, empties, plan, ease, tries=30, traps=False):
    """The solvable deal with no losing first move whose careless-win rate is nearest `ease`."""
    best = None
    bubbles = plan["bubbles"]
    for _ in range(tries):
        cand = random_board(rng, names, empties, plan["mech"], plan["mcount"], plan["mix_hidden"], plan["mix_frozen"],
                            plan["vines"], bubbles, plan["keys"], plan["morphs"], plan["cap"])
        if cand is None:
            continue
        jars_c, mech_c = cand
        if bubbles:
            mech_c["floats"] = True
        b, _ = board_from_level(dict(level, jars=jars_c, mechanics=mech_c))
        if bubbles and sum(1 for jar in b.jars for p in jar if p[2] > 0) != sum(bubbles):
            continue
        # a quick, greedy look first throws out the boards that would be slow to settle, here and on a phone
        quick, _ = solve(b, 6_000, weight=3)
        if quick is None:
            continue
        sol, _ = solve(b, 40_000)
        if sol is None:
            continue
        # With one spare jar some first moves always lose the board: that is the Expert board's bite
        # (undo and the hint still work, and nothing is lost). Everywhere else no first move may.
        if not traps and killing_first_moves(b) > 0:
            continue
        rank = abs(playout_wins(b, rng) - ease)
        if best is None or rank < best[0]:
            best = (rank, jars_c, mech_c)
        if rank <= 0.05:
            break
    return None if best is None else (best[1], best[2])


def endless_capsule(pos):
    """A capsule every fifth level."""
    return pos % 5 == 0


def make_endless(pos):
    world_idx, k, empties, ease, plan = endless_plan(pos)
    beat = BEATS[(pos - 1) % 10]
    names = kinds_for(world_idx, k)
    rng = random.Random(f"{ENDLESS}-remix-{pos}")
    level = {"schema": 1, "id": f"{ENDLESS}-{pos:02d}", "world": ENDLESS, "index": pos, "beat": beat, "capacity": plan["cap"]}
    # As planned; then with a second spare jar; then with less of each rule.
    picked = None
    for em, pl in [(empties, plan), (2, plan), (2, lighter(plan)), (2, lighter(lighter(plan)))]:
        picked = choose_endless(rng, level, names, em, pl, ease, tries=30 if em > 1 else 80, traps=em == 1)
        if picked:
            break
    if not picked:
        raise SystemExit(f"{level['id']}: no fair board")
    jars, mechanics = picked
    level["jars"] = jars
    level["mechanics"] = {"hidden": mechanics.get("hidden", []), "sticky": mechanics.get("sticky", []),
                          "frozen": mechanics.get("frozen", [])}
    for extra in ("curtains", "vines", "floats", "keys", "morph"):
        if mechanics.get(extra):
            level["mechanics"][extra] = mechanics[extra]
    b, _ = board_from_level(level)
    sol, explored = solve(b, 3_000_000)
    if sol is None:
        raise SystemExit(f"{level['id']}: unsolvable or too big ({explored} states)")
    level["par"] = len(sol)
    level["solution"] = [list(m) for m in sol]
    level["capsule"] = endless_capsule(pos)
    level["softenAfterFails"] = 2 if beat in ("tension", "boss", "showpiece") else None
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


# Twist of the week: eight themes, five boards each, in Levels/weekly (01 to 40). The app picks the
# week's theme from the date. Keep the order in step with WeeklyTwist.themes and LevelCatalog.weeklyLooks.
WEEKLY = "weekly"
# (theme, then for each of its five boards: world whose squishies it borrows, main rule, guest rule)
WEEKLY_THEMES = [
    ("keys", [(1, "keys", None), (1, "keys", None), (1, "keys", "wrapped"), (1, "keys", "ice"), (1, "keys", "wrapped")]),
    ("vines", [(5, "vines", None), (5, "vines", None), (5, "vines", None), (5, "vines", "ice"), (5, "vines", "wrapped")]),
    ("morph", [(2, "morph", None), (2, "morph", None), (2, "morph", None), (2, "morph", "wrapped"), (2, "morph", "ice")]),
    ("duets", [(2, "duets", None), (2, "duets", None), (2, "duets", None), (2, "duets", "ice"), (2, "duets", "wrapped")]),
    ("big", [(4, "big", None), (4, "big", None), (4, "big", "wrapped"), (4, "big", "ice"), (4, "big", "vines")]),
    ("floaters", [(4, "floaters", None), (4, "floaters", None), (4, "floaters", None), (4, "floaters", "duets"), (4, "floaters", "wrapped")]),
    ("frozen", [(0, "ice", None), (0, "ice", None), (0, "ice", "wrapped"), (0, "ice", "curtains"), (0, "ice", "duets")]),
    ("grand-mix", [(0, "ice", "duets"), (1, "wrapped", "keys"), (2, "curtains", "ice"), (4, "floaters", "vines"), (5, "morph", "vines")]),
]
WEEKLY_BEATS = ["easy", "easy", "medium", "tension", "showpiece"]
WEEKLY_KINDS = [5, 6, 6, 7, 7]
WEEKLY_EASE = [0.6, 0.5, 0.4, 0.3, 0.2]


def make_weekly(pos):
    theme, boards = WEEKLY_THEMES[(pos - 1) // 5]
    n = (pos - 1) % 5 + 1
    world_idx, main, guest = boards[n - 1]
    plan = dict(mech=None, mcount=0, mix_hidden=0, mix_frozen=0, vines=None, bubbles=None, keys=0, morphs=0, cap=CAP)
    # the same dials as Keep Squishing, read at places 1, 3, 5, 7 and 9 of a block
    plan.update(endless_rule(main, 2 * n - 1, 0, False))
    if guest:
        plan.update(endless_rule(guest, 2 * n - 1, 0, True))
    k = WEEKLY_KINDS[n - 1] - (1 if plan["cap"] > CAP else 0)
    names = kinds_for(world_idx, k)
    rng = random.Random(f"{WEEKLY}-{theme}-{n}")
    level = {"schema": 1, "id": f"{WEEKLY}-{pos:02d}", "world": WEEKLY, "index": pos, "beat": WEEKLY_BEATS[n - 1], "capacity": plan["cap"]}
    # Always two spare jars and no first move that loses: these are calm boards for every age.
    picked = None
    for pl in [plan, lighter(plan), lighter(lighter(plan))]:
        picked = choose_endless(rng, level, names, 2, pl, WEEKLY_EASE[n - 1])
        if picked:
            break
    if not picked:
        raise SystemExit(f"{level['id']}: no fair board")
    jars, mechanics = picked
    level["jars"] = jars
    level["mechanics"] = {"hidden": mechanics.get("hidden", []), "sticky": mechanics.get("sticky", []),
                          "frozen": mechanics.get("frozen", [])}
    for extra in ("curtains", "vines", "floats", "keys", "morph"):
        if mechanics.get(extra):
            level["mechanics"][extra] = mechanics[extra]
    b, _ = board_from_level(level)
    sol, explored = solve(b, 3_000_000)
    if sol is None:
        raise SystemExit(f"{level['id']}: unsolvable or too big ({explored} states)")
    level["par"] = len(sol)
    level["solution"] = [list(m) for m in sol]
    level["capsule"] = False
    level["softenAfterFails"] = 2 if n >= 4 else None
    return level


def write_weekly(first, last):
    d = os.path.join(ROOT, "Levels", WEEKLY)
    os.makedirs(d, exist_ok=True)
    for pos in range(first, last + 1):
        lv = make_weekly(pos)
        with open(os.path.join(d, f"{pos:02d}.json"), "w") as f:
            f.write(dump(lv))
        kinds = len({q for jar in lv["jars"] for q in jar})
        m = lv["mechanics"]
        rules = [name for name in ("hidden", "sticky", "frozen", "curtains", "vines", "keys", "morph") if m.get(name)]
        print(f"{lv['id']:12} {WEEKLY_THEMES[(pos - 1) // 5][0]:10} jars={len(lv['jars']):2} cap={lv['capacity']} kinds={kinds} par={lv['par']:2} {rules}", flush=True)


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
    if m.get("floats"):
        extra += ', "floats": true'
    for name in ("keys", "morph"):
        if m.get(name):
            extra += f', "{name}": {json.dumps(m[name])}'
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
    if world == WEEKLY:
        # python3 tools/levelgen.py --world weekly [first last]
        i = sys.argv.index("--world") + 2
        nums = [int(x) for x in sys.argv[i:i + 2]]
        write_weekly(nums[0] if nums else 1, nums[1] if len(nums) > 1 else 5 * len(WEEKLY_THEMES))
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
