module CrBDD
  # The N-queens constraint as a BDD over variables q<row>_<col> (row-major
  # order). Its model count is the number of solutions.
  def self.queens(n : Int32, manager : Manager? = nil) : Bdd
    raise Error.new("n must be positive") unless n > 0
    m = manager || Manager.new
    q = Array.new(n) { |r| Array.new(n) { |c| m.var(m.var_index!("q#{r}_#{c}")) } }
    f = m.true
    n.times do |r|
      # at least one queen in each row
      f &= q[r].reduce(m.false) { |acc, x| acc | x }
      n.times do |c|
        clash = m.true
        n.times do |r2|
          n.times do |c2|
            next if r2 == r && c2 == c
            attacks = r2 == r || c2 == c || (r2 - r).abs == (c2 - c).abs
            clash &= ~q[r2][c2] if attacks
          end
        end
        f &= q[r][c].implies(clash)
      end
    end
    f
  end
end
