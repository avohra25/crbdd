require "./spec_helper"

# (x1 & y1) | (x2 & y2) | ... : linear with interleaved order, exponential
# with all x's above all y's.
def pairs_formula(n : Int32) : String
  (1..n).map { |i| "x#{i} & y#{i}" }.join(" | ")
end

describe "variable reordering" do
  it "keeps the function when changing the order" do
    m = CrBDD::Manager.new
    f = m.parse("(a | b) & (c ^ d) -> !a")
    m2 = m.with_order(%w[d c b a])
    g = m.transfer([f], m2).first
    m2.var_order.should eq(%w[d c b a])
    g.satcount.should eq(f.satcount)
    (0...16).each do |bits|
      env = %w[a b c d].each_with_index.to_h { |n, i| {n, bits.bit(i) == 1} }
      g.eval(env).should eq(f.eval(env))
    end
  end

  it "shows the order sensitivity of the pairs function" do
    n = 6
    xs = (1..n).map { |i| "x#{i}" }
    ys = (1..n).map { |i| "y#{i}" }
    good = CrBDD::Manager.new(xs.zip(ys).flat_map { |x, y| [x, y] })
    bad = CrBDD::Manager.new(xs + ys)
    good.parse(pairs_formula(n)).size.should eq(2 * n)
    bad.parse(pairs_formula(n)).size.should eq(2 ** (n + 1) - 2)
  end

  it "sifting recovers a good order and preserves the function" do
    n = 5
    xs = (1..n).map { |i| "x#{i}" }
    ys = (1..n).map { |i| "y#{i}" }
    m = CrBDD::Manager.new(xs + ys)
    f = m.parse(pairs_formula(n))
    before = f.size
    m2, roots = m.sift([f], passes: 4)
    g = roots.first
    g.size.should be < before
    g.size.should eq(2 * n)
    g.satcount.should eq(f.satcount)
    m2.parse(pairs_formula(n)).should eq(g)
  end

  it "never makes random functions bigger" do
    rng = Random.new(99)
    names = %w[a b c d e f]
    40.times do
      m = CrBDD::Manager.new(names)
      roots = Array.new(2) { random_expr(rng, names, 4).build(m) }
      before = m.node_count(roots.map(&.id))
      m2, rebuilt = m.sift(roots)
      m2.node_count(rebuilt.map(&.id)).should be <= before
      roots.zip(rebuilt).each { |r, o| o.satcount.should eq(r.satcount) }
    end
  end

  it "rejects invalid orders" do
    m = CrBDD::Manager.new(%w[a b])
    expect_raises(CrBDD::Error) { m.with_order(%w[a]) }
    expect_raises(CrBDD::Error) { m.with_order(%w[a c]) }
  end
end
