# crbdd

Reduced ordered binary decision diagrams (ROBDDs) in pure Crystal, with no
dependencies beyond the standard library: a hash-consed node store with a
memoised ITE core, quantification and relational products, exact model
counting, variable reordering by sifting, a boolean expression language, and
a `crbdd` command-line tool with a REPL.

A BDD is a canonical, often compact representation of a boolean function.
Because every node is hash-consed through a unique table, two formulas built
in the same manager are logically equivalent exactly when they are the same
node, so equivalence and tautology checks cost O(1) once the diagrams exist.

## Library

```crystal
require "crbdd"

m = CrBDD::Manager.new(%w[a b c])
a, b, c = m.var("a"), m.var("b"), m.var("c")

(a & (b | c)) == ((a & b) | (a & c)) # => true  (distributivity)
(~(a & b)) == (~a | ~b)              # => true  (De Morgan)

f = (a & b) | c
f.satcount              # => 5
f.restrict("c", false)  # same node as a & b
f.exists("a")           # same node as b | c
f.any_sat               # => {"a" => false, "c" => true}
f.cubes                 # disjoint paths to 1
f.to_dot                # Graphviz source

g = m.parse("forall b. (a -> b) | c") # expressions declare new variables
```

| Feature | API |
| --- | --- |
| operators | `~` `&` `\|` `^` `implies` `iff` `ite`, `<=` for implication checks |
| cofactors and substitution | `restrict`, `compose`, `rename` (simultaneous, swaps are fine) |
| quantification | `exists`, `forall`, `and_exists` (relational product without building `f & g`) |
| counting and models | `satcount` (exact `BigInt`), `any_sat`, `cubes`, `each_model` |
| inspection | `size`, `support`, `eval`, `to_dot`, `Manager#node_count` for shared size |
| ordering | `Manager#with_order`, `transfer`, `size_under`, `sift` |
| parsing | `CrBDD::Expr.parse`, `Manager#parse` |

### Design

- Nodes live in three flat `Int32` arrays (level, low, high); ids 0 and 1 are
  the terminals. A node stores the *level* of its variable, and the manager
  keeps the level/variable permutation, so variables keep their index and
  name across reorderings.
- `mk` applies the reduction rule (`low == high` collapses) and looks nodes up
  in the unique table, which gives canonicity.
- Every binary operator is `ite(f, g, h)` with terminal cases, standard-triple
  normalisation and a computed table.
- Quantification and `and_exists` stop recursing below the deepest
  quantified level and short-circuit when a branch is already true.
- `satcount` works level-aware with `BigInt`, so a 100-variable tautology
  reports 2^100 exactly.
- Reordering is done by rebuilding: `with_order` creates a manager with the
  requested order and `transfer` copies shared structure into it once.
  `sift` is Rudell-style sifting on top of that: each variable, most-used
  first, is tried in every position and kept where the shared size is
  smallest, for several passes while it improves. Rebuilding is slower than
  in-place adjacent swaps but simple to verify, and the original manager is
  left untouched.
- There is no garbage collection of dead nodes; a manager grows until it is
  dropped. That is fine for the problem sizes this library targets.

## Expressions

Loosest binding first: `<->`, `->` (right associative), `|` or `+`, `^`,
`&` or `*`, prefix `!` `~` `-`. Constants are `0 1 true false`, and
`exists x, y. e` / `forall x. e` quantify (the body extends as far right as
possible). The printer emits minimal parentheses and round-trips through the
parser.

## Command line

```sh
shards build --release        # or: crystal build --release src/cli.cr -o bin/crbdd
```

```console
$ crbdd check "a & b | c"
satisfiable
variables: 3 (a, b, c)
models:    5
bdd size:  3 nodes
witness:   !a c

$ crbdd equiv "a -> b" "b -> a"
not equivalent
counterexample: !a b
  first:  true
  second: false

$ crbdd models "a ^ b"
!a b
a !b

$ crbdd sift "x1&y1 | x2&y2 | x3&y3 | x4&y4" --order x1,x2,x3,x4,y1,y2,y3,y4
before: 30 nodes  order: x1 x2 x3 x4 y1 y2 y3 y4
after:  8 nodes  order: y1 x1 x2 y2 x3 y3 x4 y4

$ crbdd queens 8
8-queens: 92 solutions
bdd size: 2451 nodes, 83334 created, 181.6 ms

$ crbdd dot "(a | b) & c" | dot -Tsvg > f.svg
```

`crbdd repl` starts an interactive session where `name = expr` defines a
function that later expressions can mention; `:help` lists the commands
(`:equiv A ; B`, `:models`, `:dot`, `:defs`, `:vars`, `:quit`).

Exit status is 0 on success, 1 when `equiv` finds the expressions differ, and
2 on usage or parse errors.

## Examples

- `examples/queens.cr` counts N-queens solutions for N = 1..8.
- `examples/adder.cr` proves a 16-bit ripple-carry adder equal to a
  carry-lookahead adder and shows the order sensitivity of adder BDDs
  (a middle sum bit has 33 nodes interleaved and 4095 with all `a` bits
  above all `b` bits).

```sh
crystal run examples/queens.cr
crystal run --release examples/adder.cr
```

## Tests

```sh
crystal spec
```

The specs compare BDDs against exhaustive truth tables on hundreds of
seeded random formulas and functions: operators, canonicity, quantification
versus brute force, `and_exists` versus `exists(f & g)`, model counts and cube
covers, parser/printer round trips, function preservation under reordering,
sifting never growing a diagram, the pairs function going from exponential to
linear size, known N-queens counts, and the CLI and REPL through in-memory IO.

## License

MIT
