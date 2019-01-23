class Mare::Program
  # TODO: add Package delineation here
  getter types
  
  property! layout : Compiler::Layout
  property! code_gen : Compiler::CodeGen
  
  def initialize
    @types = [] of Type
  end
  
  def find_type!(type_name)
    @types.find { |t| t.ident.value == type_name }.not_nil!
  end
  
  def find_func!(type_name, func_name)
    find_type!(type_name).find_func!(func_name)
  end
  
  class Type
    enum Kind
      Actor
      Class
      Primitive
      Numeric
      FFI
    end
    
    getter kind : Kind
    getter ident : AST::Identifier
    getter properties
    getter functions
    
    property! layout : Compiler::Layout
    
    def initialize(@kind, @ident)
      @properties = [] of Property
      @functions = [] of Function
    end
    
    def find_func!(func_name)
      @functions.find { |f| f.ident.value == func_name }.not_nil!
    end
    
    def is_concrete?
      case kind
      when Kind::Actor, Kind::Class, Kind::Primitive, Kind::Numeric, Kind::FFI
        true
      else false
      end
    end
    
    def is_instantiable?
      case kind
      when Kind::Actor, Kind::Class
        true
      else false
      end
    end
  end
  
  class Property
    getter ident : AST::Identifier
    getter ret : AST::Identifier
    getter body : AST::Group
    
    def initialize(@ident, @ret, @body)
    end
  end
  
  class Function
    getter ident : AST::Identifier
    getter params : AST::Group?
    getter ret : AST::Identifier?
    getter body : AST::Group?
    
    property! refer : Compiler::Refer
    property! infer : Compiler::Infer
    
    KNOWN_TAGS = [
      :constructor,
    ]
    
    def initialize(@ident, @params, @ret, @body)
      @tags = Set(Symbol).new
    end
    
    def add_tag(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.add(tag)
    end
    
    def has_tag?(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.includes?(tag)
    end
  end
end
