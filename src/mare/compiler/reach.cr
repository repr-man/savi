##
# The purpose of the Reach pass is to [TODO: justify and clean up this pass].
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the program level.
# This pass produces output state at the type/meta-type level.
#
class Mare::Compiler::Reach < Mare::AST::Visitor
  class Ref
    def initialize(@meta_type : Infer::MetaType)
    end
    
    def show_type
      @meta_type.show_type
    end
    
    def is_tuple?
      false # TODO
    end
    
    def is_intersect?
      false # TODO
    end
    
    def is_union?
      !@meta_type.singular? # TODO: distinguish from tuple and intersect
    end
    
    def is_abstract?
      is_intersect? || is_union? || !@meta_type.single!.defn.is_concrete?
    end
    
    def is_concrete?
      !is_abstract?
    end
    
    def is_value?
      is_tuple? || (singular? && single!.has_tag?(:no_desc))
    end
    
    def singular?
      @meta_type.singular?
    end
    
    def single!
      @meta_type.single!
    end
    
    def any_callable_defn_for(name) : Infer::ReifiedType
      @meta_type.any_callable_func_defn_type(name).not_nil!
    end
    
    def tuple_count
      0 # TODO
    end
    
    def is_none!
      # TODO: better reach the one true None instead of a namespaced impostor?
      raise "#{self} is not None" unless single!.defn.ident.value == "None"
    end
    
    @llvm_use_type : Symbol?
    def llvm_use_type : Symbol
      (@llvm_use_type ||= \
      if is_tuple?
        :tuple
      elsif !singular?
        :object_ptr
      else
        defn = single!.defn
        if defn.has_tag?(:numeric)
          if defn.const_bool("is_floating_point")
            case defn.const_u64("bit_width")
            when 32 then :f32
            when 64 then :f64
            else raise NotImplementedError.new(defn.inspect)
            end
          else
            case defn.const_u64("bit_width")
            when 1 then :i1
            when 8 then :i8
            when 32 then :i32
            when 64 then :i64
            else raise NotImplementedError.new(defn.inspect)
            end
          end
        else
          # TODO: don't special-case this in the compiler?
          case defn.ident.value
          when "CString" then :ptr
          else
            :struct_ptr
          end
        end
      end
      ).not_nil!
    end
    
    def llvm_mem_type : Symbol
      if llvm_use_type == :i1
        # TODO: use :i32 on Darwin PPC32? (see ponyc's gentype.c:283)
        :i8
      else
        llvm_use_type
      end
    end
  end
  
  class Def
    getter! desc_id : Int32
    getter fields : Array({String, Ref})
    
    def initialize(@reified : Infer::ReifiedType, reach : Reach, @fields)
      @desc_id =
        if is_numeric?
          reach.next_numeric_id
        elsif is_abstract?
          reach.next_trait_id
        elsif is_tuple?
          reach.next_tuple_id
        else
          reach.next_object_id
        end
    end
    
    def inner
      @reified
    end
    
    def refer(ctx)
      ctx.refer[@reified.defn]
    end
    
    def program_type
      @reified.defn
    end
    
    def llvm_name : String
      # TODO: guarantee global uniqueness
      @reified.show_type
    end
    
    def abi_size : Int32
      # TODO: move final number calculation to CodeGen side (LLVMABISizeOfType)
      # TODO: cross-platform
      if @reified.defn.has_tag?(:no_desc)
        16 # we use the boxed size here
      elsif !@reified.defn.has_tag?(:allocated)
        8 # the size of just a descriptor pointer
      elsif @reified.defn.has_tag?(:actor)
        256 # TODO: handle fields
      else
        64 # TODO: handle fields
      end
    end
    
    def field_count
      0 # TODO
    end
    
    def field_offset : Int32
      return 0 if field_count == 0
      
      # TODO: move final number calculation to CodeGen side (LLVMOffsetOfElement)
      offset = 0
      offset += 8 unless @reified.defn.has_tag?(:no_desc)
      offset += 8 if @reified.defn.has_tag?(:actor)
      offset
    end
    
    def has_desc?
      !@reified.defn.has_tag?(:no_desc)
    end
    
    def has_allocation?
      @reified.defn.has_tag?(:allocated)
    end
    
    def has_state?
      @reified.defn.has_tag?(:allocated) ||
      @reified.defn.has_tag?(:numeric)
    end
    
    def has_actor_pad?
      @reified.defn.has_tag?(:actor)
    end
    
    def is_actor?
      @reified.defn.has_tag?(:actor)
    end
    
    def is_abstract?
      @reified.defn.has_tag?(:abstract)
    end
    
    def is_tuple?
      false
    end
    
    def is_numeric?
      @reified.defn.has_tag?(:numeric)
    end
    
    def is_floating_point_numeric?
      is_numeric? && @reified.defn.const_bool("is_floating_point")
    end
    
    def is_signed_numeric?
      is_numeric? && @reified.defn.const_bool("is_signed")
    end
    
    def bit_width
      @reified.defn.const_u64("bit_width").to_i32
    end
    
    def each_function
      @reified.defn.functions.each
    end
    
    def as_ref : Ref
      Ref.new(Infer::MetaType.new(@reified))
    end
  end
  
  property! infer : Infer::ForFunc
  
  def initialize
    @refs = Hash(Infer::MetaType, Ref).new
    @defs = Hash(Infer::ReifiedType, Def).new
    @seen_funcs = Set(Program::Function).new
  end
  
  def run(ctx)
    # Reach functions called starting from the entrypoint of the program.
    env = ctx.program.find_type!("Env")
    handle_func(ctx, ctx.infer.reified_type(ctx, env), env.find_func!("new"))
    main = ctx.program.find_type!("Main")
    handle_func(ctx, ctx.infer.reified_type(ctx, main), main.find_func!("new"))
  end
  
  def handle_func(ctx, rt, func)
    # Skip this function if we've already seen it.
    return if @seen_funcs.includes?(func)
    @seen_funcs.add(func)
    
    # Get each infer instance associated with this function.
    ctx.infer.infers_for(func).each do |infer|
      # Reach all type references seen by this function.
      infer.each_meta_type do |meta_type|
        handle_type_ref(ctx, meta_type)
      end
      
      # Reach all functions called by this function.
      infer.each_called_func.each do |called_rt, called_func|
        handle_func(ctx, called_rt, called_func)
      end
      
      # Reach all functions that have the same name as this function and
      # belong to a type that is a subtype of this one.
      # TODO: can we avoid doing this for unreachable types? It seems nontrivial.
      ctx.infer.completely_reified_types.each do |other_rt|
        next if rt == other_rt
        other_func = other_rt.defn.find_func?(func.ident.value)
        
        handle_func(ctx, other_rt, other_func) \
          if other_func && infer.is_subtype?(other_rt, rt)
      end
    end
  end
  
  def handle_field(ctx, rt, func) : {String, Ref}
    # Reach the metatype of the field.
    ref = nil
    ctx.infer.infers_for(func).each do |infer|
      next unless rt == infer.reified.type
      ref = infer.resolve(func.ident)
      handle_type_ref(ctx, ref)
    end
    ref.not_nil!
    
    # Handle the field as if it were a function.
    handle_func(ctx, rt, func)
    
    # Return the Ref instance for this meta type.
    {func.ident.value, @refs[ref.not_nil!]}
  end
  
  def handle_type_ref(ctx, meta_type : Infer::MetaType)
    # Skip this type ref if we've already seen it.
    return if @refs.has_key?(meta_type)
    
    # First, reach any type definitions referenced by this type reference.
    meta_type.each_reachable_defn.each { |t| handle_type_def(ctx, t) }
    
    # Now, save a Ref instance for this meta type.
    @refs[meta_type] = Ref.new(meta_type)
  end
  
  def handle_type_def(ctx, rt : Infer::ReifiedType)
    # Skip this type def if we've already seen it.
    return if @defs.has_key?(rt)
    
    # Skip this type def if it's not completely reified.
    return unless rt.is_complete?
    
    # Reach all fields, regardless of if they were actually used.
    # This is important for consistency of memory layout purposes.
    fields = rt.defn.functions.select(&.has_tag?(:field)).map do |f|
      handle_field(ctx, rt, f)
    end
    
    # Now, save a Def instance for this program type.
    @defs[rt] = Def.new(rt, self, fields)
  end
  
  # Traits are numbered 0, 1, 2, 3, 4, ...
  @trait_count = 0
  def next_trait_id
    @trait_count
    .tap { @trait_count += 1 }
  end
  
  # Objects are numbered 0, 3, 5, 7, 9, ...
  @object_count = 0
  def next_object_id
    (@object_count * 2) + 1
    .tap { @object_count += 1 }
  end
  
  # Numerics are numbered 0, 4, 8, 12, 16, ...
  @numeric_count = 0
  def next_numeric_id
    @numeric_count * 4
    .tap { @numeric_count += 1 }
  end
  
  # Tuples are numbered 2, 6, 10, 14, 18, ...
  @tuple_count = 0
  def next_tuple_id
    (@tuple_count * 4) + 2
    .tap { @tuple_count += 1 }
  end
  
  def [](meta_type : Infer::MetaType)
    @refs[meta_type]
  end
  
  def [](rt : Infer::ReifiedType)
    @defs[rt]
  end
  
  def reached_func?(program_func : Program::Function)
    @seen_funcs.includes?(program_func)
  end
  
  def each_type_def
    @defs.each_value
  end
end
