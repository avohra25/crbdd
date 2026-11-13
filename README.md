# crbdd

Reduced ordered binary decision diagrams (ROBDDs) in pure Crystal, with no
dependencies beyond the standard library.

A BDD is a canonical, usually compact representation of a boolean function.
Because nodes are hash-consed, two formulas built in the same manager are
logically equivalent exactly when they are the same node, so equivalence and
tautology checks are O(1) once the diagrams exist.

```crystal
require "crbdd"

m = CrBDD::Manager.new(%w[a b c])
a, b, c = m.var("a"), m.var("b"), m.var("c")

(a & (b | c)) == ((a & b) | (a & c)) # => true
(~(a & b)) == (~a | ~b)              # => true
((a & b) | c).restrict("c", false)   # => a & b
```

## Status

Work in progress. Done so far:

- core: unique table, memoised ITE, boolean operators, restrict/compose,
  evaluation, support
- existential/universal quantification, relational product
  (`and_exists`), simultaneous variable renaming
- exact model counting with `BigInt`, satisfying cubes, cube and model
  enumeration
- Graphviz DOT export

## Development

```sh
crystal spec
```

## License

MIT
