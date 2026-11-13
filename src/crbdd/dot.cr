module CrBDD
  class Manager
    # Graphviz rendering of the shared diagram rooted at `roots`.
    # Solid edges are the high (then) branch, dashed edges the low branch.
    def to_dot(roots : Hash(String, Int32), io : IO) : Nil
      io << "digraph bdd {\n"
      io << "  node [shape=circle, fontname=\"Helvetica\"];\n"
      io << "  t0 [label=\"0\", shape=box];\n  t1 [label=\"1\", shape=box];\n"
      seen = Set(Int32).new
      by_level = Hash(Int32, Array(Int32)).new { |h, k| h[k] = [] of Int32 }
      stack = roots.values.dup
      until stack.empty?
        n = stack.pop
        next if terminal?(n) || !seen.add?(n)
        by_level[@level[n]] << n
        stack << @low[n] << @high[n]
      end
      by_level.keys.sort!.each do |lvl|
        nodes = by_level[lvl].sort!
        io << "  { rank=same; "
        nodes.each { |n| io << dot_id(n) << "; " }
        io << "}\n"
        nodes.each do |n|
          io << "  " << dot_id(n) << " [label=\"" << @names[@var_at_level[lvl]].dump_unquoted << "\"];\n"
          io << "  " << dot_id(n) << " -> " << dot_id(@high[n]) << ";\n"
          io << "  " << dot_id(n) << " -> " << dot_id(@low[n]) << " [style=dashed];\n"
        end
      end
      roots.each do |name, id|
        io << "  \"root_" << name.dump_unquoted << "\" [label=\"" << name.dump_unquoted << "\", shape=plaintext];\n"
        io << "  \"root_" << name.dump_unquoted << "\" -> " << dot_id(id) << ";\n"
      end
      io << "}\n"
    end

    private def dot_id(n : Int32) : String
      terminal?(n) ? "t#{n}" : "n#{n}"
    end
  end

  struct Bdd
    def to_dot(name : String = "f") : String
      String.build { |io| @manager.to_dot({name => @id}, io) }
    end
  end
end
