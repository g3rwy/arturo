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
    # WARNING TODO IMPORTANT !!! figure out how to import "objects" without issues
    import dynlib, os, strutils, libffi, tables

    import vm/[errors, values/value]

    #import vm/values/custom/[vlogical]

    #=======================================
    # Types
    #=======================================

    # The most stupid hack of the century
    # but it kinda works - better than nothing!

    #=======================================
    # Helpers
    #=======================================

    proc loadLibrary*(path: string): LibHandle =
        result = loadLib(path)

        if result == nil:
            RuntimeError_LibraryNotLoaded(path)

    proc unloadLibrary*(lib: LibHandle) =
        unloadLib(lib)

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
    #=======================================
    # Methods
    #=======================================
    import "vm/globals.nim"
    proc execForeignMethod*(path: string, meth: string, params: ValueArray = @[], expected: Value = nil): Value =
        try:
            #TODO Have some kind of check if struct is one element? Cause it might not work
            # set result to :null
            result = VNULL

            # load library
            let resolvedPath = resolveLibrary(path)
            let lib = loadLibrary(resolvedPath)


            # If expected value is nil then  
            var expectedType: ValueKind = 
                if expected.isNil:
                    Nothing    # turn that into Nothing ValueKind
                else:
                    expected.t # otherwise use ValueKind underneath 

            # TODO, if expected type is Block, it should contain :null type inside + type, treated as return as pointer

            var
                cif: TCif
                params_cif: ParamList
                args: ArgList
                
                struct_values   : seq[array[0..63, uint8]] # 64-byte array to be used as struct
                structs_elements: seq[array[0..15, ptr Type]] 
                struct_types    : seq[Type]

                return_struct_type: Type

            # TODO When its block, do the same as in Object but keep in mind it returns a pointer
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
                        var types : OrderedTable[string,int]
                        let return_type = getType(expected.tid)
                        var 
                            max_size  = 0
                            full_size = 0
                            buffer : array[0..15, ptr Type]

                        for f in return_type.content["init"].mmain.a:
                            if f.kind == Block:
                                for typ in f.a:
                                    if typ.tpKind == UserType and typ.kind != Word:
                                        let size = returnTypeSize(typ.tid)
                                        types[typ.tid] = size
                                        
                                        if size > max_size: max_size = size
                                        full_size += size 
                        
                                        var i = 0
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
             
            var fun = lib.symAddr(meth)
            #echo expectedType

            for i,p in params.pairs: 
                case p.kind:
                    of Object:
                            let type_name = params[i].proto.name
                            if type_name[0] == 'c': # FIXME
                                    params_cif[i] = returnTypeAddr(type_name)

                                    if type_name in ["cuint64", "cpointer"]:
                                        var cval = csize_t.new # Test it out
                                        cval[] = params[i].o["value"].i.csize_t
                                        args[i] = cast[ptr csize_t](cval)
                                    
                                    elif type_name == "cint64":
                                        var cval = clonglong.new # Test it out
                                        cval[] = params[i].o["value"].i.clonglong
                                        args[i] = cast[ptr clonglong](cval)
                                    
                                    elif type_name == "cfloat":
                                        var cval = cfloat.new # Test it out
                                        cval[] = params[i].o["value"].f.cfloat
                                        args[i] = cast[ptr cfloat](cval)
                                    
                                    elif type_name == "cstring":
                                        var cval = cstring.new
                                        cval[] = params[i].o["value"].s.cstring
                                        args[i] = cast[cstring](cval)

                                    else:
                                        echo "Unimplemented! ", type_name
                            else:
                                var 
                                    buffer : array[0..63, uint8] # Fake 64byte struct
                                    idx = 0
                                    max_size  = 0
                                    full_size = 0
                                    types : OrderedTable[string,int]
                                    elements_buf : array[0..15, ptr Type]

                                var j = 0
                                for value in params[i].o.values:
                                    #echo value.kind
                                    if value.kind != Method:
                                        echo value.proto.name
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

                                        structs_elements.add(elements_buf)
                                        struct_types.add( 
                                            libffi.Type(size: full_size, 
                                                        alignment: max_size.uint16 , 
                                                        typ: tkSTRUCT, 
                                                        elements: cast[ptr ptr Type](structs_elements[structs_elements.high].addr) ) 
                                            )
                                        params_cif[i] = struct_types[struct_types.high].addr
                                        # -------------------------------------------


                        #struct_values.add(buffer) # make sure its pased by value and not by reference, clone it
                        #args[i] = struct_values[struct_values.high].addr
                    
                    of Literal: # TODO Should be same as Object but passed as pointer
                        discard
                    else:
                        echo "Incorrect type for C-FFI function call"
                        echo p.kind

                        discard
                echo "----------------------------"
            
            #echo args.repr

            var return_type: ptr Type 
            var # A temporary solution, might be better to have one variable of biggest type and then unsafely cast it
                return_int    : int
                return_float  : float32 
                return_logical: int
                return_string : cstring
                return_struct : array[0..63,uint8]
                return_pointer: pointer

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
            
            case expectedType:
                of Integer:
                    call(cif, fun, return_int.addr, args)
                    result = newInteger(return_int)
                of Floating:
                    call(cif, fun, return_float.addr, args)
                    result = newFloating(return_float)
                of Logical:
                    call(cif, fun, return_logical.addr, args)
                    result = newLogical(return_logical)
                of String:
                    call(cif, fun, return_string.addr, args)
                    result = newString(return_string)
                of Nothing:
                    call(cif, fun, nil, args)
                
                of Object:
                    echo "implement the structs buddy"
                    result = newInteger(0)
                    #call(cif, fun, return_struct.addr, args)
                    #let f1 = cast[ptr float32](return_struct.addr)
                    #result = newBlock( @[ newFloating(f1[]) ,newFloating(cast[ptr float32](cast[uint](f1) + 4)[] ) ] )
                else:
                    discard
            
            unloadLibrary(lib)
        
        except VMError as e:
            raise e

        except CatchableError:
            RuntimeError_ErrorLoadingLibrarySymbol(path, meth)
    
