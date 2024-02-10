#=======================================================
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2024 Yanis Zafirópulos
#
# @file: vm/errors.nim
#=======================================================

## Error handling for the VM.

#=======================================
# Libraries
#=======================================

when not defined(WEB):
    import math, re, terminal
import sequtils, strformat, strutils, sugar, std/with

import helpers/strings
import helpers/terminal

import vm/values/custom/verror

#=======================================
# Types
#=======================================

type
    ReturnTriggered*    = ref object of Defect
    BreakTriggered*     = ref object of Defect
    ContinueTriggered*  = ref object of Defect

#=======================================
# Constants
#=======================================

const
    Alternative         = "perhaps you meant"
    MaxIntSupported     = sizeof(int) * 8
    ReplContext         = " <repl> "

    UseUnicodeChars     = true

    HorizLine           = when UseUnicodeChars: "\u2550" else: "="
    LeftBracket         = when UseUnicodeChars: "\u2561" else: "["
    RightBracket        = when UseUnicodeChars: "\u255E" else: "]"

#=======================================
# Variables
#=======================================

var
    CurrentContext* : string    = ReplContext
    CurrentPath*    : string    = ""
    CurrentLine*    : int       = 0
    ExecStack*      : seq[int]  = @[]

#=======================================
# Helpers
#=======================================

# Check environment

proc isRepl(): bool =
    return CurrentContext == ReplContext

proc getCurrentContext(e: VError): string =
    if e.kind == CmdlineErr: return ""

    if CurrentContext == ReplContext: return CurrentContext
    return " <script> "

# General formatting

proc formatMessage(s: string): string =
    var ret = s.replacef(re"_([^_]+)_",fmt("{bold()}$1{resetColor}"))
               #.replacef(re":([a-z]+)",fmt("{fg(magentaColor)}:$1{resetColor}"))

    ret = indent(strip(dedent(ret)), 2)

    return ret

proc `~~`*(s: string, inputs: seq[string]): string =
    var replacements: seq[string]
    var finalS = s
    for line in s.splitLines():
        for found in line.findAll(re"\$[\$#]"):
            if found=="$$":
                let ind = line.find("$$")
                replacements.add(strip(indent(strip(inputs[replacements.len]),ind)))
            else:
                replacements.add(inputs[replacements.len])
    
    finalS = finalS.replace("$$", "$#")
    return finalS % replacements    

# Error messages

proc printErrorHeader(e: VError) =
    let preHeader = 
        fg(redColor) & "{HorizLine}{HorizLine}{LeftBracket} ".fmt & 
        bold(redColor) & (e.kind.label) & 
        fg(redColor) & " {RightBracket}".fmt

    let postHeader = 
        getCurrentContext(e) & 
        "{HorizLine}{HorizLine}".fmt & 
        resetColor()

    let middleStretch = terminalWidth() - preHeader.realLen() - postHeader.realLen()

    echo ""
    echo preHeader & repeat(HorizLine, middleStretch) & postHeader

proc printErrorKindDescription(e: VError) =
    if e.kind.description != "":
        echo ""
        echo indent(e.kind.description, 2) & resetColor

proc printErrorMessage(e: VError) =
    echo ""
    echo strip(indent(dedent(formatMessage(e.msg)), 2), chars={'\n'})

proc printCodePreview(e: VError) =
    when not defined(NOERRORLINES):
        if (not isRepl()) and e.kind != CmdlineErr:
            echo ""
            let codeLines = readFile(CurrentPath).splitLines()
            const linesBeforeAfter = 2
            let lineFrom = max(0, CurrentLine - (linesBeforeAfter+1))
            let lineTo = min(len(codeLines)-1, CurrentLine + (linesBeforeAfter-1))
            let alignmentSize = max(($lineTo).len, 3)
            let alignmentPadding = repeat(" ", alignmentSize)
            echo "  " & fg(grayColor) & "\u2503 " & bold(grayColor) & "File: " & fg(grayColor) & CurrentPath
            echo "  " & fg(grayColor) & "\u2503 " & bold(grayColor) & "Line: " & fg(grayColor) & $(CurrentLine)
            echo "  " & fg(grayColor) & "\u2503 " & resetColor
            for lineNo in lineFrom..lineTo:
                var line = codeLines[lineNo]
                var pointerArrow = "\u2551 "
                var lineNum = $(lineNo+1)
                if lineNo == CurrentLine-1: 
                    pointerArrow = "\u2551" & fg(redColor) & "\u25ba" & fg(grayColor)
                    line = bold(grayColor) & line & fg(grayColor)
                    lineNum = bold(grayColor) & lineNum & fg(grayColor)
                echo "  " & fg(grayColor) & "\u2503 " & alignmentPadding & lineNum & " {pointerArrow} ".fmt & line & resetColor

proc printHint(e: VError) =
    if e.hint != "":
        echo ""
        let wrappingWidth = min(100, int(0.8 * float(terminalWidth() - 2 - 6)))
        echo "  " & "\e[4;97m" & "Hint" & resetColor() & ": " & wrapped(strip(dedent(e.hint)).splitLines().join(" "), wrappingWidth, delim="\n        ")

#=======================================
# Methods
#=======================================

proc showError*(e: VError) =
    with e:
        printErrorHeader()
        printErrorKindDescription()
        printErrorMessage()
        printCodePreview()
        printHint()
    
    if (not isRepl()) or e.hint=="":
        echo ""

proc panic(error: VError) =
    if error.kind == CmdlineErr:
        showError(error)
        quit(1)
    else:
        raise error

#=======================================
# Constructors
#=======================================

#------------------------
# Command-line Errors
#------------------------

proc Error_ScriptNotExists*(name: string) =
    panic:
        toError CmdlineErr, """
            Given script doesn't exist:
                _{name}_
        """.fmt

proc Error_UnrecognizedOption*(name: string) =
    panic:
        toError CmdlineErr, """
            unrecognized command-line option:
                _{name}_
        """.fmt

proc Error_UnrecognizedPackageCommand*(name: string) =
    panic:
        toError CmdlineErr, """
            unrecognized _package_ command:
                _{name}_
        """.fmt

proc Error_NoPackageCommand*() =
    panic:
        toError CmdlineErr, """
            no _package_ command command given -
            have a look at the options below
        """.fmt

proc Error_ExtraneousParameter*(subcmd: string, name: string) =
    panic: 
        toError CmdlineErr, """
            extraneous parameter for _{subcmd}_:
                {name}
        """.fmt

proc Error_NotEnoughParameters*(name: string) =
    panic:
        toError CmdlineErr, """
            not enough parameters for _{name}_ -
            consult the help screen below
        """.fmt

#------------------------
# Conversion Errors
#------------------------

proc Error_CannotConvert*(arg,fromType,toType: string) =
    panic:
        toError ConversionErr, """
            Got value:
                $$

            Conversion to given type is not supported:
                :$#
        """ ~~ @[arg, toType.toLowerAscii()]

proc Error_ConversionFailed*(arg,fromType,toType: string, hint: string="") =
    panic:
        toError ConversionErr, """
            Got value:
                $$

            Failed while trying to convert to:
                :$#
        """ ~~ @[arg, toType.toLowerAscii()], hint

#------------------------
# Syntax Errors
#------------------------

proc Error_MissingClosingSquareBracket*(lineno: int, context: string) =
    CurrentLine = lineno
    panic:
        toError SyntaxErr, """
            missing closing square bracket: `]`

            near: {context}
        """.fmt

proc Error_MissingClosingParenthesis*(lineno: int, context: string) =
    CurrentLine = lineno
    panic:
        toError SyntaxErr, """
            missing closing parenthesis: `)`

            near: {context}
        """.fmt

proc Error_StrayClosingSquareBracket*(lineno: int, context: string) =
    CurrentLine = lineno
    panic:
        toError SyntaxErr, """
            stray closing square bracket: `]`

            near: {context}
        """.fmt

proc Error_StrayClosingCurlyBracket*(lineno: int, context: string) =
    CurrentLine = lineno
    panic: 
        toError SyntaxErr, """
            stray closing curly bracket: `}`

            near: $#
        """ % [context]

proc Error_StrayClosingParenthesis*(lineno: int, context: string) =
    CurrentLine = lineno
    panic:
        toError SyntaxErr, """
            stray closing parenthesis: `)`

            near: {context}
        """.fmt

proc Error_UnterminatedString*(strtype: string, lineno: int, context: string) =
    var strt = strtype
    if strt!="": strt &= " "
    CurrentLine = lineno
    panic:
        toError SyntaxErr, """
            unterminated {strt}string

            near: {context}
        """.fmt

proc Error_NewlineInQuotedString*(lineno: int, context: string) =
    CurrentLine = lineno
    panic:
        toError SyntaxErr, """
            newline in quoted string
            for multiline strings, you could use either:
            curly blocks _{..}_ or _triple "-"_ templates

            near: $#
        """ % [context]

proc Error_EmptyLiteral*(lineno: int, context: string) =
    CurrentLine = lineno
    panic: 
        toError SyntaxErr, """
            empty literal value

            near: {context}
        """.fmt

# Assertion errors

proc Error_AssertionFailed*(context: string) =
    panic:
        toError AssertionErr,
            context
          
proc Error_AssertionFailed*(context: string, message: string) =
    panic: 
        toError AssertionErr, """
            {message}:
            for: {context}
        """.fmt

# Runtime errors

proc Error_IntegerParsingOverflow*(lineno: int, number: string) =
    CurrentLine = lineno
    panic: 
        toError RuntimeErr, """
            number parsing overflow - up to {MaxIntSupported}-bit integers supported
            given: {truncate(number, 20)}
        """.fmt

proc Error_IntegerOperationOverflow*(operation: string, argA, argB: string) =
    panic: 
        toError RuntimeErr, """
            number operation overflow - up to {MaxIntSupported}-bit integers supported
            attempted: {operation}
            with: {truncate(argA & " " & argB, 30)}
        """.fmt

proc Error_NumberOutOfPermittedRange*(operation: string, argA, argB: string) =
    panic: 
        toError RuntimeErr, """
            number operator out of range - up to {MaxIntSupported}-bit integers supported
            attempted: {operation}
            with: {truncate(argA & " " & argB, 30)}
        """.fmt

proc Error_IncompatibleQuantityOperation*(operation: string, argA, argB, kindA, kindB: string) =
    panic: 
        toError RuntimeErr, """
            incompatible operation between quantities
            attempted: {operation}
            with: """.fmt & truncate(argA & " (" & kindA & ") " & argB & " (" & kindB & ")", 60)
            
proc Error_IncompatibleValueType*(functionName: string, tp: string, expected: string) =
    panic: 
        toError RuntimeErr, """
            cannot perform _{functionName}_
            incompatible value type for {tp}
            expected {expected}
        """.fmt

proc Error_IncompatibleBlockValue*(functionName: string, val: string, expected: string) =
    panic: 
        toError RuntimeErr, """
            cannot perform _{functionName}_ -> {val}
            incompatible value inside block parameter
            expected {expected}
        """.fmt

proc Error_IncompatibleBlockValueAttribute*(functionName: string, attributeName: string, val: string, expected: string) =
    panic: 
        toError RuntimeErr, """
            cannot perform _{functionName}_
            incompatible value inside block for _{attributeName}_ -> {val}
            accepts {expected}
        """.fmt

proc Error_IncompatibleBlockSize*(functionName: string, got: int, expected: string) =
    panic: 
        toError RuntimeErr, """
            cannot perform _{functionName}_
            incompatible block size: {$(got)}
            expected: {$(expected)}
        """.fmt

proc Error_UsingUndefinedType*(typeName: string) =
    panic: 
        toError RuntimeErr, """
            undefined or unknown type _:{typeName}_
            you should make sure it has been properly
            initialized using `define`
        """.fmt

proc Error_IncorrectNumberOfArgumentsForInitializer*(typeName: string, got: int, expected: seq[string]) =
    panic:
        toError RuntimeErr, """
            cannot initialize object of type _:{typeName}_
            wrong number of parameters: {$(got)}
            expected: {$(expected.len)} ({expected.join(", ")})
        """.fmt

proc Error_MissingArgumentForInitializer*(typeName: string, missing: string) =
    panic:
        toError RuntimeErr, """
            cannot initialize object of type _:{typeName}_
            missing field: {$(missing)}
        """.fmt

proc Error_UnsupportedParentType*(typeName: string) =
    panic:
        toError RuntimeErr, """
            subtyping built-in type _:{typeName}_
            is not supported
        """.fmt

proc Error_InvalidOperation*(operation: string, argA, argB: string) =
    if argB != "":
        panic:
            toError RuntimeErr, """
                invalid operation _{operation}_
                between: {argA}
                    and: {argB}
            """.fmt
    else:
        panic:
            toError RuntimeErr, """
                invalid operation _{operation}_
                with: {argA}
            """.fmt

proc Error_CannotConvertQuantity*(val, argA, kindA, argB, kindB: string) =
    panic:
        toError RuntimeErr, """
            cannot convert quantity: {val}
            from: {argA} ({kindA})
            to: {argB} ({kindB})
        """.fmt
          
proc Error_CannotConvertDifferentDimensions*() =
    panic:
        toError RuntimeErr, """
            cannot convert quantities with different dimensions
        """

proc Error_DivisionByZero*() =
    panic:
        toError ArithmeticErr, """
            division by zero
        """

proc Error_OutOfBounds*(indx: int, maxRange: int) =
    panic:
        toError RuntimeErr, """
            array index out of bounds: {$(indx)}
            valid range: 0..{$(maxRange)}
        """.fmt

proc Error_SymbolNotFound*(sym: string, alter: seq[string]) =
    let sep = "\n" & repeat("~%",Alternative.len - 2) & "or... "
    panic:
        toError RuntimeErr, """
            symbol not found: {sym}
            perhaps you meant... {alter.map((x) => "_" & x & "_ ?").join(sep)}
        """.fmt

proc Error_CannotModifyConstant*(sym: string) =
    panic:
        toError RuntimeErr, """
            value points to a readonly constant: {sym}
            which cannot be modified in-place
        """.fmt

proc Error_PathLiteralMofifyingString*() =
    panic:
        toError RuntimeErr, """ 
            in-place modification of strings
            through PathLiteral values is not supported
        """

proc Error_FileNotFound*(path: string) =
    panic:
        toError RuntimeErr, """
            file not found: {path}
        """.fmt

proc Error_AliasNotFound*(sym: string) =
    panic: 
        toError RuntimeErr, """
            alias not found: {sym}
        """.fmt

proc Error_KeyNotFound*(sym: string, alter: seq[string]) =
    let sep = "\n" & repeat("~%",Alternative.len - 2) & "or... "
    panic:
        toError RuntimeErr, """
            dictionary key not found: {sym}
            perhaps you meant... {alter.map((x) => "_" & x & "_ ?").join(sep)}
        """.fmt

proc Error_CannotStoreKey*(key: string, valueKind: string, storeKind: string) =
    panic:
        toError RuntimeErr, """
            unsupported value type: {valueKind}
            for store of type: {storeKind}
            when storing key: {key}
        """

proc Error_SqliteDisabled*() =
    panic:
        toError RuntimeErr, """
            SQLite not available in MINI builds
            if you want to have access to SQLite-related functionality,
            please, install Arturo's full version
        """

proc Error_NotEnoughArguments*(functionName:string, functionArity: int) =
    panic:
        toError RuntimeErr, """
            cannot perform _{functionName}_
            not enough parameters: {$(functionArity)} required
        """.fmt

proc Error_WrongArgumentType*(functionName: string, actual: string, paramPos: string, accepted: string) =
    panic:
        toError RuntimeErr, """
            cannot perform _{functionName}_ -> {actual}
            incorrect argument type for {paramPos} parameter
            accepts {accepted}
        """.fmt

proc Error_WrongAttributeType*(functionName: string, attributeName: string, actual: string, accepted: string) =
    panic:
        toError RuntimeErr, """
            cannot perform _{functionName}_
            incorrect attribute type for _{attributeName}_ -> {actual}
            accepts {accepted}
        """.fmt

#         Of type     : :{(fromType).toLowerAscii()}

proc Error_LibraryNotLoaded*(path: string) =
    panic:
        toError RuntimeErr, """
            dynamic library could not be loaded:
            {path}
        """.fmt

proc Error_LibrarySymbolNotFound*(path: string, sym: string) =
    panic:
        toError RuntimeErr, """
            symbol not found: {sym}
            in library: {path}
        """.fmt

proc Error_ErrorLoadingLibrarySymbol*(path: string, sym: string) =
    panic:
        toError RuntimeErr, """
            error loading symbol: {sym}
            from library: {path}
        """.fmt

proc Error_OperationNotPermitted*(operation: string) =
    panic:
        toError RuntimeErr, """
            unsafe operation: {operation}
            not permitted in online playground
        """.fmt
          
proc Error_StackUnderflow*() =
    panic:
        toError RuntimeErr, """
            stack underflow
        """

proc Error_ConfigNotFound*(gkey: string, akey: string) =
    panic:
        toError RuntimeErr, """
            configuration not found for: {gkey}
            you can either supply it globally via `config`
            or using the option: .{akey}
        """.fmt

proc Error_RangeWithZeroStep*() =
    panic:
        toError RuntimeErr, """
            attribute step can't be 0
        """
          
proc Error_CompatibleBrowserNotFound*() =
    panic:
        toError RuntimeErr, """
            could not find any Chrome-compatible browser installed
        """
          
proc Error_CompatibleBrowserCouldNotOpenWindow*() =
    panic:
        toError RuntimeErr, """
            could not open a Chrome-compatible browser window
        """

proc Error_PackageNotFound*(pkg: string) =
    panic:
        toError RuntimeErr, """
            package not found:
            _{pkg}_
        """.fmt

proc Error_PackageRepoNotCorrect*(repo: string) =
    panic:
        toError RuntimeErr, """
            package repository url not correct:
            {repo}
        """.fmt

proc Error_PackageRepoNotFound*(repo: string) =
    panic:
        toError RuntimeErr, """
            package repository not found:
            {repo}
        """.fmt

proc Error_CorruptRemoteSpec*(pkg: string) =
    panic:
        toError RuntimeErr, """
            corrupt spec file for remote package:
            _{pkg}_
        """.fmt

proc Error_PackageNotValid*(pkg: string) =
    panic:
        toError RuntimeErr, """
            invalid package:
            _{pkg}_
        """.fmt

proc Error_PackageUnknownError*(pkg: string) =
    panic:
        toError RuntimeErr, """
            unexpected error while installing package:
            _{pkg}_
        """.fmt

proc Error_PackageInvalidVersion*(vers: string) =
    panic:
        toError RuntimeErr, """
            error parsing package version:
            _{vers}_
        """.fmt

# Program errors

proc ProgramError_panic*(message: string, code: int) =
    panic:
        toError ProgramErr, 
            $(code) & "<:>" & message

# TODO Re-establish stack trace debug reports
#  labels: vm, error handling

# var
#     OpStack*    : array[5,OpCode]
#     ConstStack* : ValueArray
# proc getOpStack*(): string =
#     try:
#         var ret = ";;"
#         ret &= (fg(grayColor)).replace(";","%&") & "\b------------------------------;" & resetColor
#         ret &= (fg(grayColor)).replace(";","%&") & "bytecode stack trace:;" & resetColor
#         ret &= (fg(grayColor)).replace(";","%&") & "\b------------------------------;" & resetColor
#         for i in countdown(4,0):
#             let op = (OpCode)(OpStack[i])
#             if op!=opNop :
#                 ret &= (fg(grayColor)).replace(";","%&") & "\b>T@B" & ($(op)).replace("op","").toUpperAscii()
#                 case op:
#                     of opConstI0..opConstI10:
#                         let indx = (int)(op)-(int)opConstI0
#                         if indx>=0 and indx<ConstStack.len:
#                             ret &= " (" & $(ConstStack[indx]) & ")"
#                     of opPush0..opPush30:
#                         let indx = (int)(op)-(int)opPush0
#                         if indx>=0 and indx<ConstStack.len:
#                             ret &= " (" & $(ConstStack[indx]) & ")"
#                     of opStore0..opStore30:
#                         let indx = (int)(op)-(int)opStore0
#                         if indx>=0 and indx<ConstStack.len:
#                             ret &= " (" & $(ConstStack[indx]) & ")"
#                     of opLoad0..opLoad30:
#                         let indx = (int)(op)-(int)opLoad0
#                         if indx>=0 and indx<ConstStack.len:
#                             ret &= " (" & $(ConstStack[indx]) & ")"
#                     of opCall0..opCall30: 
#                         let indx = (int)(op)-(int)opCall0
#                         if indx>=0 and indx<ConstStack.len:
#                             ret &= " (" & $(ConstStack[indx]) & ")"
#                     else:
#                         discard
                
#                 ret &= resetColor
                    
#             if i!=0:
#                 ret &= ";"

#         ret
#     except CatchableError:
#         ""


# proc showVMErrors*(e: ref Exception) =
#     ## show error message
#     var header: string
#     var errorKind: VErrorKind = RuntimeErr
#     try:
#         header = $(e.name)

#         # try:
#         #     # try checking if it's a valid error context
#         #     errorKind = parseEnum[VMErrorKind](header)
#         # except ValueError:
#         #     # if not, show it as an uncaught runtime exception
#         #     e.msg = getLineError() & "uncaught system exception:;" & e.msg
#         #     header = $(RuntimeError)

            
#         # if $(header) notin [RuntimeErr, AssertionErr, SyntaxErr, ProgramError, CompilerErr]:
#         #     e.msg = getLineError() & "uncaught system exception:;" & e.msg
#         #     header = RuntimeErr
#     except CatchableError:
#         header = "HEADER"

#     let marker = ">>"
#     let separator = "|"
#     let indent = repeat(" ", header.len + marker.len + 2)

#     when not defined(WEB):
#         var message: string
        
#         if errorKind==ProgramErr:
#             let liner = e.msg.split("<:>")[0].split("\n\n")[0]
#             let msg = e.msg.split("<:>")[1]
#             message = liner & "\n\n" & msg.replacef(re"_([^_]+)_",fmt("{bold()}$1{resetColor}"))
#         else:
#             message = e.msg.replacef(re"_([^_]+)_",fmt("{bold()}$1{resetColor}"))
#     else:
#         var message = "MESSAGE"

#     let errMsgParts = message.strip().splitLines().map((x)=>(strutils.strip(x)).replace("~%"," ").replace("%&",";").replace("T@B","\t"))
#     let alignedError = align("error", header.len)
    
#     var errMsg = errMsgParts[0] & fmt("\n{bold(redColor)}{repeat(' ',marker.len)} {alignedError} {separator}{resetColor} ")

#     if errMsgParts.len > 1:
#         errMsg &= errMsgParts[1..^1].join(fmt("\n{indent}{bold(redColor)}{separator}{resetColor} "))
#     echo fmt("{bold(redColor)}{marker} {header} {separator}{resetColor} {errMsg}")
