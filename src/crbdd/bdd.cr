module CrBDD
  # A handle on a node: a boolean function owned by a `Manager`.
  # Handles are cheap value types; equality is function equality.
  struct Bdd
    getter manager : Manager
    getter id : Int32

    def initialize(@manager : Manager, @id : Int32)
    end

    def true? : Bool
      @id == Manager::TRUE_ID
    end

    def false? : Bool
      @id == Manager::FALSE_ID
    end

    def constant? : Bool
      @manager.terminal?(@id)
    end

    # Satisfiable (not identically false)?
    def satisfiable? : Bool
      !false?
    end

    # Tautology (identically true)?
    def tautology? : Bool
      true?
    end

    def ==(other : Bdd) : Bool
      same_manager!(other)
      @id == other.id
    end

    def hash(hasher)
      hasher = @id.hash(hasher)
      hasher
    end

    def ~ : Bdd
      wrap(@manager.not(@id))
    end

    def not : Bdd
      ~self
    end

    def &(other : Bdd) : Bdd
      same_manager!(other)
      wrap(@manager.and(@id, other.id))
    end

    def |(other : Bdd) : Bdd
      same_manager!(other)
      wrap(@manager.or(@id, other.id))
    end

    def ^(other : Bdd) : Bdd
      same_manager!(other)
      wrap(@manager.xor(@id, other.id))
    end

    def implies(other : Bdd) : Bdd
      same_manager!(other)
      wrap(@manager.imp(@id, other.id))
    end

    def iff(other : Bdd) : Bdd
      same_manager!(other)
      wrap(@manager.iff(@id, other.id))
    end

    # self ? then_ : else_
    def ite(then_ : Bdd, else_ : Bdd) : Bdd
      same_manager!(then_)
      same_manager!(else_)
      wrap(@manager.ite(@id, then_.id, else_.id))
    end

    # Does self imply other (self <= other pointwise)?
    def <=(other : Bdd) : Bool
      implies(other).true?
    end

    def restrict(v : Int32 | String, value : Bool) : Bdd
      wrap(@manager.restrict(@id, index(v), value))
    end

    def restrict(assignment : Hash(String, Bool)) : Bdd
      wrap(@manager.restrict(@id, assignment.to_h { |k, b| {@manager.var_index(k), b} }))
    end

    def restrict(assignment : Hash(Int32, Bool)) : Bdd
      wrap(@manager.restrict(@id, assignment))
    end

    def compose(v : Int32 | String, g : Bdd) : Bdd
      same_manager!(g)
      wrap(@manager.compose(@id, index(v), g.id))
    end

    # Evaluates under a total assignment (array indexed by variable, or names).
    def eval(assignment : Indexable(Bool)) : Bool
      @manager.eval(@id, assignment)
    end

    def eval(assignment : Hash(String, Bool)) : Bool
      arr = Array(Bool).new(@manager.num_vars, false)
      assignment.each { |k, b| arr[@manager.var_index(k)] = b }
      @manager.eval(@id, arr)
    end

    # Number of internal nodes.
    def size : Int32
      @manager.node_count([@id])
    end

    # Names of the variables this function depends on, in order.
    def support : Array(String)
      @manager.support(@id).map { |v| @manager.name_of(v) }
    end

    def inspect(io : IO) : Nil
      io << "#<CrBDD::Bdd id=" << @id << " size=" << size << '>'
    end

    def to_s(io : IO) : Nil
      inspect(io)
    end

    private def wrap(id : Int32) : Bdd
      Bdd.new(@manager, id)
    end

    private def index(v : Int32 | String) : Int32
      v.is_a?(String) ? @manager.var_index(v) : v
    end

    private def same_manager!(other : Bdd) : Nil
      unless other.manager.same?(@manager)
        raise Error.new("BDDs belong to different managers")
      end
    end
  end
end
