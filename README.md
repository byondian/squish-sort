# Squish Sort

A native iOS sort puzzle with squishy toys. Tap a jar, the squishy on top hops
across; fill a jar with four of a kind and the lid plops on.

- Tech design: https://claude.ai/artifact/UHK8wPMgDe88LSHp2hDwcL
- Game design: https://claude.ai/artifact/QTnoBGjYDk9d5oTqE854qU

## Layout

| Path | What |
| --- | --- |
| `Packages/SquishKit` | Swift package with no UIKit/SpriteKit/SDK imports, so it runs in `swift test` |
| ├ `SquishCore` | Board, move rule, conga lines, hidden / duet / frozen mechanics, undo, stars |
| ├ `SquishLevels` | Level JSON, validation, A* solver (par and hints), `squish-levels` CLI |
| └ `SquishPolicy` | Age groups, ad request flags, interstitial cadence, capsule drops, remote config |
| `Levels/<world>/<nn>.json` | 80 levels: toyshop, sweetfactory, starlight, christmas |
| `Content/roster.json` | The 48 squishies with stable ids |
| `tools/levelgen.py` | Deterministic level generator (Python reference solver) |
| `.github/workflows/ci.yml` | Gates 1 and 2 on a GitHub macOS runner |

## Commands

```sh
swift test --package-path Packages/SquishKit                      # gate 1
swift run -c release --package-path Packages/SquishKit squish-levels check Levels   # gate 2
swift run --package-path Packages/SquishKit squish-levels solve Levels/toyshop/05.json
python3 tools/levelgen.py                                         # regenerate levels
```

## Rules in one place

Capacity 4, up to 12 jars. A move takes the top squishy and every same-kind
squishy directly under it, onto an empty jar or a matching top, as far as there
is room. The line stops at a wrapped (hidden) or frozen squishy and never
splits a duet. A full jar of one kind locks. Frozen squishies thaw after two
moves leave or land on a jar next to them in the same row. Win when every jar
is empty or complete; stuck when no move is legal.
