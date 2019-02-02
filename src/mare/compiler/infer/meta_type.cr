class Mare::Compiler::Infer::MetaType
  # TODO: represent in DNF or CNF form, to support not just union types but
  # also intersections and exclusions in a formally reasonable way.
  @union : Set(Program::Type)
  
  def initialize(union : Enumerable(Program::Type))
    case union
    when Set(Program::Type) then @union = union
    else @union = union.to_set
    end
  end
  
  def self.new_union(types : Iterable(MetaType))
    new(types.reduce(Set(Program::Type).new) { |all, o| all | o.defns })
  end
  
  # TODO: remove this method:
  def defns
    @union
  end
  
  def empty?
    @union.empty?
  end
  
  def singular?
    @union.size == 1
  end
  
  def single!
    raise "not singular: #{show_type}" unless singular?
    @union.first
  end
  
  def intersect(other : MetaType)
    # TODO: verify total correctness of this algorithm and its use.
    new_union = Set(Program::Type).new
    other.defns.each do |defn|
      if self.defns.includes?(defn)
        new_union.add(defn)
      elsif self.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
        new_union.add(defn)
      end
    end
    self.defns.each do |defn|
      if new_union.includes?(defn)
        # skip this - it's already there
      elsif other.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
        new_union.add(defn)
      end
    end
    
    MetaType.new(new_union)
  end
  
  # Return true if this MetaType is a subtype of the other MetaType.
  def <(other); subtype_of?(other) end
  def subtype_of?(other : MetaType)
    self.defns.all? do |defn|
      other.defns.includes?(defn) ||
      other.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
    end
  end
  
  # A cache of assumptions to prevent mutual recursion when checking subtypes.
  @@defn_subtype_assumes = Set(Tuple(Program::Type, Program::Type)).new
  
  # Return true if the left type satisfies the requirements of the right type.
  def self.is_l_defn_sub_r_defn?(l : Program::Type, r : Program::Type)
    # TODO: for each return false, carry info about why it was false?
    # Maybe we only want to go to the trouble of collecting this info
    # when it is requested by the caller, so as not to slow the base case.
    
    # If these are literally the same type, we can trivially return true.
    return true if r.same? l
    
    # We don't have subtyping of concrete types (i.e. class inheritance),
    # so we know l can't possibly be a subtype of r if r is concrete.
    # Note that by the time we've reached this line, we've already
    # determined that the two types are not identical, so we're only
    # concerned with structural subtyping from here on.
    return false unless r.has_tag?(:abstract)
    
    # TODO: memoize the results of success/failure of the following steps,
    # so we can skip them if we've already done a comparison for l and r.
    # This could also be preserved for use in a selector coloring pass later.
    
    # If we have a standing assumption that l is a subtype of r, return true.
    # Otherwise, move forward with the check and add such an assumption.
    # This is done to prevent infinite recursion in the typechecking.
    # The assumption could turn out to be wrong, but no matter what,
    # we don't gain anything by trying to check something that we're
    # already in the middle of checking some way down the call stack.
    return true if @@defn_subtype_assumes.includes?({l, r})
    @@defn_subtype_assumes.add({l, r})
    
    # A type only matches an interface if all functions match that interface.
    result =
      r.functions.all? do |rf|
        # Hygienic functions are not considered to be real functions for the
        # sake of structural subtyping, so they don't have to be fulfilled.
        next if rf.has_tag?(:hygienic)
        
        # The structural comparison fails if a required method is missing.
        next unless l.has_func?(rf.ident.value)
        lf = l.find_func!(rf.ident.value)
        
        # Just asserting; we expect has_func? and find_func! to prevent this.
        raise "found hygienic function" if lf.has_tag?(:hygienic)
        
        is_l_func_sub_r_func?(l, r, lf, rf)
      end
    
    # Remove our standing assumption about l being a subtype of r -
    # we have our answer and have no more need for this recursion guard.
    @@defn_subtype_assumes.delete({l, r})
    
    result
  end
  
  # Return true if the left func satisfies the requirements of the right func.
  def self.is_l_func_sub_r_func?(
    l : Program::Type, r : Program::Type,
    lf : Program::Function, rf : Program::Function,
  )
    # Get the Infer instance for both l and r functions, to compare them.
    l_infer = Infer.from(l, lf)
    r_infer = Infer.from(r, rf)
    
    # A constructor can only match another constructor, and
    # a constant can only match another constant.
    return false if lf.has_tag?(:constructor) != rf.has_tag?(:constructor)
    return false if lf.has_tag?(:constant) != rf.has_tag?(:constant)
    
    # Must have the same number of parameters.
    return false if lf.param_count != rf.param_count
    
    # TODO: Check receiver rcap (see ponyc subtype.c:240)
    # Covariant receiver rcap for constructors.
    # Contravariant receiver rcap for functions and behaviours.
    
    # Covariant return type.
    return false unless \
      l_infer.resolve(l_infer.ret_tid) < r_infer.resolve(r_infer.ret_tid)
    
    # Contravariant parameter types.
    lf.params.try do |l_params|
      rf.params.try do |r_params|
        l_params.terms.zip(r_params.terms).each do |(l_param, r_param)|
          return false unless \
            r_infer.resolve(r_param) < l_infer.resolve(l_param)
        end
      end
    end
    
    true
  end
  
  def each_type_def : Iterator(Program::Type)
    @union.each
  end
  
  def ==(other)
    @union == other.defns
  end
  
  def hash
    @union.hash
  end
  
  def show
    "it must be a subtype of #{show_type}"
  end
  
  def show_type
    "(#{@union.map(&.ident).map(&.value).join(" | ")})"
  end
  
  def within_constraints?(list : Iterable(MetaType))
    # TODO: verify total correctness of this algorithm and its use.
    unconstrained = true
    intersected = list.reduce self do |reduction, constraint|
      unconstrained = false
      reduction.intersect(constraint)
    end
    unconstrained || !intersected.empty?
  end
end