require "spec"
require "../src/crbdd"

# Exhaustive truth table of a BDD over all of its manager's variables.
def truth_table(f : CrBDD::Bdd) : Array(Bool)
  n = f.manager.num_vars
  (0...(1 << n)).map do |bits|
    f.eval(Array(Bool).new(n) { |i| bits.bit(i) == 1 })
  end
end

def table_of(n : Int32, &block : Array(Bool) -> Bool) : Array(Bool)
  (0...(1 << n)).map do |bits|
    yield Array(Bool).new(n) { |i| bits.bit(i) == 1 }
  end
end
