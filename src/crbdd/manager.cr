module CrBDD
  # Owns every node. Nodes are hash-consed through a unique table, so two
  # BDDs built in the same manager represent the same boolean function if
  # and only if they have the same node id (canonicity).
  #
  # Nodes are stored in flat arrays (level, low, high) and identified by
  # their index. Ids 0 and 1 are the terminals FALSE and TRUE. Each node
  # records the *level* of its variable; the level <-> variable mapping is
  # the variable order.
  class Manager
    FALSE_ID = 0
    TRUE_ID  = 1
    TERMINAL = Int32::MAX

    getter var_at_level = [] of Int32
    getter level_of_var = [] of Int32
    getter names = [] of String

    @level = [TERMINAL, TERMINAL]
    @low = [FALSE_ID, TRUE_ID]
    @high = [FALSE_ID, TRUE_ID]
    @unique = {} of {Int32, Int32, Int32} => Int32
    @ite_cache = {} of {Int32, Int32, Int32} => Int32
    @name_index = {} of String => Int32

    # Creates a manager with the given variables, ordered top to bottom.
    def initialize(names : Enumerable(String) = [] of String)
      names.each { |n| new_var(n) }
    end

    def num_vars : Int32
      @names.size
    end

    # Total number of nodes ever created, terminals included.
    def num_nodes : Int32
      @level.size
    end

    # Declares a new variable placed below every existing one and returns
    # its index.
    def new_var(name : String? = nil) : Int32
      v = num_vars
      name ||= "x#{v}"
      raise Error.new("duplicate variable #{name}") if @name_index.has_key?(name)
      @names << name
      @name_index[name] = v
      @var_at_level << v
      @level_of_var << v
      v
    end

    def var_index(name : String) : Int32
      @name_index[name]? || raise Error.new("unknown variable #{name}")
    end

    def var_index?(name : String) : Int32?
      @name_index[name]?
    end

    # Returns the variable index for `name`, declaring it if needed.
    def var_index!(name : String) : Int32
      @name_index[name]? || new_var(name)
    end

    def name_of(v : Int32) : String
      @names[v]
    end

    def var_order : Array(String)
      @var_at_level.map { |v| @names[v] }
    end

    def true : Bdd
      Bdd.new(self, TRUE_ID)
    end

    def false : Bdd
      Bdd.new(self, FALSE_ID)
    end

    def constant(b : Bool) : Bdd
      b ? self.true : self.false
    end

    # The projection function of variable `v` (index or name).
    def var(v : Int32) : Bdd
      check_var(v)
      Bdd.new(self, mk(@level_of_var[v], FALSE_ID, TRUE_ID))
    end

    def var(name : String) : Bdd
      var(var_index(name))
    end

    def nvar(v : Int32 | String) : Bdd
      ~var(v)
    end

    # Wraps a raw node id that belongs to this manager.
    def wrap(id : Int32) : Bdd
      raise Error.new("bad node id #{id}") unless 0 <= id < num_nodes
      Bdd.new(self, id)
    end

    # ---- raw node access ------------------------------------------------

    def terminal?(n : Int32) : Bool
      n <= TRUE_ID
    end

    def level(n : Int32) : Int32
      @level[n]
    end

    def low(n : Int32) : Int32
      @low[n]
    end

    def high(n : Int32) : Int32
      @high[n]
    end

    # Variable index tested by an internal node.
    def var_of(n : Int32) : Int32
      raise Error.new("terminal has no variable") if terminal?(n)
      @var_at_level[@level[n]]
    end

    # Finds or creates the node (lvl ? hi : lo), applying the reduction rule.
    def mk(lvl : Int32, lo : Int32, hi : Int32) : Int32
      return lo if lo == hi
      key = {lvl, lo, hi}
      if id = @unique[key]?
        return id
      end
      id = @level.size
      @level << lvl
      @low << lo
      @high << hi
      @unique[key] = id
      id
    end

    # Cofactors of `n` with respect to level `lvl` (which must be <= level(n)).
    @[AlwaysInline]
    def cofactors(n : Int32, lvl : Int32) : {Int32, Int32}
      @level[n] == lvl ? {@low[n], @high[n]} : {n, n}
    end

    # If-then-else: (f & g) | (!f & h). Every binary operator reduces to it.
    def ite(f : Int32, g : Int32, h : Int32) : Int32
      return g if f == TRUE_ID
      return h if f == FALSE_ID
      return g if g == h
      return f if g == TRUE_ID && h == FALSE_ID
      # Standard triples: normalise so equivalent calls share a cache entry.
      g = TRUE_ID if g == f
      h = FALSE_ID if h == f
      key = {f, g, h}
      if r = @ite_cache[key]?
        return r
      end
      top = Math.min(@level[f], Math.min(@level[g], @level[h]))
      f0, f1 = cofactors(f, top)
      g0, g1 = cofactors(g, top)
      h0, h1 = cofactors(h, top)
      r = mk(top, ite(f0, g0, h0), ite(f1, g1, h1))
      @ite_cache[key] = r
      r
    end

    def not(f : Int32) : Int32
      ite(f, FALSE_ID, TRUE_ID)
    end

    def and(f : Int32, g : Int32) : Int32
      ite(f, g, FALSE_ID)
    end

    def or(f : Int32, g : Int32) : Int32
      ite(f, TRUE_ID, g)
    end

    def xor(f : Int32, g : Int32) : Int32
      ite(f, self.not(g), g)
    end

    def imp(f : Int32, g : Int32) : Int32
      ite(f, g, TRUE_ID)
    end

    def iff(f : Int32, g : Int32) : Int32
      ite(f, g, self.not(g))
    end

    # f with variable v fixed to `value`.
    def restrict(f : Int32, v : Int32, value : Bool) : Int32
      check_var(v)
      lvl = @level_of_var[v]
      memo = {} of Int32 => Int32
      restrict_rec(f, lvl, value, memo)
    end

    private def restrict_rec(f, lvl, value, memo) : Int32
      fl = @level[f]
      return f if fl > lvl
      return(value ? @high[f] : @low[f]) if fl == lvl
      memo[f]? || (memo[f] = mk(fl, restrict_rec(@low[f], lvl, value, memo),
        restrict_rec(@high[f], lvl, value, memo)))
    end

    # Restricts several variables at once: `assignment` maps var index => value.
    def restrict(f : Int32, assignment : Hash(Int32, Bool)) : Int32
      levels = {} of Int32 => Bool
      assignment.each { |v, b| check_var(v); levels[@level_of_var[v]] = b }
      memo = {} of Int32 => Int32
      restrict_many(f, levels, memo)
    end

    private def restrict_many(f, levels, memo) : Int32
      return f if terminal?(f)
      memo[f]? || begin
        fl = @level[f]
        r = if levels.has_key?(fl)
              restrict_many(levels[fl] ? @high[f] : @low[f], levels, memo)
            else
              mk(fl, restrict_many(@low[f], levels, memo), restrict_many(@high[f], levels, memo))
            end
        memo[f] = r
      end
    end

    # Substitutes function g for variable v in f.
    def compose(f : Int32, v : Int32, g : Int32) : Int32
      ite(g, restrict(f, v, true), restrict(f, v, false))
    end

    # Evaluates f under a total assignment indexed by variable.
    def eval(f : Int32, assignment : Indexable(Bool)) : Bool
      n = f
      until terminal?(n)
        n = assignment[var_of(n)] ? @high[n] : @low[n]
      end
      n == TRUE_ID
    end

    # Number of internal nodes reachable from the given roots (shared).
    def node_count(roots : Enumerable(Int32)) : Int32
      seen = Set(Int32).new
      stack = roots.to_a
      until stack.empty?
        n = stack.pop
        next if terminal?(n) || !seen.add?(n)
        stack << @low[n] << @high[n]
      end
      seen.size
    end

    # Variables f actually depends on, in order.
    def support(f : Int32) : Array(Int32)
      levels = Set(Int32).new
      seen = Set(Int32).new
      stack = [f]
      until stack.empty?
        n = stack.pop
        next if terminal?(n) || !seen.add?(n)
        levels << @level[n]
        stack << @low[n] << @high[n]
      end
      levels.to_a.sort!.map { |l| @var_at_level[l] }
    end

    # Drops the operation cache (the unique table is kept).
    def clear_cache : Nil
      @ite_cache.clear
    end

    protected def check_var(v : Int32) : Nil
      raise Error.new("unknown variable index #{v}") unless 0 <= v < num_vars
    end
  end
end
