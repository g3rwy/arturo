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
    import dynlib, os, strutils, libffi, objects

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

    #=======================================
    # Methods
    #=======================================

    proc execForeignMethod*(path: string, meth: string, params: ValueArray = @[], expected: Value = nil): Value =
        try:
            #TODO add another attribute to set if it uses 32-bit sizes or 64-bit sizes
            #TODO Have some kind of check if struct is one element? Cause it might not work
            # set result to :null
            result = VNULL
            # load library
            
            let resolvedPath = resolveLibrary(path)
            let lib = loadLibrary(resolvedPath)

            # the variable that will store 
            # the return value from the function
            let expectedType: ValueKind = 
                if expected.isNil:
                    Nothing
                else:
                    expected.t


            # execute given method
            # depending on the params given
            var struct_elements : array[0..2, ptr Type]
            struct_elements[0] = type_float.addr
            struct_elements[1] = type_float.addr

            var type_structV2 : Type = libffi.Type(size: 4 * 2, alignment: 8, typ: tkSTRUCT, elements: cast[ptr ptr Type](struct_elements.addr) )

            var fun = lib.symAddr(meth)
            var
                cif: TCif
                params_cif: ParamList
                args: ArgList
                bool_values   : seq[int]
                string_values : seq[cstring]
                float_values  : seq[float32]
                struct_values : seq[array[0..63, uint8]] # 64-byte array to be used as struct
            
            for i,p in params.pairs:
                case p.kind:
                    of Integer:
                        params_cif[i] = type_sint64.addr
                        args[i] = params[i].i.addr
                    of Floating:
                        params_cif[i] = type_float.addr
                        float_values.add(params[i].f.float32)
                        args[i] = float_values[float_values.high].addr
                    of Logical:
                        params_cif[i] = type_sint8.addr
                        if params[i].isTrue: # TODO add maybe if possible
                            bool_values.add(1)
                            args[i] = bool_values[bool_values.high].addr
                        else:
                            bool_values.add(0)
                            args[i] = bool_values[bool_values.high].addr
                    of String:
                        params_cif[i] = type_pointer.addr
                        string_values.add(cstring(params[i].s))
                        args[i] = string_values[string_values.high].addr
                    of Object:
                        params_cif[i] = type_structV2.addr
                        var buffer : array[0..63, uint8] # Fake 64byte struct
                        var idx = 0
                        for value in params[i].o.objectValues:
                            case value.kind:
                                of Floating: # If its 64-bit, considering padding, struct should be padded to the biggest size in field
                                    let tmp = value.f.float32
                                    for b in cast[array[0..3,uint8]](tmp):
                                        buffer[idx] = b
                                        inc idx 
                                else:
                                    echo "Not Implemented"
                                    discard
                        struct_values.add(buffer) # make sure its pased by value and not by reference, clone it
                        args[i] = struct_values[struct_values.high].addr
                    else:
                        discard

            var return_type: ptr Type 
            var # A temporary solution, might be better to have one variable of biggest type and then unsafely cast it
                return_int    : int
                return_float  : float32
                return_logical: int
                return_string : cstring
                return_struct : array[0..63,uint8]
                return_pointer: pointer

            case expectedType:
                of Integer:
                    return_type = type_sint64.addr
                of Floating:
                    return_type = type_float.addr
                of Logical:
                    return_type = type_sint8.addr
                of String:
                    return_type = type_pointer.addr        
                of Object:
                    return_type = type_structV2.addr
                of Nothing:
                    return_type = type_void.addr
                else:
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
                    call(cif, fun, return_struct.addr, args)
                    let f1 = cast[ptr float32](return_struct.addr)
                    result = newBlock( @[ newFloating(f1[]) ,newFloating(cast[ptr float32](cast[uint](f1) + 4)[] ) ] )
                else:
                    discard
            
            # unload the library
            
            unloadLibrary(lib)
        
        except VMError as e:
            raise e

        except CatchableError:
            RuntimeError_ErrorLoadingLibrarySymbol(path, meth)
    
