class LLVM::Context
  def intptr(target_data : TargetData) : Type
    Type.new LibLLVM.intptr_type_in_context(self, target_data)
  end

  def struct_create_named(name : String) : Type
    Type.new LibLLVM.struct_create_named(self, name)
  end

  def const_inbounds_gep(type : Type, value : Value, indices : Array(Value))
    Value.new LibLLVM.const_inbounds_gep_2(type, value, indices.to_unsafe.as(LibLLVM::ValueRef*), indices.size)
  end

  def const_bit_cast(value : Value, to_type : Type)
    Value.new LibLLVM.const_bit_cast(value, to_type)
  end

  {% for name in %w(shl and lshr) %}
    def const_{{name.id}}(lhs, rhs)
      # check_value(lhs)
      # check_value(rhs)

      Value.new LibLLVM.const_{{name.id}}(lhs, rhs)
    end
  {% end %}

  # (derived from existing parse_ir method)
  def parse_bitcode(buf : MemoryBuffer)
    ret = LibLLVM.parse_bitcode_in_context(self, buf, out mod, out msg)
    if ret != 0 && msg
      raise LLVM.string_and_dispose(msg)
    end
    Module.new(mod, self)
  end
end
