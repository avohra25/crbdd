require "./spec_helper"

def cli(*args : String, input : String = "") : {Int32, String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  code = CrBDD::CLI.run(args.to_a, stdout, stderr, IO::Memory.new(input))
  {code, stdout.to_s, stderr.to_s}
end

describe CrBDD::CLI do
  it "prints usage" do
    code, text, _ = cli("--help")
    code.should eq(0)
    text.should contain("usage: crbdd")
  end

  it "checks expressions" do
    code, text, _ = cli("check", "a & b | c")
    code.should eq(0)
    text.should contain("satisfiable")
    text.should contain("models:    5")
    cli("check", "a | !a")[1].should start_with("tautology")
    cli("check", "a & !a")[1].should start_with("unsatisfiable")
  end

  it "decides equivalence with a counterexample" do
    cli("equiv", "a -> b", "!a | b").should eq({0, "equivalent\n", ""})
    code, text, _ = cli("equiv", "a -> b", "b -> a")
    code.should eq(1)
    text.should contain("counterexample: ")
  end

  it "counts and lists models" do
    cli("count", "a ^ b")[1].should eq("2\n")
    cli("count", "--vars", "a,b,c", "a ^ b")[1].should eq("4\n")
    cli("models", "a ^ b")[1].should eq("!a b\na !b\n")
    cli("models", "--cubes", "a | b")[1].lines.size.should eq(2)
    cli("models", "--limit", "1", "a | b")[1].lines.size.should eq(1)
    cli("models", "a & !a")[1].should eq("(no models)\n")
  end

  it "honours --order" do
    cli("check", "--order", "c,b,a", "a & b")[1].should contain("(c, b, a)")
  end

  it "emits DOT" do
    cli("dot", "a & b")[1].should start_with("digraph bdd {")
  end

  it "sifts" do
    _, text, _ = cli("sift", "x1 & y1 | x2 & y2 | x3 & y3", "--order", "x1,x2,x3,y1,y2,y3")
    text.should contain("before: 14 nodes")
    text.should contain("after:  6 nodes")
  end

  it "counts queens" do
    cli("queens", "6")[1].should start_with("6-queens: 4 solutions")
  end

  it "reports errors with exit status 2" do
    code, _, errs = cli("check", "a &")
    code.should eq(2)
    errs.should contain("parse error")
    cli("frobnicate")[0].should eq(2)
    cli("check", "--bogus", "a")[0].should eq(2)
    cli("equiv", "a")[0].should eq(2)
    cli("count", "--vars", "a", "a & b")[0].should eq(2)
  end

  it "runs a REPL session with definitions" do
    script = "f = a -> b\ng = !b -> !a\n:equiv f ; g\n:equiv f ; b -> a\nf & a\n:vars\n:nope\n:quit\n"
    code, text, _ = cli("repl", input: script)
    code.should eq(0)
    text.should contain("f: 3 models")
    text.should contain("equivalent\n")
    text.should contain("not equivalent, e.g.")
    text.should contain("models:    1")
    text.should contain("a b\n")
    text.should contain("error: unknown command :nope")
  end
end

describe "N-queens" do
  it "counts known solution numbers" do
    [1, 0, 0, 2, 10, 4].each_with_index do |expected, i|
      CrBDD.queens(i + 1).satcount.should eq(expected)
    end
  end
end
