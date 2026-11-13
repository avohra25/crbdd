module CrBDD
  class Manager
    # Existential quantification: exists vars . f
    def exists(f : Int32, vars : Enumerable(Int32)) : Int32
      levels = levels_of(vars)
      return f if levels.empty?
      deepest = levels.max
      memo = {} of Int32 => Int32
      exists_rec(f, levels, deepest, memo)
    end

    # Universal quantification: forall vars . f  ==  !exists vars . !f
    def forall(f : Int32, vars : Enumerable(Int32)) : Int32
      self.not(exists(self.not(f), vars))
    end

    # Relational product: exists vars . (f & g), without building f & g.
    # This is the workhorse of symbolic image computation.
    def and_exists(f : Int32, g : Int32, vars : Enumerable(Int32)) : Int32
      levels = levels_of(vars)
      return self.and(f, g) if levels.empty?
      memo = {} of {Int32, Int32} => Int32
      ex_memo = {} of Int32 => Int32
      and_exists_rec(f, g, levels, levels.max, memo, ex_memo)
    end

    # Simultaneously substitutes variables: `mapping` maps var => var.
    # Implemented with compose through fresh functions, so any permutation
    # (including swaps) is handled correctly.
    def rename(f : Int32, mapping : Hash(Int32, Int32)) : Int32
      subst = {} of Int32 => Int32
      mapping.each do |from, to|
        check_var(from)
        check_var(to)
        subst[@level_of_var[from]] = mk(@level_of_var[to], FALSE_ID, TRUE_ID)
      end
      memo = {} of Int32 => Int32
      vector_compose(f, subst, memo)
    end

    # Substitutes a function for each variable simultaneously.
    def vector_compose(f : Int32, subst : Hash(Int32, Int32), memo : Hash(Int32, Int32)) : Int32
      return f if terminal?(f)
      memo[f]? || begin
        lvl = @level[f]
        lo = vector_compose(@low[f], subst, memo)
        hi = vector_compose(@high[f], subst, memo)
        sel = subst[lvl]? || mk(lvl, FALSE_ID, TRUE_ID)
        memo[f] = ite(sel, hi, lo)
      end
    end

    private def levels_of(vars : Enumerable(Int32)) : Set(Int32)
      set = Set(Int32).new
      vars.each { |v| check_var(v); set << @level_of_var[v] }
      set
    end

    private def exists_rec(f, levels, deepest, memo) : Int32
      return f if terminal?(f) || @level[f] > deepest
      memo[f]? || begin
        lvl = @level[f]
        lo = exists_rec(@low[f], levels, deepest, memo)
        r = if levels.includes?(lvl)
              lo == TRUE_ID ? TRUE_ID : self.or(lo, exists_rec(@high[f], levels, deepest, memo))
            else
              mk(lvl, lo, exists_rec(@high[f], levels, deepest, memo))
            end
        memo[f] = r
      end
    end

    private def and_exists_rec(f, g, levels, deepest, memo, ex_memo) : Int32
      return FALSE_ID if f == FALSE_ID || g == FALSE_ID
      return TRUE_ID if f == TRUE_ID && g == TRUE_ID
      return exists_rec(g, levels, deepest, ex_memo) if f == TRUE_ID || f == g
      return exists_rec(f, levels, deepest, ex_memo) if g == TRUE_ID
      f, g = g, f if f > g # commutative: one cache entry per pair
      key = {f, g}
      if r = memo[key]?
        return r
      end
      top = Math.min(@level[f], @level[g])
      if top > deepest
        r = self.and(f, g)
      else
        f0, f1 = cofactors(f, top)
        g0, g1 = cofactors(g, top)
        r0 = and_exists_rec(f0, g0, levels, deepest, memo, ex_memo)
        r = if levels.includes?(top)
              r0 == TRUE_ID ? TRUE_ID : self.or(r0, and_exists_rec(f1, g1, levels, deepest, memo, ex_memo))
            else
              mk(top, r0, and_exists_rec(f1, g1, levels, deepest, memo, ex_memo))
            end
      end
      memo[key] = r
    end
  end

  struct Bdd
    def exists(vars : Enumerable(String | Int32)) : Bdd
      wrap(@manager.exists(@id, vars.map { |v| index(v) }))
    end

    def exists(*vars : String | Int32) : Bdd
      exists(vars.to_a)
    end

    def forall(vars : Enumerable(String | Int32)) : Bdd
      wrap(@manager.forall(@id, vars.map { |v| index(v) }))
    end

    def forall(*vars : String | Int32) : Bdd
      forall(vars.to_a)
    end

    def and_exists(other : Bdd, vars : Enumerable(String | Int32)) : Bdd
      same_manager!(other)
      wrap(@manager.and_exists(@id, other.id, vars.map { |v| index(v) }))
    end

    def rename(mapping : Hash(String, String)) : Bdd
      wrap(@manager.rename(@id, mapping.to_h { |k, v| {@manager.var_index(k), @manager.var_index(v)} }))
    end
  end
end
