#=======================================================
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2023 Yanis Zafirópulos
#
# @file: helpers/datasource.nim
#=======================================================

# TODO(Helpers/helper) General cleanup needed
#  Too much commented-out code, that's - probably - not needed whatsoever...
#  labels: helpers, cleanup

#=======================================
# Libraries
#=======================================

import sequtils, strformat
import strutils, tables
import sugar

when defined(DOCGEN):
    import re

import helpers/sets
import helpers/terminal

import vm/values/[printable, value]

#=======================================
# Constants
#=======================================

const
    lineChar       = '-'
    lineLength     = 80
    initialSep     = "|"
    initialPadding = "    "
    labelAlignment = 11

#=======================================
# Helpers
#=======================================

template printLine(charWith = lineChar) =
    stdout.write initialSep
    if charWith != lineChar:
        stdout.write fg(grayColor)
    var i = 0
    while i < lineLength:
        stdout.write charWith
        i += 1
    stdout.write "\n"
    if charWith != lineChar:
        stdout.write resetColor()
    stdout.flushFile()


proc printEmptyLine() = 
    echo "|"


proc getAlias(objName: string, aliases: SymbolDict): (string, PrecedenceKind) = 
    ## Return the alias of an object into a tuple 
    ## with it's symbol as a string and its kind of precedence
    
    runnableExamples:
        import vm/globals   # Aliases
        import vm/values    # PrecedenceKind
        
        assert ("~", PrefixPrecedence) == "render".getAlias(Aliases)
    
    for key, val in pairs(aliases):
        if val.name.s == objName:
            return ($(newSymbol(key)), val.precedence)
    return ("", PrefixPrecedence)


proc printOneData(
        label:  string, 
        data:   string, 
        color:  string = resetColor, 
        colorb: string = resetColor
    ) =
    let 
        init  = fmt"{initialSep}{initialPadding}"
        label = fmt"{color}{align(label, labelAlignment)}{resetColor}"
        data  = fmt"{colorb}{data}{resetColor}"
    echo fmt("{init}{label}  {data}")


proc printMultiData(
        label:  string, 
        data:   seq[string], 
        color:  string = resetColor, 
        colorb: string = resetColor
    ) =
    
    printOneData(label, data[0], color, colorb)
    for item in data[1..^1]:
        printOneData("", item, resetColor, colorb)


func getShortData(initial: string): seq[string] =
    result = @[initial]
    if result[0].len > 50:
        let parts  = result[0].splitWhitespace()
        let middle = (parts.len div 2)
        result = @[
            parts[0..middle].join(" "),
            parts[(middle + 1)..^1].join(" ")
        ]


func getTypeString(valueSpec: ValueSpec): string =
    ## Returns the representation of a type into a string
    if valueSpec == {}: 
        return ":nothing"
    
    return collect(for spec in valueSpec: spec.stringify()).join(" ")


proc getUsageForFunction(objName: string, value: Value): seq[string] =
    let args = toSeq(value.info.args.pairs)

    let lenBefore = objName.len
    var spaceBefore: string
    var j = 0
    while j < lenBefore:
        spaceBefore &= " "
        j += 1
        
    let
        templateName = fmt"{bold()}{objName}{resetColor}"
        templateType = fmt"{fg(grayColor)}{getTypeString(args[0][1])}"

    if args[0][0] != "":
        let templateArg = fmt"{args[0][0]}" 
        result.add fmt("{templateName} {templateArg} {templateType}")
    else:   
        result.add fmt("{templateName} {templateType}")

    for arg in args[1..^1]:
        let
            templateArg = fmt"{arg[0]}"
            templateType = fmt"{fg(grayColor)}{getTypeString(arg[1])}"
        result.add fmt("{spaceBefore} {templateArg} {templateType}")


proc getOptionsForFunction(v: Value): seq[string] =
    var attrs = toSeq(v.info.attrs.pairs)
    
    if attrs.len == 1 and attrs[0][0] == "": 
        return @[]

    var maxLen = 0
    for attr in attrs:
        let ts = getTypeString(attr[1][0])
        if ts != ":logical":
            let len = fmt(".{attr[0]} {ts}").len
            if len > maxLen: 
                maxLen = len
        else:
            let len = fmt(".{attr[0]}").len
            if len > maxLen: 
                maxLen = len

    for attr in attrs:
        let ts = getTypeString(attr[1][0])
        var leftSide: string
        var myLen = maxLen
        if ts != ":logical":
            leftSide = fmt("{fg(cyanColor)}.{attr[0]} {fg(grayColor)}{ts}")
            myLen += len(fmt("{fg(cyanColor)}{fg(grayColor)}"))
        else:
            leftSide = fmt("{fg(cyanColor)}.{attr[0]}")
            myLen += len(fmt("{fg(cyanColor)}"))
        
        result.add fmt("{alignLeft(leftSide,myLen)} {resetColor}-> {attr[1][1]}")


when defined(DOCGEN):
    
    proc splitExamples*(ex: string): seq[string] =
        var currentEx: string
        for line in splitLines(ex):
            if line.strip().findAll(re"\.{4,}").len > 0:
                result.add(currentEx)
                currentEx = ""
            else:
                if currentEx != "":
                    currentEx &= "\n"
                currentEx &= line

        result.add(currentEx)


    proc syntaxHighlight(code: string) =
        # token colors
        let commentColor  = fg(grayColor)
        let literalColor  = fg(rgb("129"))
        let functionColor = fg(rgb("87"))
        let labelColor    = fg(rgb("148"))
        let sugarColor    = bold(rgb("208"))
        let symbolColor   = fg(rgb("124"))
        let stringColor   = fg(rgb("221"))

        proc colorizeToken(color, pattern: string): tuple[pattern: Regex, repl: string] = 
            result = (re(pattern), "{color}$1{resetColor}".fmt)

        let highlighted = code.splitLines().map((line)=>
            line.multiReplace(@[
                colorizeToken(commentColor, """(;.+)$"""),
                colorizeToken(stringColor, """(\"[^\"]+\")"""),
                colorizeToken(stringColor, """(`[^\`]+`)"""),
                colorizeToken(literalColor, """('[\w]+\b\??:?)"""),
                colorizeToken(labelColor, """([\w]+\b\??:)"""),
                colorizeToken(sugarColor, """(->|=>|\||\:\:|[\-]{3,})"""),
                colorizeToken(functionColor, """((?<!')\b(all|and|any|ascii|attr|attribute|attributeLabel|binary|block|char|contains|database|date|dictionary|empty|equal|even|every|exists|false|floating|function|greater|greaterOrEqual|if|in|inline|integer|is|key|label|leap|less|lessOrEqual|literal|logical|lower|nand|negative|nor|not|notEqual|null|numeric|odd|or|path|pathLabel|positive|prefix|prime|set|some|sorted|standalone|string|subset|suffix|superset|symbol|true|try|type|unless|upper|when|whitespace|word|xnor|xor|zero)\?(?!:))"""),
                colorizeToken(symbolColor, """(<\:|\-\:|ø|∞|@|#|\+|<=>|=>>|<->|-->|<-->|==>|<==>|<\||\|\-|\|=|\||\*|\$|\-|\%|\/|[\.]{2,}|&|_|!|!!|<:|>:|\./|\^|~|=|<|>|\\|(?<!\\w)\?)"""),
                colorizeToken(functionColor, """((?<!')\b(abs|acos|acosh|acsec|acsech|actan|actanh|add|after|and|angle|append|arg|args|arity|array|as|asec|asech|asin|asinh|atan|atan2|atanh|attr|attrs|average|before|benchmark|blend|break|builtins1|builtins2|call|capitalize|case|ceil|chop|clear|close|color|combine|conj|continue|copy|cos|cosh|csec|csech|ctan|ctanh|cursor|darken|dec|decode|define|delete|desaturate|deviation|dictionary|difference|digest|digits|div|do|download|drop|dup|e|else|empty|encode|ensure|env|escape|execute|exit|exp|extend|extract|factors|false|fdiv|filter|first|flatten|floor|fold|from|function|gamma|gcd|get|goto|hash|help|hypot|if|inc|indent|index|infinity|info|input|insert|inspect|intersection|invert|join|keys|kurtosis|last|let|levenshtein|lighten|list|ln|log|loop|lower|mail|map|match|max|maybe|median|min|mod|module|mul|nand|neg|new|nor|normalize|not|now|null|open|or|outdent|pad|panic|path|pause|permissions|permutate|pi|pop|pow|powerset|powmod|prefix|print|prints|process|product|query|random|range|read|relative|remove|rename|render|repeat|replace|request|return|reverse|round|sample|saturate|script|sec|sech|select|serve|set|shl|shr|shuffle|sin|sinh|size|skewness|slice|sort|split|sqrt|squeeze|stack|strip|sub|suffix|sum|switch|symbols|symlink|sys|take|tan|tanh|terminal|to|true|truncate|try|type|union|unique|unless|until|unzip|upper|values|var|variance|volume|webview|while|with|wordwrap|write|xnor|xor|zip)\b(?!:))""")
            ])
        )

        for line in highlighted:
            echo "{initialSep}{initialPadding}{line}".fmt

#=======================================
# Methods
#=======================================


proc getInfo*(objName: string, objValue: Value, aliases: SymbolDict): ValueDict =
    ## Returns a Dictionary containing information about a object

    result = initOrderedTable[string,Value]()

    result["name"]    = newString(objName)
    result["address"] = newString(fmt("{cast[uint](objValue):#X}"))
    result["type"]    = newType(objValue.kind)
    
    if objValue.info.isNil:
        return
    
    # ====> In case of 'info attribute be present: 
    
    if objValue.info.descr != "":  result["description"] = newString(objValue.info.descr) 
    if objValue.info.module != "": result["module"]      = newString(objValue.info.module)
    
    when defined(DOCGEN):
        
        const repo = "https://github.com/arturo-lang/arturo/blob/v0.9.83/src/library/"
        
        result["example"] = newStringBlock(splitExamples(objValue.info.example))
        if objValue.info.line != 0:
            result["line"] = newInteger(objValue.info.line)
            result["source"] = newString(
                    repo & 
                    result["module"].s & 
                    ".nim#L" & 
                    $(result["line"].i))


    if objValue.info.kind != Function:
        return
    
    # ====> In case of 'objValue being a function: 

    template validSpec(value: Value, spec: untyped): bool =
        ## Checks if the function value has arguments or attributes
        ## * spec: can be 'args or 'attrs
        value.info.spec.len > 0 and (toSeq(value.info.spec.keys))[0] != ""
        
    template listTypes(values: untyped): Value =
        ## Converts each value of values to Type 
        ## and returns it into a new Block
        newBlock collect(for val in values: newType val)
        
    var funArgs  = initOrderedTable[string,Value]()
    var funAttrs = initOrderedTable[string,Value]()
    
    if objValue.validSpec(args):        
        for key, spec in objValue.args: 
            funArgs[key] = spec.listTypes()

    if objValue.validSpec(attrs):            
        for key, objAttr in objValue.info.attrs:
            var attribute = initOrderedTable[string,Value]()
            
            let spec      = objAttr[0]
            let descr     = objAttr[1]

            attribute["types"]       = spec.listTypes()
            attribute["description"] = newString(descr)
            funAttrs[key]            = newDictionary(attribute)
            
    result["args"]    = newDictionary(funArgs)
    result["attrs"]   = newDictionary(funAttrs)
    result["returns"] = if objValue.info.returns.len == 0: 
        newBlock(@[newType(Nothing)]) else: objValue.info.returns.listTypes()

    let alias = getAlias(objName, aliases)
    if alias[0] != "":
        result["alias"]  = newString(alias[0])
        result["infix?"] = newLogical(alias[1] == InfixPrecedence)


# TODO(Helpers/helper) embed "see also" functions in info screens
#  related: https://github.com/arturo-lang/arturo/issues/466#issuecomment-1065274429
#  labels: helpers, library, repl, enhancement

proc printInfo*(n: string, v: Value, aliases: SymbolDict) =
    # Get type + possible module (if it's a builtin)
    var typeStr = valueKind(v)
    # if v.kind==Function and v.fnKind==BuiltinFunction:
    #     typeStr &= " /" & v.module.toLowerAscii()

    typeStr = alignLeft(typeStr,30)

    # Get address
    var address = align(fmt("{cast[uint](v):#X}"), 32)
    # if v.kind==Function and v.fnKind==BuiltinFunction:
    #     address = align(fmt("builtin\\{v.module.toLowerAscii()}"), 32)

    # Print header
    printLine()
    if (not v.info.isNil) and v.info.module != "":
        let mdl = v.info.module
        printOneData(n,fmt("{typeStr}{fg(grayColor)}{align(mdl,32)}"),bold(magentaColor),resetColor)
    else:
        printOneData(n,fmt("{typeStr}{fg(grayColor)}{address}"),bold(magentaColor),resetColor)

    # Print alias if it exists
    let alias = getAlias(n, aliases)
    if alias[0]!="":
        printOneData("alias",alias[0])

    # Print separator
    printLine()

    # If it's a function or builtin constant,
    # print its description/info
    if not v.info.isNil:
        var desc: string = v.info.descr
        
        for d in getShortData(desc):
            printOneData("",d)
        printLine()

        # If it's a function,
        # print more details
        if v.info.kind==Function:
            printMultiData("usage", getUsageForFunction(n,v), bold(greenColor))
            let opts = getOptionsForFunction(v)
            if opts.len>0:
                printEmptyLine()
                printMultiData("options",opts,bold(greenColor))
                
            printEmptyLine()

            printOneData("returns",getTypeString(v.info.returns),bold(greenColor),fg(grayColor))
            printLine()

            # if v.info.example.strip()!="" and withExamples:
            #     echo initialSep & repeat(' ', 36) & "EXAMPLES" & repeat(' ', 36) 
            #     printLine()
            #     printEmptyLine()
            #     let examples = splitExamples(v.info.example)
            #     for i, example in examples:
            #         syntaxHighlight(example)
            #         if i!=examples.len - 1:
            #             printEmptyLine()
            #             printLine('.')
            #             printEmptyLine()
            #     printEmptyLine()
            #     printLine()
