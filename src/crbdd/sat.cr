module CrBDD
  class Manager
    # Number of satisfying assignments over the first `nvars` levels
    # (by default all declared variables). Exact, using BigInt.
    def satcount(f : Int32, nvars : Int32 = num_vars) : BigInt
      memo = {} of Int32 => BigInt
      count = satcount_rec(f, nvars, memo)
      count << depth(f, nvars)
    end

    private def depth(n : Int32, nvars : Int32) : Int32
      terminal?(n) ? nvars : @level[n]
    end

    # Models of the sub-diagram at n over levels depth(n)...nvars.
    private def satcount_rec(n, nvars, memo) : BigInt
      return BigInt.new(0) if n == FALSE_ID
      return BigInt.new(1) if n == TRUE_ID
      memo[n]? || begin
        lvl = @level[n]
        raise Error.new("satcount: node depends on variable below nvars") if lvl >= nvars
        lo, hi = @low[n], @high[n]
        c = (satcount_rec(lo, nvars, memo) << (depth(lo, nvars) - lvl - 1)) +
            (satcount_rec(hi, nvars, memo) << (depth(hi, nvars) - lvl - 1))
        memo[n] = c
      end
    end

    # One satisfying partial assignment (a path to TRUE), or nil if f is
    # unsatisfiable. Variables missing from the result are don't-cares.
    def any_sat(f : Int32) : Hash(Int32, Bool)?
      return nil if f == FALSE_ID
      cube = {} of Int32 => Bool
      n = f
      until terminal?(n)
        if @low[n] != FALSE_ID
          cube[var_of(n)] = false
          n = @low[n]
        else
          cube[var_of(n)] = true
          n = @high[n]
        end
      end
      cube
    end

    # Yields every path to TRUE as a cube (partial assignment). The cubes are
    # disjoint and together cover exactly the models of f.
    def each_cube(f : Int32, & : Hash(Int32, Bool) ->) : Nil
      stack = [{f, {} of Int32 => Bool}]
      until stack.empty?
        n, cube = stack.pop
        next if n == FALSE_ID
        if n == TRUE_ID
          yield cube
          next
        end
        v = var_of(n)
        stack << {@high[n], cube.merge({v => true})}
        stack << {@low[n], cube.merge({v => false})}
      end
    end

    # Yields every total assignment over `vars` (default: all variables)
    # satisfying f. `vars` must include the support of f.
    def each_model(f : Int32, vars : Array(Int32) = (0...num_vars).to_a, & : Hash(Int32, Bool) ->) : Nil
      missing = support(f) - vars
      raise Error.new("each_model: vars must cover the support") unless missing.empty?
      each_cube(f) do |cube|
        free = vars.reject { |v| cube.has_key?(v) }
        (0_u64...(1_u64 << free.size)).each do |bits|
          model = cube.dup
          free.each_with_index { |v, i| model[v] = bits.bit(i) == 1 }
          yield model
        end
      end
    end
  end

  struct Bdd
    def satcount : BigInt
      @manager.satcount(@id)
    end

    # A satisfying cube keyed by variable name, or nil.
    def any_sat : Hash(String, Bool)?
      @manager.any_sat(@id).try &.to_h { |v, b| {@manager.name_of(v), b} }
    end

    def cubes : Array(Hash(String, Bool))
      out = [] of Hash(String, Bool)
      @manager.each_cube(@id) { |c| out << c.to_h { |v, b| {@manager.name_of(v), b} } }
      out
    end

    def each_model(vars : Array(String)? = nil, & : Hash(String, Bool) ->) : Nil
      idx = vars ? vars.map { |n| @manager.var_index(n) } : (0...@manager.num_vars).to_a
      @manager.each_model(@id, idx) { |m| yield m.to_h { |v, b| {@manager.name_of(v), b} } }
    end
  end
end
