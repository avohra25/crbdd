module CrBDD
  class Manager
    # A fresh manager with the same variables (same indices and names) but
    # the given top-to-bottom order of variable names.
    def with_order(order : Array(String)) : Manager
      unless order.size == num_vars && order.sort == @names.sort
        raise Error.new("order must be a permutation of the variables")
      end
      m = Manager.new(@names)
      m.set_order(order.map { |n| var_index(n) })
      m
    end

    protected def set_order(var_at_level : Array(Int32)) : Nil
      raise Error.new("set_order on a non-empty manager") unless num_nodes == 2
      @var_at_level = var_at_level.dup
      var_at_level.each_with_index { |v, l| @level_of_var[v] = l }
    end

    # Rebuilds BDDs from this manager inside `target`, which must declare the
    # same variable names (in any order). Shared structure is copied once.
    def transfer(roots : Array(Bdd), target : Manager) : Array(Bdd)
      map = @names.map { |n| target.var_index(n) }
      memo = {FALSE_ID => FALSE_ID, TRUE_ID => TRUE_ID}
      roots.map do |r|
        raise Error.new("root from another manager") unless r.manager.same?(self)
        target.wrap(transfer_rec(r.id, target, map, memo))
      end
    end

    private def transfer_rec(n, target, map, memo) : Int32
      memo[n]? || begin
        lo = transfer_rec(@low[n], target, map, memo)
        hi = transfer_rec(@high[n], target, map, memo)
        memo[n] = target.ite(target.var(map[var_of(n)]).id, hi, lo)
      end
    end

    # Shared size of `roots` under a candidate variable order.
    def size_under(roots : Array(Bdd), order : Array(String)) : Int32
      m = with_order(order)
      m.node_count(transfer(roots, m).map(&.id))
    end

    # Rudell-style sifting: each variable (largest level population first)
    # is tried at every position while the others keep their relative order,
    # and left where the shared size of `roots` is smallest. Repeats while it
    # keeps improving, up to `passes` times. Returns the new manager and the
    # roots rebuilt inside it; this manager is left untouched.
    def sift(roots : Array(Bdd), passes : Int32 = 2, max_growth : Float64 = 2.0) : {Manager, Array(Bdd)}
      order = var_order
      best = node_count(roots.map(&.id))
      passes.times do
        improved = false
        population(roots).each do |name|
          rest = order - [name]
          cur_best, cur_order = best, order
          (0..rest.size).each do |pos|
            cand = rest.dup.insert(pos, name)
            next if cand == order
            s = size_under(roots, cand)
            next if s > best * max_growth
            if s < cur_best
              cur_best, cur_order = s, cand
            end
          end
          if cur_best < best
            best, order, improved = cur_best, cur_order, true
          end
        end
        break unless improved
      end
      m = with_order(order)
      {m, transfer(roots, m)}
    end

    # Variables ordered by how many nodes test them (most first).
    private def population(roots : Array(Bdd)) : Array(String)
      counts = Hash(Int32, Int32).new(0)
      seen = Set(Int32).new
      stack = roots.map(&.id)
      until stack.empty?
        n = stack.pop
        next if terminal?(n) || !seen.add?(n)
        counts[var_of(n)] += 1
        stack << @low[n] << @high[n]
      end
      (0...num_vars).to_a.sort_by! { |v| {-counts[v], v} }.map { |v| @names[v] }
    end
  end
end
