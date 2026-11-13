require "./spec_helper"

describe "quantification" do
  it "matches the Shannon definitions" do
    m = CrBDD::Manager.new(%w[a b c])
    a, b, c = m.var("a"), m.var("b"), m.var("c")
    f = (a & b) | (~a & c)
    f.exists("a").should eq(f.restrict("a", false) | f.restrict("a", true))
    f.forall("a").should eq(f.restrict("a", false) & f.restrict("a", true))
    f.exists("a").should eq(b | c)
    f.forall("a").should eq(b & c)
    f.exists("a", "b", "c").should eq(m.true)
    f.forall("a", "b", "c").should eq(m.false)
    f.exists([] of String).should eq(f)
  end

  it "computes relational products like exists(f & g)" do
    names = (0...8).map { |i| "v#{i}" }
    m = CrBDD::Manager.new(names)
    rng = Random.new(7)
    200.times do
      f = random_bdd(m, rng, 4)
      g = random_bdd(m, rng, 4)
      vars = names.select { rng.next_bool }
      f.and_exists(g, vars).should eq((f & g).exists(vars))
    end
  end

  it "quantifies random functions consistently with brute force" do
    names = %w[p q r s t]
    m = CrBDD::Manager.new(names)
    rng = Random.new(11)
    100.times do
      f = random_bdd(m, rng, 5)
      vars = names.select { rng.next_bool }
      idx = vars.map { |v| m.var_index(v) }
      ex = f.exists(vars)
      fa = f.forall(vars)
      table_of(5) { |x|
        any = all = nil.as(Bool?)
        (0...(1 << idx.size)).each do |bits|
          y = x.dup
          idx.each_with_index { |v, i| y[v] = bits.bit(i) == 1 }
          val = f.eval(y)
          any = (any || false) || val
          all = all.nil? ? val : (all && val)
        end
        any.not_nil!
      }.should eq(truth_table(ex))
      (fa == ~((~f).exists(vars))).should be_true
    end
  end

  it "renames variables simultaneously, including swaps" do
    m = CrBDD::Manager.new(%w[a b c])
    a, b, c = m.var("a"), m.var("b"), m.var("c")
    f = a & ~b
    f.rename({"a" => "b", "b" => "a"}).should eq(b & ~a)
    f.rename({"a" => "c"}).should eq(c & ~b)
  end
end

# Builds a random function as a DNF of random cubes.
def random_bdd(m : CrBDD::Manager, rng : Random, terms : Int32) : CrBDD::Bdd
  f = m.false
  terms.times do
    cube = m.true
    m.num_vars.times do |v|
      case rng.rand(3)
      when 0 then cube &= m.var(v)
      when 1 then cube &= ~m.var(v)
      end
    end
    f |= cube
  end
  f
end
