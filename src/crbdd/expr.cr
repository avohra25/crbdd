module CrBDD
  # Boolean expression AST with a small recursive-descent parser.
  #
  # Grammar, loosest binding first:
  #
  #     expr  := iff
  #     iff   := imp ("<->" imp)*
  #     imp   := or ("->" imp)?            right associative
  #     or    := xor (("|" | "+") xor)*
  #     xor   := and ("^" and)*
  #     and   := unary (("&" | "*") unary)*
  #     unary := ("!" | "~" | "-") unary | atom
  #     atom  := ident | "0" | "1" | "true" | "false" | "(" expr ")"
  #            | ("exists" | "forall") ident ("," ident)* "." expr
  abstract class Expr
    def self.parse(src : String) : Expr
      Parser.new(src).parse
    end

    # Variable names in order of first appearance.
    def variables : Array(String)
      acc = [] of String
      collect_vars(acc)
      acc
    end

    abstract def collect_vars(acc : Array(String)) : Nil
    abstract def eval(env : Hash(String, Bool)) : Bool
    abstract def build(m : Manager) : Bdd
    abstract def to_s(io : IO) : Nil

    class Const < Expr
      getter value : Bool

      def initialize(@value)
      end

      def collect_vars(acc) : Nil
      end

      def eval(env) : Bool
        @value
      end

      def build(m : Manager) : Bdd
        m.constant(@value)
      end

      def to_s(io : IO) : Nil
        io << (@value ? '1' : '0')
      end
    end

    class Var < Expr
      getter name : String

      def initialize(@name)
      end

      def collect_vars(acc) : Nil
        acc << @name unless acc.includes?(@name)
      end

      def eval(env) : Bool
        env.fetch(@name) { raise Error.new("unbound variable #{@name}") }
      end

      def build(m : Manager) : Bdd
        m.var(m.var_index!(@name))
      end

      def to_s(io : IO) : Nil
        io << @name
      end
    end

    class Not < Expr
      getter arg : Expr

      def initialize(@arg)
      end

      def collect_vars(acc) : Nil
        @arg.collect_vars(acc)
      end

      def eval(env) : Bool
        !@arg.eval(env)
      end

      def build(m : Manager) : Bdd
        ~@arg.build(m)
      end

      def to_s(io : IO) : Nil
        io << '!'
        if @arg.is_a?(Binary) || @arg.is_a?(Quant)
          io << '(' << @arg << ')'
        else
          io << @arg
        end
      end
    end

    class Binary < Expr
      OPS = {"&" => 4, "^" => 3, "|" => 2, "->" => 1, "<->" => 0}

      getter op : String
      getter left : Expr
      getter right : Expr

      def initialize(@op, @left, @right)
      end

      def collect_vars(acc) : Nil
        @left.collect_vars(acc)
        @right.collect_vars(acc)
      end

      def eval(env) : Bool
        l = @left.eval(env)
        r = @right.eval(env)
        case @op
        when "&"   then l && r
        when "|"   then l || r
        when "^"   then l != r
        when "->"  then !l || r
        when "<->" then l == r
        else            raise Error.new("bad operator #{@op}")
        end
      end

      def build(m : Manager) : Bdd
        l = @left.build(m)
        r = @right.build(m)
        case @op
        when "&"   then l & r
        when "|"   then l | r
        when "^"   then l ^ r
        when "->"  then l.implies(r)
        when "<->" then l.iff(r)
        else            raise Error.new("bad operator #{@op}")
        end
      end

      # Fully precedence-aware printing that round-trips through the parser.
      def to_s(io : IO) : Nil
        prec = OPS[@op]
        right_assoc = @op == "->"
        side(io, @left, prec, right_assoc)
        io << ' ' << @op << ' '
        side(io, @right, prec, !right_assoc)
      end

      private def side(io, e, prec, paren_on_equal)
        p = e.is_a?(Binary) ? OPS[e.op] : (e.is_a?(Quant) ? -1 : 99)
        if p < prec || (p == prec && paren_on_equal)
          io << '(' << e << ')'
        else
          io << e
        end
      end
    end

    class Quant < Expr
      getter kind : String
      getter vars : Array(String)
      getter body : Expr

      def initialize(@kind, @vars, @body)
      end

      def collect_vars(acc) : Nil
        inner = [] of String
        @body.collect_vars(inner)
        inner.each { |v| acc << v unless acc.includes?(v) || @vars.includes?(v) }
      end

      def eval(env) : Bool
        results = (0...(1 << @vars.size)).map do |bits|
          e = env.dup
          @vars.each_with_index { |v, i| e[v] = bits.bit(i) == 1 }
          @body.eval(e)
        end
        @kind == "exists" ? results.any? : results.all?
      end

      def build(m : Manager) : Bdd
        @vars.each { |v| m.var_index!(v) }
        b = @body.build(m)
        @kind == "exists" ? b.exists(@vars) : b.forall(@vars)
      end

      def to_s(io : IO) : Nil
        io << @kind << ' ' << @vars.join(", ") << ". " << @body
      end
    end
  end

  class ParseError < Error
    getter position : Int32

    def initialize(message : String, @position : Int32)
      super("#{message} at offset #{@position}")
    end
  end

  class Parser
    TOKEN = /\G\s*(?:(<->|->|[&|^!~()*+.,-])|([A-Za-z_][A-Za-z0-9_'\[\]]*)|([01]))/

    @tokens = [] of {String, Int32}
    @pos = 0

    def initialize(@src : String)
      i = 0
      loop do
        while i < @src.size && @src[i].whitespace?
          i += 1
        end
        break if i >= @src.size
        md = TOKEN.match(@src, i)
        raise ParseError.new("unexpected character #{@src[i].inspect}", i) unless md
        tok = md[1]? || md[2]? || md[3]
        @tokens << {tok, md.begin(0) + md[0].size - tok.size}
        i = md.end(0)
      end
    end

    def parse : Expr
      e = parse_iff
      raise ParseError.new("unexpected #{peek.inspect}", offset) if @pos < @tokens.size
      e
    end

    private def peek : String?
      @tokens[@pos]?.try &.[0]
    end

    private def offset : Int32
      @tokens[@pos]?.try(&.[1]) || @src.size
    end

    private def accept(*toks : String) : String?
      t = peek
      if t && toks.includes?(t)
        @pos += 1
        t
      end
    end

    private def expect(tok : String) : Nil
      accept(tok) || raise ParseError.new("expected #{tok.inspect}", offset)
    end

    private def parse_iff : Expr
      e = parse_imp
      while accept("<->")
        e = Expr::Binary.new("<->", e, parse_imp)
      end
      e
    end

    private def parse_imp : Expr
      e = parse_or
      accept("->") ? Expr::Binary.new("->", e, parse_imp) : e
    end

    private def parse_or : Expr
      e = parse_xor
      while accept("|", "+")
        e = Expr::Binary.new("|", e, parse_xor)
      end
      e
    end

    private def parse_xor : Expr
      e = parse_and
      while accept("^")
        e = Expr::Binary.new("^", e, parse_and)
      end
      e
    end

    private def parse_and : Expr
      e = parse_unary
      while accept("&", "*")
        e = Expr::Binary.new("&", e, parse_unary)
      end
      e
    end

    private def parse_unary : Expr
      accept("!", "~", "-") ? Expr::Not.new(parse_unary) : parse_atom
    end

    private def parse_atom : Expr
      t = peek
      raise ParseError.new("unexpected end of input", offset) unless t
      case t
      when "("
        @pos += 1
        e = parse_iff
        expect(")")
        e
      when "0", "false"
        @pos += 1
        Expr::Const.new(false)
      when "1", "true"
        @pos += 1
        Expr::Const.new(true)
      when "exists", "forall"
        @pos += 1
        vars = [ident]
        while accept(",")
          vars << ident
        end
        expect(".")
        Expr::Quant.new(t, vars, parse_iff)
      else
        Expr::Var.new(ident)
      end
    end

    private def ident : String
      t = peek
      unless t && t =~ /\A[A-Za-z_]/ && !%w[true false exists forall].includes?(t)
        raise ParseError.new("expected a variable", offset)
      end
      @pos += 1
      t
    end
  end

  class Manager
    # Parses `src` and builds its BDD, declaring unseen variables at the
    # bottom of the order in order of first appearance.
    def parse(src : String) : Bdd
      Expr.parse(src).build(self)
    end
  end
end
