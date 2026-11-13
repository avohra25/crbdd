require "./spec_helper"

describe "model counting and enumeration" do
  it "counts models exactly" do
    m = CrBDD::Manager.new(%w[a b c])
    a, b, c = m.var("a"), m.var("b"), m.var("c")
    m.false.satcount.should eq(0)
    m.true.satcount.should eq(8)
    a.satcount.should eq(4)
    c.satcount.should eq(4)
    ((a & b) | c).satcount.should eq(5)
    (a ^ b ^ c).satcount.should eq(4)
  end

  it "counts beyond 64 bits" do
    names = (0...100).map { |i| "x#{i}" }
    m = CrBDD::Manager.new(names)
    m.true.satcount.should eq(BigInt.new(1) << 100)
    (m.var("x99") | m.var("x0")).satcount.should eq((BigInt.new(3)) << 98)
  end

  it "agrees with the truth table on random functions" do
    m = CrBDD::Manager.new(%w[a b c d e f])
    rng = Random.new(3)
    300.times do
      f = random_bdd(m, rng, rng.rand(1..6))
      f.satcount.should eq(truth_table(f).count(true))
    end
  end

  it "finds a satisfying cube" do
    m = CrBDD::Manager.new(%w[a b c])
    a, b, c = m.var("a"), m.var("b"), m.var("c")
    m.false.any_sat.should be_nil
    m.true.any_sat.should eq({} of String => Bool)
    f = a & ~b & c
    f.any_sat.should eq({"a" => true, "b" => false, "c" => true})
    g = (a & b) | c
    cube = g.any_sat.not_nil!
    g.restrict(cube).should eq(m.true)
  end

  it "enumerates disjoint cubes covering exactly the models" do
    m = CrBDD::Manager.new(%w[a b c d])
    rng = Random.new(5)
    100.times do
      f = random_bdd(m, rng, 3)
      cover = m.false
      total = BigInt.new(0)
      f.cubes.each do |cube|
        term = cube.reduce(m.true) { |acc, (k, v)| acc & (v ? m.var(k) : ~m.var(k)) }
        (cover & term).should eq(m.false) # disjoint
        cover |= term
        total += term.satcount
      end
      cover.should eq(f)
      total.should eq(f.satcount)
    end
  end

  it "enumerates total models" do
    m = CrBDD::Manager.new(%w[a b c])
    f = m.var("a") | m.var("c")
    models = [] of Hash(String, Bool)
    f.each_model { |mdl| models << mdl }
    models.size.should eq(6)
    models.uniq.size.should eq(6)
    models.each { |mdl| f.eval(mdl).should be_true }
    sub = [] of Hash(String, Bool)
    f.each_model(%w[a c]) { |mdl| sub << mdl }
    sub.size.should eq(3)
    expect_raises(CrBDD::Error) { f.each_model(%w[a]) { } }
  end
end

describe "DOT export" do
  it "renders nodes, edges and the root" do
    m = CrBDD::Manager.new(%w[a b])
    dot = (m.var("a") & m.var("b")).to_dot("conj")
    dot.should start_with("digraph bdd {")
    dot.should contain("label=\"a\"")
    dot.should contain("label=\"b\"")
    dot.should contain("[style=dashed]")
    dot.should contain("\"root_conj\"")
    dot.scan(/ -> /).size.should eq(5)
  end
end
