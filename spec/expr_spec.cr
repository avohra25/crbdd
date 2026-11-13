require "./spec_helper"

describe CrBDD::Expr do
  it "parses with the documented precedence" do
    CrBDD::Expr.parse("a | b & c").to_s.should eq("a | b & c")
    CrBDD::Expr.parse("(a | b) & c").to_s.should eq("(a | b) & c")
    CrBDD::Expr.parse("a -> b -> c").to_s.should eq("a -> b -> c")
    CrBDD::Expr.parse("(a -> b) -> c").to_s.should eq("(a -> b) -> c")
    CrBDD::Expr.parse("!a ^ b <-> c").to_s.should eq("!a ^ b <-> c")
    CrBDD::Expr.parse("a*b + ~c").to_s.should eq("a & b | !c")
    CrBDD::Expr.parse("exists x, y. x & y | z").to_s.should eq("exists x, y. x & y | z")
  end

  it "evaluates implication right-associatively" do
    e = CrBDD::Expr.parse("a -> b -> c")
    e.eval({"a" => true, "b" => false, "c" => false}).should be_true
  end

  it "reports parse errors with positions" do
    expect_raises(CrBDD::ParseError, /offset 4/) { CrBDD::Expr.parse("a & ") }
    expect_raises(CrBDD::ParseError, /expected "\)"/) { CrBDD::Expr.parse("(a | b") }
    expect_raises(CrBDD::ParseError, /unexpected character/) { CrBDD::Expr.parse("a # b") }
    expect_raises(CrBDD::ParseError) { CrBDD::Expr.parse("a b") }
  end

  it "lists variables in order of first appearance" do
    CrBDD::Expr.parse("c & (a | c) -> b").variables.should eq(%w[c a b])
    CrBDD::Expr.parse("exists a. a & b").variables.should eq(%w[b])
  end

  it "builds BDDs that match the AST semantics on random formulas" do
    rng = Random.new(2026)
    names = %w[a b c d e]
    400.times do
      e = random_expr(rng, names, 5)
      reparsed = CrBDD::Expr.parse(e.to_s)
      m = CrBDD::Manager.new(names)
      f = e.build(m)
      reparsed.build(m).should eq(f) # printer round-trips
      table = table_of(5) { |x| e.eval(names.zip(x).to_h) }
      truth_table(f).should eq(table)
      f.satcount.should eq(table.count(true))
    end
  end

  it "proves classic identities by canonicity" do
    m = CrBDD::Manager.new
    m.parse("a -> b").should eq(m.parse("!b -> !a"))
    m.parse("(a -> b) & (b -> c)").implies(m.parse("a -> c")).tautology?.should be_true
    m.parse("!(a | b) <-> !a & !b").tautology?.should be_true
    m.parse("a ^ a").should eq(m.false)
    m.parse("exists a. a & b").should eq(m.parse("b"))
    m.parse("forall a. a | b").should eq(m.parse("b"))
  end
end

def random_expr(rng : Random, names : Array(String), depth : Int32) : CrBDD::Expr
  if depth == 0 || rng.rand(4) == 0
    return rng.rand(12) == 0 ? CrBDD::Expr::Const.new(rng.next_bool) : CrBDD::Expr::Var.new(names.sample(rng))
  end
  case rng.rand(8)
  when 0
    CrBDD::Expr::Not.new(random_expr(rng, names, depth - 1))
  when 1
    CrBDD::Expr::Quant.new(rng.next_bool ? "exists" : "forall", [names.sample(rng)], random_expr(rng, names, depth - 1))
  else
    op = %w[& | ^ -> <->].sample(rng)
    CrBDD::Expr::Binary.new(op, random_expr(rng, names, depth - 1), random_expr(rng, names, depth - 1))
  end
end
