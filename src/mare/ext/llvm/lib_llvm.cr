lib LibLLVM
  fun intptr_type_in_context = LLVMIntPtrTypeInContext(ContextRef, TargetDataRef) : TypeRef
  fun build_struct_gep = LLVMBuildStructGEP(builder : BuilderRef, pointer : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun const_named_struct = LLVMConstNamedStruct(type : TypeRef, values : ValueRef*, num_values : UInt32) : ValueRef
  fun const_inbounds_gep = LLVMConstInBoundsGEP(value : ValueRef, indices : ValueRef*, num_indices : UInt32) : ValueRef
  fun const_bit_cast = LLVMConstBitCast(value : ValueRef, to_type : TypeRef) : ValueRef
  fun set_unnamed_addr = LLVMSetUnnamedAddr(global : ValueRef, is_unnamed_addr : Int32)
  fun is_unnamed_addr = LLVMIsUnnamedAddr(global : ValueRef) : Int32
  fun parse_bitcode_in_context = LLVMParseBitcodeInContext(context : ContextRef, mem_buf : MemoryBufferRef, out_m : ModuleRef*, out_message : UInt8**) : Int32
  fun link_modules = LLVMLinkModules2 (dest : ModuleRef, src : ModuleRef) : Int32
end
