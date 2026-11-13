module CrBDD
  # Command-line front end. `run` returns the process exit status, so it can
  # be tested without spawning processes.
  module CLI
    USAGE = <<-TXT
      usage: crbdd <command> [options] [args]

      commands:
        check  EXPR           satisfiability, tautology, model count, BDD size
        equiv  EXPR EXPR      decide equivalence; prints a counterexample if not
        count  EXPR           number of models over the expression's variables
        models EXPR           list models (--cubes for compact cubes, --limit N)
        dot    EXPR           Graphviz DOT of the BDD
        sift   EXPR...        reorder variables by sifting, report sizes and order
        queens N              count N-queens solutions with a BDD
        repl                  interactive session (try :help)

      options:
        --order a,b,c         declare these variables first, top to bottom
        --vars a,b,c          count/models over exactly these variables
        --limit N             stop listing models after N (default 64)
        --cubes               list cubes (paths) instead of total models
        -h, --help            show this help

      expressions: ! ~ (not), & * (and), ^ (xor), | + (or), -> (implies),
      <-> (iff), 0/1, exists x,y. e, forall x. e
      TXT

    class UsageError < Error; end

    record Options, order : Array(String)?, vars : Array(String)?, limit : Int32, cubes : Bool

    def self.run(args : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR, stdin : IO = STDIN) : Int32
      opts, rest = parse_options(args)
      if rest.empty?
        stdout << USAGE
        return 0
      end
      cmd = rest.shift
      m = Manager.new(opts.order || [] of String)
      case cmd
      when "check"  then check(m, one(rest, cmd), stdout)
      when "equiv"  then equiv(m, rest, stdout)
      when "count"  then count(m, one(rest, cmd), opts, stdout)
      when "models" then models(m, one(rest, cmd), opts, stdout)
      when "dot"
        stdout << m.parse(one(rest, cmd)).to_dot
        0
      when "sift"   then sift(m, rest, stdout)
      when "queens" then queens(one(rest, cmd), stdout)
      when "repl"   then Repl.new(m, stdin, stdout).run
      when "help"
        stdout << USAGE
        0
      else
        raise UsageError.new("unknown command #{cmd.inspect}")
      end
    rescue ex : UsageError
      stderr << "crbdd: " << ex.message << "\n" << "run 'crbdd --help' for usage\n"
      2
    rescue ex : ParseError
      stderr << "crbdd: parse error: " << ex.message << '\n'
      2
    rescue ex : Error
      stderr << "crbdd: " << ex.message << '\n'
      2
    end

    def self.parse_options(args : Array(String)) : {Options, Array(String)}
      order = vars = nil
      limit = 64
      cubes = false
      rest = [] of String
      it = args.each
      loop do
        a = it.next
        break if a.is_a?(Iterator::Stop)
        case a
        when "--order" then order = list(it.next, a)
        when "--vars"  then vars = list(it.next, a)
        when "--limit"
          v = it.next
          limit = (v.as?(String).try &.to_i?) || raise UsageError.new("--limit needs a number")
        when "--cubes"      then cubes = true
        when "-h", "--help" then rest = ["help"]; break
        else
          raise UsageError.new("unknown option #{a}") if a.starts_with?("--")
          rest << a
        end
      end
      {Options.new(order, vars, limit, cubes), rest}
    end

    private def self.list(v, flag) : Array(String)
      raise UsageError.new("#{flag} needs a value") unless v.is_a?(String)
      v.split(',').map(&.strip).reject(&.empty?)
    end

    private def self.one(rest, cmd) : String
      raise UsageError.new("#{cmd} takes exactly one argument") unless rest.size == 1
      rest[0]
    end

    def self.format_assignment(h : Hash(String, Bool)) : String
      return "(any)" if h.empty?
      h.map { |k, v| v ? k : "!#{k}" }.join(" ")
    end

    def self.summary(f : Bdd, io : IO) : Nil
      status = f.tautology? ? "tautology" : (f.satisfiable? ? "satisfiable" : "unsatisfiable")
      io << status << '\n'
      io << "variables: " << f.manager.num_vars << " (" << f.manager.var_order.join(", ") << ")\n"
      io << "models:    " << f.satcount << '\n'
      io << "bdd size:  " << f.size << " nodes\n"
      if (w = f.any_sat) && !f.tautology?
        io << "witness:   " << format_assignment(w) << '\n'
      end
    end

    private def self.check(m, src, io) : Int32
      summary(m.parse(src), io)
      0
    end

    private def self.equiv(m, rest, io) : Int32
      raise UsageError.new("equiv takes exactly two arguments") unless rest.size == 2
      f = m.parse(rest[0])
      g = m.parse(rest[1])
      if f == g
        io << "equivalent\n"
        return 0
      end
      diff = (f ^ g).any_sat.not_nil!
      io << "not equivalent\n"
      io << "counterexample: " << format_assignment(diff) << '\n'
      io << "  first:  " << f.restrict(diff).true? << '\n'
      io << "  second: " << g.restrict(diff).true? << '\n'
      1
    end

    private def self.over(m : Manager, f : Bdd, opts : Options) : Array(String)
      vars = opts.vars || m.var_order
      vars.each { |v| m.var_index!(v) }
      missing = f.support - vars
      raise Error.new("--vars must include #{missing.join(", ")}") unless missing.empty?
      vars
    end

    private def self.count(m, src, opts, io) : Int32
      f = m.parse(src)
      vars = over(m, f, opts)
      # project the count onto `vars`
      io << (f.satcount >> (m.num_vars - vars.size)) << '\n'
      0
    end

    private def self.models(m, src, opts, io) : Int32
      f = m.parse(src)
      n = 0
      if opts.cubes
        f.cubes.each do |c|
          break if n >= opts.limit
          io << format_assignment(c) << '\n'
          n += 1
        end
      else
        vars = over(m, f, opts)
        f.each_model(vars) do |mdl|
          break if n >= opts.limit
          io << vars.map { |v| mdl[v] ? v : "!#{v}" }.join(" ") << '\n'
          n += 1
        end
      end
      io << "(no models)\n" if n == 0
      0
    end

    private def self.sift(m, rest, io) : Int32
      raise UsageError.new("sift needs at least one expression") if rest.empty?
      roots = rest.map { |src| m.parse(src) }
      before = m.node_count(roots.map(&.id))
      m2, rebuilt = m.sift(roots, passes: 4)
      after = m2.node_count(rebuilt.map(&.id))
      io << "before: " << before << " nodes  order: " << m.var_order.join(" ") << '\n'
      io << "after:  " << after << " nodes  order: " << m2.var_order.join(" ") << '\n'
      0
    end

    private def self.queens(arg, io) : Int32
      n = arg.to_i? || raise UsageError.new("queens needs a number")
      raise UsageError.new("queens: N must be between 1 and 12") unless 1 <= n <= 12
      f = uninitialized Bdd
      elapsed = Time.measure { f = CrBDD.queens(n) }
      io << n << "-queens: " << f.satcount << " solutions\n"
      io << "bdd size: " << f.size << " nodes, " << f.manager.num_nodes << " created, "
      io << elapsed.total_milliseconds.round(1) << " ms\n"
      0
    end

    # Line-oriented interactive session. Definitions (`name = expr`) are
    # expanded when later expressions mention them.
    class Repl
      HELP = <<-TXT
        name = EXPR      define a function
        EXPR             show satisfiability, models and size
        :equiv A ; B     compare two expressions
        :models EXPR     list cubes of EXPR
        :dot EXPR        print Graphviz DOT
        :defs            list definitions
        :vars            show the variable order
        :quit            leave
        TXT

      def initialize(@m : Manager, @in : IO, @out : IO)
        @defs = {} of String => Bdd
      end

      def run : Int32
        loop do
          @out << "bdd> "
          @out.flush
          line = @in.gets
          break unless line
          line = line.strip
          next if line.empty? || line.starts_with?('#')
          break if {":quit", ":q", ":exit"}.includes?(line)
          begin
            handle(line)
          rescue ex : Error
            @out << "error: " << ex.message << '\n'
          end
        end
        @out << '\n'
        0
      end

      private def build(src : String) : Bdd
        @m.parse(src, @defs)
      end

      private def handle(line : String) : Nil
        if md = line.match(/\A([A-Za-z_][A-Za-z0-9_]*)\s*:?=(?!=)\s*(.+)\z/)
          name = md[1]
          raise Error.new("#{name} is already a variable") if @m.var_index?(name)
          f = build(md[2])
          @defs[name] = f
          @out << name << ": " << f.satcount << " models, " << f.size << " nodes\n"
        elsif line.starts_with?(":equiv ")
          a, sep, b = line[7..].partition(';')
          raise Error.new("usage: :equiv A ; B") if sep.empty?
          f, g = build(a), build(b)
          if f == g
            @out << "equivalent\n"
          else
            @out << "not equivalent, e.g. " << CLI.format_assignment((f ^ g).any_sat.not_nil!) << '\n'
          end
        elsif line.starts_with?(":models ")
          f = build(line[8..])
          cubes = f.cubes
          cubes.first(32).each { |c| @out << CLI.format_assignment(c) << '\n' }
          @out << "... (" << cubes.size << " cubes)\n" if cubes.size > 32
          @out << "(no models)\n" if cubes.empty?
        elsif line.starts_with?(":dot ")
          @out << build(line[5..]).to_dot
        elsif line == ":defs"
          @defs.each { |k, f| @out << k << ": " << f.size << " nodes\n" }
        elsif line == ":vars"
          @out << @m.var_order.join(" ") << '\n'
        elsif line == ":help"
          @out << HELP
        elsif line.starts_with?(':')
          raise Error.new("unknown command #{line.split.first} (try :help)")
        else
          CLI.summary(build(line), @out)
        end
      end
    end
  end
end
