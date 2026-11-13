# Counts N-queens solutions for N = 1..8 by building one BDD per board.
#
#     crystal run examples/queens.cr
require "../src/crbdd"

(1..8).each do |n|
  f = CrBDD.queens(n)
  puts "#{n}: #{f.satcount} solutions (#{f.size} nodes)"
end
