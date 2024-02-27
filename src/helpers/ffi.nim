#=======================================================
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2024 Yanis Zafirópulos
#
# @file: helpers/ffi.nim
#=======================================================

# TODO(Helpers/ffi) Re-visit & re-implement the whole thing
#  Current, this "works". However, even if it works, it's not the best way to do it. Plus, we're totally limited regarding what type of functions we can "import".
#  labels: helpers, enhancement, cleanup, open discussion

when not defined(WEB):
    #=======================================
    # Libraries
    #=======================================
    
    import dynlib, os, strutils, libffi, tables

    import vm/[errors, values/value]
    import vm/globals
    #import vm/values/custom/[vlogical]

    
    #=======================================
    # List of libraries
    #=======================================

    # The most stupid hack of the century
    # but it kinda works - better than nothing!

    #=======================================
    # Helpers
    #=======================================

    proc loadLibrary*(path: string): LibHandle =
        result = loadLib(path, true)

        if result == nil:
            RuntimeError_LibraryNotLoaded(path)

    template checkRunner*(r: pointer):untyped =
        if r == nil:
            RuntimeError_LibrarySymbolNotFound(resolvedPath, meth)

    func resolveLibrary*(path: string): string =
        let (_, _, extension) = splitFile(path)
        if extension != "":
            result = path
        else:
            result = DynlibFormat % [path]
    
    func returnTypeSize(name: string): int =
        case name:
            of "cldouble": return 10
            
            of "cint64",
               "cdouble",
               "cpointer",
               "cstring",
               "cuint64":  return 8
            
            of "cint32",
               "cuint32",
               "cfloat":   return 4
            
            of "cuint16",
               "cint16":   return 2
            
            of "cint8",
               "cuint8":   return 1
            of "cvoid": return 0
            else: return -1
    
    proc returnTypeAddr(name: string): ptr Type =
        case name:
            of "cpointer", "cstring": return type_pointer.addr
            of "cldouble": return type_longdouble.addr
            of "cdouble":  return type_double.addr
            of "cfloat":   return type_float.addr
            
            of "cint64":   return type_sint64.addr
            of "cuint64":  return type_uint64.addr
            
            of "cint32":   return type_sint32.addr
            of "cuint32":  return type_uint32.addr
            
            of "cint16":   return type_sint16.addr
            of "cuint16":  return type_uint16.addr

            of "cint8":    return type_sint8.addr
            of "cuint8":   return type_uint8.addr
            of "cvoid":    return type_void.addr
            else:   return nil 
    
    func getStructFieldPtr(struct: ptr array[0..63, uint8], offset: uint): uint =
        return cast[uint](struct) + offset

    proc returnValue(val: Value) : Value =
        return if val.o.hasKey("value"): val.o["value"] else: nil

    proc addParameterFFI(p: Value, i : int ,params_cif: var ParamList, args : var ArgList,
                                            struct_values: var seq[array[0..63,uint8]], structs_elements: var seq[array[0..15, ptr Type]],struct_types: var seq[Type],
                                            literal_value: pointer | bool ) =
        when literal_value isnot bool:
            params_cif[i] = type_pointer.addr
            args[i] = literal_value
            return
        else:
            case p.kind:
                of Object:
                        let type_name = p.proto.name
                        if type_name[0] == 'c': # FIXME
                                params_cif[i] = returnTypeAddr(type_name)

                                case type_name:
                                of "cuint64", "cpointer":
                                    var cval = csize_t.new # Test it out
                                    cval[] = p.o["value"].i.csize_t
                                    args[i] = cast[ptr csize_t](cval)
                                
                                of "cint64":
                                    var cval = clonglong.new # Test it out
                                    cval[] = p.o["value"].i.clonglong
                                    args[i] = cast[ptr clonglong](cval)
                                
                                of "cint32":
                                    var cval = clong.new
                                    cval[] = p.o["value"].i.clong
                                    args[i] = cast[ptr clong](cval)
                                
                                of "cuint32":
                                    var cval = culong.new
                                    cval[] = p.o["value"].i.culong
                                    args[i] = cast[ptr culong](cval)

                                of "cfloat":
                                    var cval = cfloat.new # Test it out
                                    cval[] = p.o["value"].f.cfloat
                                    args[i] = cast[ptr cfloat](cval)
                                
                                of "cstring":
                                    var cval = cstring.new
                                    cval[] = p.o["value"].s.cstring
                                    args[i] = cast[cstring](cval)
                                
                                else:
                                    echo "Unimplemented! ", type_name
                        else:
                            if type_name.len == 0:
                                echo "WROOOONG"
                            echo type_name
                            var 
                                buffer : array[0..63, uint8] # Fake 64byte struct
                                idx = 0
                                max_size  = 0
                                full_size = 0
                                types : OrderedTable[string,int]
                                elements_buf : array[0..15, ptr Type]

                            var j = 0
                            for value in p.o.values:
                                if value.kind != Method:
                                    echo "YES"
                            # ------- Defining struct layout and type
                                    let size = returnTypeSize(value.proto.name)
                                    types[value.proto.name] = size
                                    
                                    if size > max_size: max_size = size
                                    full_size += size
                                    
                                    let address = returnTypeAddr(value.proto.name) # TODO, Add types for other structs too
                                    if address.isNil:
                                        echo "Error Type: ", value.proto.name
                                        break
                                    else:
                                        elements_buf[j] = address
                                        inc j
                                    
                                    turnIntoStruct(value,buffer,idx)
                                    idx += size
                            
                            echo buffer
                            echo elements_buf.repr

                            struct_values.add(buffer)
                            args[i] = struct_values[struct_values.high].addr
                            
                            structs_elements.add(elements_buf)
                            struct_types.add( 
                                libffi.Type(size: full_size, 
                                            alignment: max_size.uint16 , 
                                            typ: tkSTRUCT, 
                                            elements: cast[ptr ptr Type](structs_elements[structs_elements.high].addr) ) 
                                )
                            params_cif[i] = struct_types[struct_types.high].addr
                else:
                    discard
    
    proc turnIntoStruct(v: Value, buffer: var array[0..63,uint8], offset : int = 0) =
        let size = returnTypeSize(v.proto.name)
        case v.proto.name:
            of "cint64":
                let field_v = v.o["value"].i.clonglong
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..7,uint8]](field_v)[i] 
                    inc i
            of "cuint64", "cpointer":
                let field_v = v.o["value"].i.culonglong
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..7,uint8]](field_v)[i] 
                    inc i
            
            of "cdouble":
                let field_v = v.o["value"].f.cdouble
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..7,uint8]](field_v)[i] 
                    inc i
            of "cfloat":
                let field_v = v.o["value"].f.cfloat
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..3,uint8]](field_v)[i] 
                    inc i

            of "cint32":
                let field_v = v.o["value"].i.clong
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..3,uint8]](field_v)[i] 
                    inc i
            of "cuint32":
                let field_v = v.o["value"].i.culong
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..3,uint8]](field_v)[i] 
                    inc i

            of "cint16":
                let field_v = v.o["value"].i.cshort
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..1,uint8]](field_v)[i] 
                    inc i
            of "cuint16":
                let field_v = v.o["value"].i.cshort
                var i = 0
                while i < size:
                    buffer[i + offset] = cast[array[0..1,uint8]](field_v)[i] 
                    inc i

            of "cint8":
                let field_v = v.o["value"].i.int8
                buffer[offset] = cast[uint8](field_v)
                
            of "cuint8":
                let field_v = v.o["value"].i.uint8
                buffer[offset] = field_v
            else:
                echo "unimplemented field type"
                raise VMError()

    #=======================================
    # Methods
    #=======================================
    import std/endians
    
    proc execForeignMethod*(path: string, meth: string, params: ValueArray = @[], expected_t: Value = nil): Value =
        try:
            #TODO Have some kind of check if struct is one element? Cause it might not work
            # set result to :null
            #TODO Check and add padding to all struct oriented scopes, padded to biggest type
            result = VNULL
            
            # load library
            var fun : pointer = nil
            if path in CachedFFILibs:
                let lib = CachedFFILibs[path]
                fun = lib.symAddr(meth)
            else:
                let resolvedPath = resolveLibrary(path)
                let lib = loadLibrary(resolvedPath)
                CachedFFILibs[path] = lib
                fun = lib.symAddr(meth)


            # If expected value is nil then  
            var expectedType: ValueKind = 
                if expected_t.isNil:
                    Nothing    # turn that into Nothing ValueKind
                else:
                    if expected_t.kind != Block:
                        expected_t.t # otherwise use ValueKind underneath if its not Block
                    else:
                        Block
                    
            var
                cif: TCif
                params_cif: ParamList
                args: ArgList
                returns_pointer = false
                expected : Value = expected_t
                struct_values   : seq[array[0..63, uint8]] # 64-byte array to be used as struct
                structs_elements: seq[array[0..15, ptr Type]] 
                struct_types    : seq[Type]

                return_struct_type: Type
                return_struct_fields: seq[string]

                literal_values : seq[pointer]

            # TODO When its block, do the same as in Object but keep in mind it returns a pointer
            if expectedType == Block:
                returns_pointer = true
                if expected.a.len != 2:
                    echo "Block should have 2 elements"
                    raise VMError()

                var has_null = false
                for v in expected_t.a:
                    let typ = v.t
                    if typ == Null: has_null = true; continue
                    expected = v
                    expectedType = typ
                
                if not has_null:
                    echo "No null inside the block"
                    raise VMError()

            
            if expectedType == Object: # set up cffi struct type to return
                case expected.tid:
                    of "cvoid":
                        expectedType = Nothing # Make sure nothing gets returned
                    
                    of "cint64",
                       "cuint64",
                       "cint32",
                       "cuint32",
                       "cint16",
                       "cuint16",
                       "cint8",
                       "cuint8",
                       "cpointer": expectedType = Integer
                    
                    of "cstring": expectedType = String

                    of "cdouble",
                       "cfloat",
                       "cldouble": expectedType = Floating

                    else:
                        let return_type = getType(expected.tid)
                        var 
                            max_size  = 0
                            full_size = 0
                            buffer : array[0..15, ptr Type]
                            i = 0

                        for f in return_type.content["init"].mmain.a:
                            if f.kind == Block:
                                for typ in f.a:
                                    if typ.tpKind == UserType and typ.kind != Word:
                                        let size = returnTypeSize(typ.tid)
                                        return_struct_fields.add(typ.tid)

                                        if size > max_size: max_size = size
                                        full_size += size
                        
                                        if size != 0:
                                            let address = returnTypeAddr(typ.tid) # TODO, Add types for other structs too
                                            if address.isNil:
                                                echo "Error Type: ", typ.tid
                                                break
                                            else: 
                                                buffer[i] = address
                                                inc i
                        
                        structs_elements.add(buffer)
                        return_struct_type = libffi.Type(size: full_size, alignment: max_size.uint16 , typ: tkSTRUCT, elements: cast[ptr ptr Type](structs_elements[0].addr))
                        # FIXME currently using structs_elements[0], keep that in mind for declaring other structs
            for i,p in params.pairs:
                case p.kind:
                    of Object:
                        addParameterFFI(p,i, params_cif, args, struct_values, structs_elements, struct_types, false)
                    
                    of Literal:
                        let value = FetchSym(p.s)

                        if not value.o.hasKey("value") and value.proto.name[0] != 'c': #FIXME
                            var buffer = new array[0..63,uint8] # DONT PUT IT OUTSIDE OF IF, IT WONT WORK

                            var buf_offset = 0
                            for k in value.o.keys:
                                if value.o[k].kind != Method:
                                    #TODO add support for structs inside structs
                                    let field = value.o[k]
                                    let type_name = field.proto.name
                                    turnIntoStruct(field,buffer[],buf_offset)
                                    buf_offset += returnTypeSize(type_name)
                            literal_values.add(cast[ptr array[0..63,uint8]](buffer))
                            addParameterFFI(value,i, params_cif, args, struct_values, structs_elements, struct_types, cast[pointer](buffer.addr) )
                        else:
                            var buffer = new array[0..63,uint8]
                            turnIntoStruct(value,buffer[])
                            literal_values.add(cast[ptr array[0..63,uint8]](buffer))
                            addParameterFFI(value,i, params_cif, args, struct_values, structs_elements, struct_types, cast[pointer](buffer.addr) )
                    else:
                        echo "Incorrect type for C-FFI function call"
                        echo p.kind

                        discard
            
            var return_type: ptr Type 
            var # A temporary solution, might be better to have one variable of biggest type and then unsafely cast it
                return_int    : int
                return_float  : float # FIXME make it either float or float32
                return_string : cstring
                return_struct : array[0..63,uint8]
                return_pointer: pointer

            if returns_pointer:
                return_type = type_pointer.addr
            else:
                case expectedType:
                    of Nothing:
                        return_type = type_void.addr
                    of Integer, Floating, String:
                        return_type = returnTypeAddr(expected.tid)
                    of Object:
                        return_type = return_struct_type.addr
                    else:
                        echo "Unimplemented return type ", expected.tid
                        discard
                    
            if OK != prep_cif(cif, DEFAULT_ABI, params.len.cuint , return_type, params_cif):
                echo "Something went wrong with preparing the statement"
                quit 1

            case expectedType: # Add appropriate casting later
                of Integer: #TODO fix all the types
                    if returns_pointer:
                        call(cif, fun, return_pointer.addr, args)
                        return_int = cast[ptr int](return_pointer)[]
                    else:
                        call(cif, fun, return_int.addr, args)
                    result = newInteger(return_int)
                of Floating:
                    if returns_pointer:
                        call(cif, fun, returns_pointer.addr, args)
                        return_float = cast[ptr float64](return_pointer)[]
                    else:
                        call(cif, fun, return_float.addr, args)
                    result = if expected.tid == "cdouble": newFloating(return_float)
                    else:                                  newFloating(cast[float32](return_float))
                of Logical:
                    if returns_pointer:
                        call(cif, fun, return_pointer.addr, args)
                        return_int = cast[ptr int](return_pointer)[]
                    else:
                        call(cif, fun, return_int.addr, args)
                    result = newLogical(return_int)
                of String:
                    if returns_pointer:
                        call(cif, fun, return_pointer.addr, args)
                        if not return_pointer.isNil: return_string = cast[cstring](return_pointer)
                    else:
                        call(cif, fun, return_string.addr, args)
                    if returns_pointer and (not return_pointer.isNil):
                        result = newString(return_string)
                    else:
                        result = VNULL
                of Nothing:
                    if returns_pointer:
                        echo "Is it really correct?"
                        raise VMError()
                    call(cif, fun, nil, args)
                    result = VNULL
                of Object:
                    if returns_pointer:
                        call(cif, fun, return_pointer.addr, args)
                        return_struct = cast[ptr array[0..63,uint8]](return_pointer)[]
                    else:
                        call(cif, fun, return_struct.addr, args)

                    var result_block : seq[Value]
                    var idx : uint = 0
                    for f in return_struct_fields:
                        case f:
                            of "cdouble":
                                result_block.add( newFloating( cast[ptr float]( getStructFieldPtr(return_struct.addr, idx) )[] ) )
                                idx += returnTypeSize(f).uint
                            of "cfloat":
                                result_block.add( newFloating( cast[ptr float32]( getStructFieldPtr(return_struct.addr, idx) )[] ) )
                                idx += returnTypeSize(f).uint
                            
                            of "cpointer":
                                var val: array[0..7, uint8]
                                littleEndian64(val.addr, cast[ptr array[0..7, uint8]]( getStructFieldPtr(return_struct.addr, idx) ) )
                                result_block.add( newInteger( cast[csize_t](val).int ) )
                                idx += returnTypeSize(f).uint

                            of "cint64":
                                result_block.add( newInteger( cast[ptr clonglong]( getStructFieldPtr(return_struct.addr, idx) )[] ) )
                                idx += returnTypeSize(f).uint
                            of "cuint64":
                                result_block.add( newInteger( cast[ptr culonglong]( getStructFieldPtr(return_struct.addr, idx) )[].int ) )
                                idx += returnTypeSize(f).uint
                            
                            of "cint32":
                                var val: array[0..3, uint8]
                                littleEndian32(val.addr, cast[ptr array[0..3, uint8]]( getStructFieldPtr(return_struct.addr, idx) ) )
                                result_block.add( newInteger( cast[int32](val) ) )
                                idx += returnTypeSize(f).uint
                            of "cuint32":
                                var val: array[0..3, uint8]
                                littleEndian32(val.addr, cast[ptr array[0..3, uint8]]( getStructFieldPtr(return_struct.addr, idx) ) )
                                result_block.add( newInteger( cast[uint32](val).int ) )
                                idx += returnTypeSize(f).uint

                            of "cint16":
                                result_block.add( newInteger( cast[ptr cshort]( getStructFieldPtr(return_struct.addr, idx) )[] ) )
                                idx += returnTypeSize(f).uint
                            of "cuint16":
                                result_block.add( newInteger( cast[ptr cushort]( getStructFieldPtr(return_struct.addr, idx) )[].int ) )
                                idx += returnTypeSize(f).uint
                            
                            else:
                                echo "Unimplemented field type yet ", f
                                raise VMError()
                    
                    result = newBlock( result_block )
                else:
                    discard
            
            var idx = 0
            for i,p in params.pairs:
                if p.kind == Literal:
                    let param = FetchSym(p.s)
                    if param.o.hasKey("value") and param.proto.name[0] == 'c': # FIXME
                        # Single value
                        let buff : array[0..63,uint8] = cast[ptr array[0..63,uint8]](literal_values[idx])[]
                        case param.proto.name:
                            of "cint64":    
                                Syms[p.s].o["value"].i = cast[clonglong](buff)
                            of "cuint64":    
                                Syms[p.s].o["value"].i = cast[culonglong](buff).int
                            
                            of "cint32":    
                                Syms[p.s].o["value"].i = cast[clong](buff)
                            of "cuint32":    
                                Syms[p.s].o["value"].i = cast[culong](buff).int
                            #TODO 16-bit
                            of "cfloat":    
                                Syms[p.s].o["value"].f = cast[cfloat](buff)
                            of "cdouble":    
                                Syms[p.s].o["value"].f = cast[cdouble](buff)
                            else:
                                echo "NOT IMPLEMENTED YET"
                    else:
                        # Struct
                        let buff : array[0..63,uint8] = cast[ptr array[0..63,uint8]](literal_values[idx])[]
                        var buf_offset : uint = 0
                        for k in param.o.keys:
                            if param.o[k].kind != Method:
                                #TODO add support for structs inside structs
                                let type_name = param.o[k].proto.name

                                case type_name:
                                    of "cfloat":
                                        Syms[p.s].o[k].o["value"].f = cast[ptr cfloat]( cast[uint](buff.addr) + buf_offset )[]
                                    of "cdouble":
                                        Syms[p.s].o[k].o["value"].f = cast[ptr cdouble]( cast[uint](buff.addr) + buf_offset )[]
                                    
                                    of "cint64":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr clonglong]( cast[uint](buff.addr) + buf_offset )[]
                                    of "cuint64":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr culonglong]( cast[uint](buff.addr) + buf_offset )[].int
                                    
                                    of "cint32":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr clong]( cast[uint](buff.addr) + buf_offset )[]
                                    of "cuint32":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr culong]( cast[uint](buff.addr) + buf_offset )[].int

                                    of "cint16":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr cshort]( cast[uint](buff.addr) + buf_offset )[]
                                    of "cuint16":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr cushort]( cast[uint](buff.addr) + buf_offset )[].int
                                    
                                    of "cint8":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr cschar]( cast[uint](buff.addr) + buf_offset )[]
                                    of "cuint8":
                                        Syms[p.s].o[k].o["value"].i = cast[ptr uint8]( cast[uint](buff.addr) + buf_offset )[].int
                                    else:
                                        discard
                                
                                buf_offset += returnTypeSize(type_name).uint # FIXME PADDING                            
                        
                    
                    inc idx
            
        
        except VMError as e:
            raise e

        except CatchableError:
            unloadCachedFFILibs()
            RuntimeError_ErrorLoadingLibrarySymbol(path, meth)
    
