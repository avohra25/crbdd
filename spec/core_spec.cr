require "./spec_helper"

describe CrBDD::Manager do
  it "has distinct terminals" do
    m = CrBDD::Manager.new
    m.true.true?.should be_true
    m.false.false?.should be_true
    (m.true == m.false).should be_false
    (~m.true).should eq(m.false)
  end

  it "builds projection functions" do
    m = CrBDD::Manager.new(%w[a b])
    a = m.var("a")
    a.size.should eq(1)
    a.support.should eq(["a"])
    truth_table(a).should eq(table_of(2) { |x| x[0] })
    m.var("a").should eq(a)
  end

  it "rejects unknown and duplicate variables" do
    m = CrBDD::Manager.new(%w[a])
    expect_raises(CrBDD::Error) { m.var("zz") }
    expect_raises(CrBDD::Error) { m.new_var("a") }
    expect_raises(CrBDD::Error) { m.var(3) }
  end

  it "implements the boolean operators" do
    m = CrBDD::Manager.new(%w[a b])
    a, b = m.var("a"), m.var("b")
    truth_table(a & b).should eq(table_of(2) { |x| x[0] && x[1] })
    truth_table(a | b).should eq(table_of(2) { |x| x[0] || x[1] })
    truth_table(a ^ b).should eq(table_of(2) { |x| x[0] != x[1] })
    truth_table(a.implies(b)).should eq(table_of(2) { |x| !x[0] || x[1] })
    truth_table(a.iff(b)).should eq(table_of(2) { |x| x[0] == x[1] })
    truth_table(~a).should eq(table_of(2) { |x| !x[0] })
    truth_table(a.ite(b, ~b)).should eq(table_of(2) { |x| x[0] ? x[1] : !x[1] })
  end

  it "is canonical: equivalent formulas share one node" do
    m = CrBDD::Manager.new(%w[a b c])
    a, b, c = m.var("a"), m.var("b"), m.var("c")
    (a & (b | c)).should eq((a & b) | (a & c)) # distributivity
    (~(a & b)).should eq(~a | ~b)              # De Morgan
    (a ^ b ^ c).should eq(c ^ (b ^ a))         # associativity / commutativity
    ((a | ~a)).should eq(m.true)
    (a & ~a).should eq(m.false)
    a.implies(b).should eq(~a | b)
    ((a & b) <= a).should be_true
    (a <= (a & b)).should be_false
  end

  it "applies the reduction rule" do
    m = CrBDD::Manager.new(%w[a b])
    a, b = m.var("a"), m.var("b")
    ((a & b) | (~a & b)).should eq(b)
    ((a & b) | (~a & b)).size.should eq(1)
  end

  it "restricts and composes" do
    m = CrBDD::Manager.new(%w[a b c])
    a, b, c = m.var("a"), m.var("b"), m.var("c")
    f = (a & b) | c
    f.restrict("a", true).should eq(b | c)
    f.restrict("a", false).should eq(c)
    f.restrict("c", true).should eq(m.true)
    f.restrict({"a" => true, "b" => false}).should eq(c)
    f.compose("c", a & b).should eq(a & b)
    f.compose("b", ~a).should eq(c)
  end

  it "evaluates assignments" do
    m = CrBDD::Manager.new(%w[a b c])
    f = (m.var("a") & m.var("b")) | m.var("c")
    f.eval([true, true, false]).should be_true
    f.eval([true, false, false]).should be_false
    f.eval({"c" => true}).should be_true
  end

  it "computes the support" do
    m = CrBDD::Manager.new(%w[a b c d])
    f = (m.var("d") & m.var("b")) | (m.var("a") & ~m.var("a"))
    f.support.should eq(%w[b d])
  end

  it "builds parity with linear size" do
    names = (0...24).map { |i| "x#{i}" }
    m = CrBDD::Manager.new(names)
    f = names.reduce(m.false) { |acc, n| acc ^ m.var(n) }
    f.size.should eq(2 * 24 - 1)
  end

  it "refuses to mix managers" do
    m1 = CrBDD::Manager.new(%w[a])
    m2 = CrBDD::Manager.new(%w[a])
    expect_raises(CrBDD::Error) { m1.var("a") & m2.var("a") }
  end
end
