class Mare::Compiler::Infer
  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    
    abstract def resolve!(infer : Infer) : MetaType
    abstract def within_domain!(
      infer : Infer,
      pos : Source::Pos,
      constraint : MetaType,
    )
  end
  
  class Fixed < Info
    property inner : MetaType
    
    def initialize(@pos, @inner)
    end
    
    def resolve!(infer : Infer)
      @inner
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      return if @inner.within_constraints?([constraint])
      
      Error.at self,
        "This type is outside of a constraint: #{@inner.show_type}",
        [{pos, constraint.show}]
    end
  end
  
  class Self < Info
    property inner : MetaType
    property domain_constraints : Array(Tuple(Source::Pos, MetaType))
    
    def initialize(@pos, @inner)
      @domain_constraints = [] of Tuple(Source::Pos, MetaType)
    end
    
    def resolve!(infer : Infer)
      @inner
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      @domain_constraints << {pos, constraint}
      
      return if @inner.within_constraints?([constraint])
      
      Error.at self,
        "This type is outside of a constraint: #{@inner.show_type}",
        [{pos, constraint.show}]
    end
  end
  
  class Literal < Info
    @domain : MetaType
    @domain_constraints : Array(MetaType)
    
    def initialize(@pos, possible : Enumerable(Program::Type))
      possible = possible.map { |defn| MetaType.new(defn) }
      @domain = MetaType.new_union(possible)
      @domain_constraints = [MetaType.new_union(possible).cap("val")]
      @pos_list = [@pos] of Source::Pos
    end
    
    def resolve!(infer : Infer)
      if @domain.unsatisfiable?
        Error.at self,
          "This value's type is unresolvable due to conflicting constraints",
          @pos_list.zip(@domain_constraints.map(&.show))
      end
      
      if !@domain.singular?
        Error.at self,
          "This value couldn't be inferred as a single concrete type",
          @pos_list.zip(@domain_constraints.map(&.show))
      end
      
      @domain
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      @domain = @domain.intersect(constraint).simplify # TODO: maybe simplify just once at the end?
      @domain_constraints << constraint
      @pos_list << pos
      
      return unless @domain.unsatisfiable?
      
      Error.at self,
        "This value's type is unresolvable due to conflicting constraints",
        @pos_list.zip(@domain_constraints.map(&.show))
    end
  end
  
  class Local < Info # TODO: dedup implementation with Field
    @explicit : MetaType?
    @explicit_pos : Source::Pos?
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    def resolve!(infer : Infer)
      return @explicit.not_nil! if @explicit
      
      if @upstream != 0
        infer[@upstream].resolve!(infer)
      else
        Error.at self, "This needs an explicit type; it could not be inferred"
      end
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream != 0
      
      @explicit = explicit
      @explicit_pos = explicit_pos
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      if @explicit
        if !@explicit.not_nil!.within_constraints?([constraint])
          Error.at self,
            "This type is outside of a constraint: #{@explicit.try(&.show_type)}",
            [{pos, constraint.show}]
        else
          return # explicit was okay, and we ignore upstream
        end
      end
      
      infer[@upstream].within_domain!(infer, pos, constraint)
    end
    
    def assign(infer : Infer, tid : TID)
      infer[tid].within_domain!(
        infer,
        @explicit_pos.not_nil!,
        @explicit.not_nil!
      ) if @explicit
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Field < Info # TODO: dedup implementation with Local
    @explicit : MetaType?
    @explicit_pos : Source::Pos?
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    def resolve!(infer : Infer)
      return @explicit.not_nil! if @explicit
      
      if @upstream != 0
        infer[@upstream].resolve!(infer)
      else
        Error.at self, "This needs an explicit type; it could not be inferred"
      end
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream != 0
      
      @explicit = explicit
      @explicit_pos = explicit_pos
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      if @explicit
        if !@explicit.not_nil!.within_constraints?([constraint])
          Error.at self,
            "This type is outside of a constraint: #{@explicit.try(&.show_type)}",
            [{pos, constraint.show}]
        else
          return # explicit was okay, and we ignore upstream
        end
      end
      
      infer[@upstream].within_domain!(infer, pos, constraint)
    end
    
    def assign(infer : Infer, tid : TID)
      infer[tid].within_domain!(
        infer,
        @explicit_pos.not_nil!,
        @explicit.not_nil!
      ) if @explicit
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Param < Info
    @explicit : MetaType?
    @explicit_pos : Source::Pos?
    @downstreamed : MetaType?
    @downstreamed_pos : Source::Pos?
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    private def already_resolved! : MetaType
    end
    
    def resolve!(infer : Infer) : MetaType
      return @explicit.not_nil! unless @explicit.nil?
      return infer[@upstream].resolve!(infer) unless @upstream == 0
      return @downstreamed.not_nil! unless @downstreamed.nil?
      
      Error.at self,
        "This parameter's type was not specified and couldn't be inferred"
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "already have downstreams" if @downstreamed
      raise "already have an upstream" if @upstream != 0
      
      @explicit = explicit
      @explicit_pos = explicit_pos
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      if @explicit && !@explicit.not_nil!.within_constraints?([constraint])
        Error.at self,
          "This type is outside of a constraint: #{@explicit.try(&.show_type)}",
          [{pos, constraint.show}]
      end
      
      @downstreamed_pos ||=pos
      ds = @downstreamed
      if ds
        @downstreamed = ds.intersect(constraint).simplify # TODO: maybe simplify just once at the end?
      else
        @downstreamed = constraint
      end
      
      infer[@upstream].within_domain!(infer, pos, constraint) if @upstream != 0
    end
    
    def verify_arg(infer : Infer, arg_infer : Infer, arg_tid : TID)
      arg = arg_infer[arg_tid]
      arg.within_domain!(arg_infer, @pos, resolve!(infer))
    end
    
    def assign(infer : Infer, tid : TID)
      infer[tid].within_domain!(
        infer,
        @explicit_pos.not_nil!,
        @explicit.not_nil!
      ) if @explicit
      
      infer[tid].within_domain!(
        infer,
        @downstreamed_pos.not_nil!,
        @downstreamed.not_nil!
      ) if @downstreamed
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Choice < Info
    getter clauses : Array(TID)
    
    def initialize(@pos, @clauses)
    end
    
    def resolve!(infer : Infer)
      MetaType.new_union(clauses.map { |tid| infer[tid].resolve!(infer) })
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      clauses.each { |tid| infer[tid].within_domain!(infer, pos, constraint) }
    end
  end
  
  class TypeCondition < Info
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine_tid : TID
    getter refine_type : MetaType
    
    def initialize(@pos, @bool, @refine_tid, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end
    
    def resolve!(infer : Infer)
      @bool
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      return if @bool.within_constraints?([constraint])
      
      Error.at self,
        "This type is outside of a constraint: #{@bool.show_type}",
        [{pos, constraint.show}]
    end
  end
  
  class Refinement < Info
    getter refine_tid : TID
    getter refine_type : MetaType
    
    def initialize(@pos, @refine_tid, @refine_type)
    end
    
    def resolve!(infer : Infer)
      infer[@refine_tid].resolve!(infer).intersect(@refine_type)
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      return if resolve!(infer).within_constraints?([constraint])
      
      Error.at self,
        "This type is outside of a constraint: #{@refine_type.show_type}",
        [{pos, constraint.show}]
    end
  end
  
  class FromCall < Info
    getter lhs : TID
    getter member : String
    getter args : Array(TID)
    @ret : MetaType?
    @ret_pos : Source::Pos?
    
    def initialize(@pos, @lhs, @member, @args)
      @domain_constraints = [] of MetaType
      @pos_list = [] of Source::Pos
    end
    
    def resolve!(infer : Infer)
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end
    
    def within_domain!(infer : Infer, pos : Source::Pos, constraint : MetaType)
      @domain_constraints << constraint
      @pos_list << pos
      verify_constraints! if @ret
    end
    
    def set_return(ret_pos : Source::Pos, ret : MetaType)
      @ret_pos = ret_pos
      @ret = ret
      verify_constraints!
    end
    
    private def verify_constraints!
      ret = @ret.not_nil!
      return if ret.within_constraints?(@domain_constraints)
      
      Error.at self, "This return value is outside of its constraints",
        @pos_list.zip(@domain_constraints.map(&.show)).push(
          {@ret_pos.not_nil!, "but it had a return type of #{ret.show_type}"})
    end
  end
end