# Proves a 16-bit ripple-carry adder equal to a carry-lookahead adder,
# then shows how the interleaved variable order keeps the BDDs small.
#
#     crystal run examples/adder.cr
require "../src/crbdd"

BITS = 16
order = (0...BITS).flat_map { |i| ["a#{i}", "b#{i}"] }
m = CrBDD::Manager.new(order)
a = (0...BITS).map { |i| m.var("a#{i}") }
b = (0...BITS).map { |i| m.var("b#{i}") }

# ripple carry
carry = m.false
ripple = (0...BITS).map do |i|
  s = a[i] ^ b[i] ^ carry
  carry = (a[i] & b[i]) | (carry & (a[i] ^ b[i]))
  s
end

# carry lookahead: c[i+1] = g[i] | p[i] & c[i], expanded without reusing c
g = (0...BITS).map { |i| a[i] & b[i] }
p = (0...BITS).map { |i| a[i] | b[i] }
cla = (0...BITS).map do |i|
  c = m.false
  (0...i).each do |j|
    term = g[j]
    (j + 1...i).each { |k| term &= p[k] }
    c |= term
  end
  a[i] ^ b[i] ^ c
end

puts "ripple == lookahead: #{ripple.zip(cla).all? { |x, y| x == y }}"
puts "shared size (interleaved order): #{m.node_count(ripple.map(&.id))} nodes"

bad = m.with_order((0...BITS).map { |i| "a#{i}" } + (0...BITS).map { |i| "b#{i}" })
puts "sum bit 10 size, interleaved: #{ripple[10].size}, a's before b's: #{m.transfer([ripple[10]], bad).first.size}"
