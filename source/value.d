/*****************************************************************
 * Arturo
 * 
 * Programming Language + Interpreter
 * (c) 2019 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: value.d
 *****************************************************************/

module value;

// Imports

import core.checkedint;

import std.algorithm;
import std.array;
import std.bigint;
import std.conv;
import std.digest.sha;
import std.range;
import std.stdio;
import std.string;

import parser.statements;

import func;

import art.json;
import std.json;

import panic;

import context;
import globals;

import var;

// Aliases

alias nV = ValueType.numberValue;
alias rV = ValueType.realValue;
alias sV = ValueType.stringValue;
alias bV = ValueType.booleanValue;
alias aV = ValueType.arrayValue;
alias dV = ValueType.dictionaryValue;
alias fV = ValueType.functionValue;
alias xV = ValueType.anyValue;
alias noV = ValueType.noValue;

// Definitions

enum ValueType : string
{
    numberValue = "Number",
    realValue = "Real",
    stringValue = "String",
    booleanValue = "Boolean",
    arrayValue = "Array",
    dictionaryValue = "Dictionary",
    functionValue = "Function",
    noValue = "Null",
    anyValue = "Any"
}

union ValueContent
{
    long i;
    BigInt bi;
    real r;
    string s;
    bool b;
    Func f;
    Value[] a;
    Context d;
}

// Aliases

auto I(alias symbol,int index)(){ return symbol[index].content.i; }
auto I(alias symbol)(){ return symbol.content.i; }
auto BI(alias symbol,int index)(){ return symbol[index].content.bi; }
auto BI(alias symbol)(){ return symbol.content.bi; }

auto R(alias symbol,int index)(){ return symbol[index].content.r; }
auto R(alias symbol)(){ return symbol.content.r; }
auto S(alias symbol,int index)(){ return symbol[index].content.s; }
auto S(alias symbol)(){ return symbol.content.s; }
auto F(alias symbol,int index)(){ return symbol[index].content.f; }
auto F(alias symbol)(){ return symbol.content.f; }
auto B(alias symbol,int index)(){ return symbol[index].content.b; }
auto B(alias symbol)(){ return symbol.content.b; }
auto A(alias symbol,int index)(){ return symbol[index].content.a; }
auto A(alias symbol)(){ return symbol.content.a; }
auto D(alias symbol,int index)(){ return symbol[index].content.d; }
auto D(alias symbol)(){ return symbol.content.d; }

// Functions

class Value {

    ValueType type;
    ValueContent content;
    bool isBig;

    this() { 
        type = ValueType.noValue; 
    }

    this(int v) { 
        type = ValueType.numberValue; 
        isBig = false;  
        content.i = v;
    }
    
    this(BigInt v) { 
        type = ValueType.numberValue; 
        isBig = true; 
        content.bi = v; 
    }

    this(long v) { 
        type = ValueType.numberValue; 
        content.i = v; 
    }

    this(string v, bool bignum=false) { 
        if (bignum) {
            isBig = true;
            type = ValueType.numberValue;
            content.bi = BigInt(v);
        }
        else {
            type = ValueType.stringValue;   
            content.s = v; 
        }
    }

    this(bool v) { 
        type = ValueType.booleanValue;    
        content.b = v; 
    }

    this(real v) { 
        type = ValueType.realValue;       
        content.r = v; 
    }

    this(Statements v) {
        type = ValueType.functionValue;   
        content.f = new Func("", v); 
    }

    this(Statements v, string[] ids) { 
        type = ValueType.functionValue;   
        content.f = new Func("", v, [], ids); 
    }

    this(Value[] v)
    {
        type = ValueType.arrayValue;
        content.a = [];
        foreach (Value i; v) {
            content.a ~= i;
        }
    }

    this(Value[Value] v)
    {
        type = ValueType.dictionaryValue;
        content.d =  new Context(ContextType.dictionaryContext);
        foreach (Value k, Value c; v) {
            content.d._varSet(k.content.s, c);
        }
    }

    this(string[] v)
    {
        type = ValueType.arrayValue;
        content.a = [];
        foreach (string s; v) {
            content.a ~= new Value(s);
        }
    }

    this(string[string] v)
    {
        type = ValueType.dictionaryValue;
        content.d = new Context(ContextType.dictionaryContext);
        foreach (string k, string c; v) {
            content.d._varSet(k, new Value(c));
        }
    }

    this(Value v)
    {
        type = v.type;

        switch (type)
        {
            case ValueType.numberValue : if (isBig) { content.bi = v.content.bi; } else { content.i = v.content.i; } break;
            case ValueType.realValue : content.r = v.content.r; break;
            case ValueType.stringValue : content.s = v.content.s; break;
            case ValueType.booleanValue : content.b = v.content.b; break;
            case ValueType.functionValue : content.f = v.content.f; break;
            case ValueType.arrayValue : 
                content.a = [];
                foreach (Value vv; v.content.a) content.a ~= new Value(vv);
                break;
            case ValueType.dictionaryValue :
                content.d = new Context(ContextType.dictionaryContext);
                foreach (Var va; v.content.d.variables)
                    content.d._varSet(va.name, va.value); break;
            default: break;
        }
    }

    this(const Value v) 
    {
        type = v.type;

        switch (type)
        {
            case ValueType.numberValue : if (isBig) { content.bi = v.content.bi; } else { content.i = v.content.i; } break;
            case ValueType.realValue : content.r = v.content.r; break;
            case ValueType.stringValue : content.s = v.content.s; break;
            case ValueType.booleanValue : content.b = v.content.b; break;
            case ValueType.functionValue : content.f = cast(Func)(v.content.f); break;
            case ValueType.arrayValue : 
                content.a = [];
                foreach (const Value vv; v.content.a) content.a ~= new Value(vv);
                break;
            case ValueType.dictionaryValue :
                content.d = new Context(ContextType.dictionaryContext);
                foreach (const Var va; v.content.d.variables)
                    content.d._varSet(va.name, new Value(va.value)); break;
            default: break;
        }
    }

    static Value dictionary() {
        Value v = new Value();
        v.type = ValueType.dictionaryValue;
        v.content.d = new Context(ContextType.dictionaryContext);
        return v;
    }

    bool arrayContains(Value item)
    {
        foreach (Value v; content.a)
            if (v==item) return true;

        return false;
    }

    bool dictionaryContains(Value item) {
        return content.d._varExists(item.content.s);
    }

    Value[] arrayValues() {
        return content.a;
    }

    Value removeDuplicatesFromArray() {
        Value ret = new Value(cast(Value[])[]);

        foreach (i, Value v; content.a) {
            if (!ret.arrayContains(v)) {
                ret.content.a ~= v;
            }
        }
        return ret;
    }

    Value removeValueFromArray(Value object) {
        foreach (i, Value v; content.a) {
            if (object==v) {
                return removeIndexFromArray(i);
            }
        }

        return this;
    }

    const Value removeValueFromArrayImmut(const Value object) {
        Value ret = new Value(this);
        foreach (i, Value v; ret.content.a) {
            if (object==v) {
                return ret.removeIndexFromArrayImmut(i);
            }
        }

        return ret;
    }

    Value removeValueFromDict(Value object) {
        foreach (Var va; content.d.variables) {
            if (va.value==object) content.d._varUnset(va.name);
        }

        return this;
    }
/*
    const Value removeValueFromDictImmut(const Value object) {
        Value ret = new Value(this);
        foreach (Var va; content.d.variables) {
            if (va.value==object) content.d._varUnset(va.name);
        }

        return ret;
    }*/

    const Value removeIndexFromArrayImmut(long index) {
        Value ret = new Value(this);
        ret.content.a = ret.content.a.remove(index);
        return ret;
    }

    Value removeIndexFromArray(long index) {
        content.a = content.a.remove(index);
        return this;
    }

    Value removeIndexFromDict(string key) {
        content.d._varUnset(key);

        return this;
    }

    Value getValueFromDictValue(Value key)
    {
        if (content.d._varExists(key.content.s))
            return content.d._varGet(key.content.s).value;
        else return null;
    }

    Value getValueFromDict(string key)
    {
        if (content.d._varExists(key)) {
            return content.d._varGet(key).value;
        }

        return null;
    }

    const Value getValueFromDictImmut(string key)
    {
        Value cp = new Value(this);
        if (cp.content.d._varExists(key)) {
            return cp.content.d._varGet(key).value;
        }

        return null;
    }

    void setValueForDictValue(Value key, Value val) {
        content.d._varSet(key.content.s, val);
    }

    void setValueForDict(string key, Value val) {
        //writeln("in setValueForDict: before");
        content.d._varSet(key, val);

        if (val.type==fV) {
            val.content.f.parentThis = this;
            val.content.f.parentContext = content.d;
        }
        //writeln("in setValueForDict: after");
    }

    void setValueForDictRegardless(string key, Value val) {
        content.d._varSet(key,val);
    }

    const Value mergeDictWith(const Value dictB) {
        Value cp = new Value(this);

        foreach (const Var v; dictB.content.d.variables) {
            cp.setValueForDictRegardless(new Value(v.name).content.s, new Value(v.value));
        }

        return cp;
    }

    bool arrayContainsSameTypeValues() {
        ValueType previousType = ValueType.noValue;
        foreach (Value v; content.a) {
            if (previousType==ValueType.noValue)
                previousType = v.type;
            else {
                if (previousType!=v.type)
                    return false;
            }
        }
        return true;
    }

    Value arraySort() {
        if (arrayContainsSameTypeValues()) {
            if (content.a.length>0) {
                ValueType t = content.a[0].type;
                switch (t) {
                    case nV: return new Value(content.a.map!(v => v.content.i).array.sort().map!(v => new Value(v)).array);
                    case sV: return new Value(content.a.map!(v => v.content.s).array.sort().map!(v => new Value(v)).array);
                    default: return null;
                }
            }
            else return null;
        }
        else return null;
    }

    /************************************
     ARITHMETIC OPERATIONS
     ************************************/
     /*
    Value opUnary(string op)() const if (op == "-")
    {
        if (type==ValueType.numberValue)
        {
            return new Value(-1 * content.i);
        }
        else if (type==ValueType.realValue)
        {
            return new Value(-1 * content.r);
        }

        //throw new ERR_UndefinedOperation(op,this,new Value("u-"));

        return new Value(0);
    }*/

    Value opBinary(string op)(in Value rhs) const if (op == "+")
    {
        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(BigInt(lhs + rhs.content.bi)); } else { return new Value(BigInt(lhs + rhs.content.i)); }
                    case ValueType.realValue        : throw new ERR_OperationNotPermitted("(+)","Big Number","Real");
                    case ValueType.stringValue      : return new Value(to!string(lhs) ~ rhs.content.s);
                    case ValueType.booleanValue     : if (rhs.content.b) return new Value(lhs + 1); else return new Value(lhs);
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(+)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(+)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(+)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }

            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(BigInt(lhs + rhs.content.bi)); } 
                                                      else { 
                                                        bool overflow;
                                                        auto result = adds(lhs, rhs.content.i, overflow);
                                                        if (!overflow) return new Value(result);
                                                        else return new Value(BigInt(lhs) + BigInt(rhs.content.i)); 
                                                      }
                    case ValueType.realValue        : return new Value(lhs + rhs.content.r);
                    case ValueType.stringValue      : return new Value(to!string(lhs) ~ rhs.content.s);
                    case ValueType.booleanValue     : if (rhs.content.b) {
                                                        bool overflow;
                                                        auto result = adds(lhs, 1, overflow);
                                                        if (!overflow) return new Value(result);
                                                        else return new Value(BigInt(lhs) + BigInt(1));
                                                      } else return new Value(lhs);
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(+)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(+)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(+)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.realValue        : return new Value(lhs + rhs.content.r);
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(+)","Real","Big Number"); } else { return new Value(lhs + rhs.content.i); }
                case ValueType.stringValue      : return new Value(to!string(lhs) ~ rhs.content.s);
                case ValueType.booleanValue     : return new Value(lhs + to!int(rhs.content.b));
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(+)","Real","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(+)","Real","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(+)","Real","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { return new Value(lhs ~ to!string(rhs.content.bi)); } else { return new Value(lhs ~ to!string(rhs.content.i)); }
                case ValueType.realValue        : return new Value(lhs ~ to!string(rhs.content.r));
                case ValueType.stringValue      : return new Value(lhs ~ rhs.content.s);
                case ValueType.booleanValue     : return new Value(lhs ~ rhs.stringifyImmut());
                case ValueType.arrayValue       : return new Value(lhs ~ rhs.stringifyImmut());
                case ValueType.dictionaryValue  : return new Value(lhs ~ rhs.stringifyImmut());
                case ValueType.functionValue    : return new Value(lhs ~ rhs.stringifyImmut());
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.booleanValue)
        {
            bool lhs = content.b;

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { return new Value(to!int(lhs) + rhs.content.bi); }    
                                                  else { 
                                                    bool overflow;
                                                    auto result = adds(to!int(lhs), rhs.content.i, overflow);
                                                    if (!overflow) return new Value(result);
                                                    else return new Value(BigInt(to!int(lhs)) + BigInt(rhs.content.i));
                                                  }
                case ValueType.realValue        : return new Value(to!int(lhs) + to!int(rhs.content.r));
                case ValueType.stringValue      : return new Value(to!string(lhs) ~ rhs.content.s);
                case ValueType.booleanValue     : return new Value(to!int(lhs) + to!int(rhs.content.b));
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(+)","Boolean","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(+)","Boolean","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(+)","Boolean","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.arrayValue)
        {
            Value newV = new Value(cast(Value)(this));
            if (rhs.type!=ValueType.arrayValue)
            {
                newV.content.a ~= cast(Value)rhs;
            }
            else
            {
                foreach (const Value vv; rhs.content.a)
                {
                    newV.content.a ~= cast(Value)vv;
                }
            }
            return newV;
        }
        else if (type==ValueType.dictionaryValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(+)","Dictionary","Number"); 
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(+)","Dictionary","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(+)","Dictionary","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(+)","Dictionary","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(+)","Dictionary","Array");
                case ValueType.dictionaryValue  : return mergeDictWith(rhs);
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(+)","Dictionary","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.functionValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(+)","Function","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(+)","Function","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(+)","Function","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(+)","Function","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(+)","Function","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(+)","Function","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(+)","Function","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.noValue)
        {
            return new Value(); // null
        }

        return new Value(); // Control never reaches this point
    }

    Value opBinary(string op)(in Value rhs) const if (op == "-")
    {
        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(BigInt(lhs - rhs.content.bi)); } else { return new Value(BigInt(lhs - rhs.content.i)); }
                    case ValueType.realValue        : throw new ERR_OperationNotPermitted("(-)","Big Number","Real");
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(-)","Number","String");
                    case ValueType.booleanValue     : if (rhs.content.b) return new Value(lhs - 1); else return new Value(lhs);
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(-)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(-)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(-)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(BigInt(lhs - rhs.content.bi)); } 
                                                      else { 
                                                        bool overflow;
                                                        auto result = subs(lhs, rhs.content.i, overflow);
                                                        if (!overflow) return new Value(result);
                                                        else return new Value(BigInt(lhs) - BigInt(rhs.content.i)); 
                                                      }
                    case ValueType.realValue        : return new Value(lhs - rhs.content.r);
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(-)","Number","String");
                    case ValueType.booleanValue     : if (rhs.content.b) {
                                                        bool overflow;
                                                        auto result = subs(lhs, 1, overflow);
                                                        if (!overflow) return new Value(result);
                                                        else return new Value(BigInt(lhs) - BigInt(1));
                                                      } else return new Value(lhs);
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(-)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(-)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(-)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(-)","Real","Big Number"); } else { return new Value(lhs - rhs.content.i); }
                case ValueType.realValue        : return new Value(lhs - rhs.content.r);
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(-)","Real","String");
                case ValueType.booleanValue     : return new Value(lhs - to!int(rhs.content.b));
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(-)","Real","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(-)","Real","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(-)","Real","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { return new Value(replace(lhs, to!string(rhs.content.bi),"")); } else { return new Value(replace(lhs, to!string(rhs.content.i),"")); }
                case ValueType.realValue        : return new Value(replace(lhs, to!string(rhs.content.r),""));
                case ValueType.stringValue      : return new Value(replace(lhs, rhs.content.s,""));
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(-)","String","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(-)","String","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(-)","String","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(-)","String","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.booleanValue)
        {
            bool lhs = content.b;

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { return new Value(to!int(lhs) - rhs.content.bi); }    
                                                  else { 
                                                    bool overflow;
                                                    auto result = subs(to!int(lhs), rhs.content.i, overflow);
                                                    if (!overflow) return new Value(result);
                                                    else return new Value(BigInt(to!int(lhs)) - BigInt(rhs.content.i));
                                                  }
                case ValueType.realValue        : return new Value(to!int(lhs) - to!int(rhs.content.r));
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(-)","Boolean","String");
                case ValueType.booleanValue     : return new Value(to!int(lhs) - to!int(rhs.content.b));
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(-)","Boolean","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(-)","Boolean","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(-)","Boolean","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.arrayValue)
        {
            return removeValueFromArrayImmut(rhs);
        }
        else if (type==ValueType.dictionaryValue)
        {   
            Value cp = new Value(this);
            Value cprhs = new Value(rhs);
            return cp.removeValueFromDict(cprhs);
        }
        else if (type==ValueType.functionValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(-)","Function","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(-)","Function","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(-)","Function","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(-)","Function","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(-)","Function","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(-)","Function","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(-)","Function","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.noValue)
        {
            return new Value(); // null
        }

        return new Value(); // Control never reaches this point
    }

    Value opBinary(string op)(in Value rhs) const if (op == "*")
    {
        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(BigInt(lhs * rhs.content.bi)); } else { return new Value(BigInt(lhs * rhs.content.i)); }
                    case ValueType.realValue        : throw new ERR_OperationNotPermitted("(-)","Big Number","Real");
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","Big Number","String");
                    case ValueType.booleanValue     : if (rhs.content.b) return new Value(lhs * 1); else return new Value(0);
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","Big Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(BigInt(lhs * rhs.content.bi)); } 
                                                      else { 
                                                        bool overflow;
                                                        auto result = muls(lhs, rhs.content.i, overflow);
                                                        if (!overflow) return new Value(result);
                                                        else return new Value(BigInt(lhs) * BigInt(rhs.content.i)); 
                                                      }
                    case ValueType.realValue        : return new Value(lhs * rhs.content.r);
                    case ValueType.stringValue      : return new Value(replicate(rhs.content.s,lhs));
                    case ValueType.booleanValue     : if (rhs.content.b) return new Value(lhs * 1); else return new Value(0);
                    case ValueType.arrayValue       : return new Value(replicate(cast(Value[])(rhs.content.a),lhs));
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(*)","Real","Big Number"); } else { return new Value(lhs * rhs.content.i); }
                case ValueType.realValue        : return new Value(lhs * rhs.content.r);
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","Real","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(*)","Real","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","Real","Real");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Real","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Real","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }

        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(*)","String","Big Number"); } else { return new Value(replicate(lhs,rhs.content.i)); } 
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(*)","String","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","String","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(*)","String","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","String","String");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","String","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","String","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.booleanValue)
        {
            bool lhs = content.b;

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { return new Value(to!int(lhs) - rhs.content.bi); }    
                                                  else { 
                                                    bool overflow;
                                                    auto result = muls(to!int(lhs), rhs.content.i, overflow);
                                                    if (!overflow) return new Value(result);
                                                    else return new Value(BigInt(to!int(lhs)) * BigInt(rhs.content.i));
                                                  }
                case ValueType.realValue        : return new Value(to!int(lhs) * to!int(rhs.content.r));
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","Boolean","String");
                case ValueType.booleanValue     : return new Value(to!int(lhs) * to!int(rhs.content.b));
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","Boolean","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Boolean","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Boolean","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.arrayValue)
        {
            Value[] lhs = cast(Value[])(content.a);

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(*)","Array","Big Number"); } else { return new Value(replicate(lhs,rhs.content.i)); }
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(*)","Array","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","Array","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(*)","Array","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","Array","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Array","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Array","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.dictionaryValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(*)","Dictionary","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(*)","Dictionary","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","Dictionary","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(*)","Dictionary","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","Dictionary","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Dictionary","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Dictionary","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.functionValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(*)","Function","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(*)","Function","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(*)","Function","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(*)","Function","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(*)","Function","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(*)","Function","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(*)","Function","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.noValue)
        {
            return new Value(); // null
        }

        return new Value(); // Control never reaches this point
    }

    Value opBinary(string op)(in Value rhs) const if (op == "/")
    {
        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(lhs / rhs.content.bi); } else { return new Value(lhs / rhs.content.i); }
                    case ValueType.realValue        : throw new ERR_OperationNotPermitted("(/)","Big Number","Real");
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Number","String");
                    case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Number","Boolean");
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(lhs / rhs.content.bi); } else { return new Value(lhs / rhs.content.i); }
                    case ValueType.realValue        : return new Value(lhs / rhs.content.r);
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Number","String");
                    case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Number","Boolean");
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(/)","Real","Big Number"); } else { return new Value(lhs / rhs.content.i); }
                case ValueType.realValue        : return new Value(lhs / rhs.content.r);
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Real","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Real","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Real","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Real","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Real","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : Value[] ret;
                                                  string resp = "";
                                                  if (rhs.isBig) {
                                                      for (int kk=0; kk<lhs.length; kk++){
                                                        resp ~= content.s[kk];
                                                        if ((kk+1)%rhs.content.bi==0){ret ~= new Value(resp);resp = "";}
                                                      }
                                                  }
                                                  else {
                                                      for (int kk=0; kk<lhs.length; kk++){
                                                        resp ~= content.s[kk];
                                                        if ((kk+1)%rhs.content.i==0){ret ~= new Value(resp);resp = "";}
                                                      }
                                                  }
                                                  return new Value(ret);
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(/)","String","Real");
                case ValueType.stringValue      : return new Value(lhs.split(rhs.content.s));
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","String","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","String","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","String","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","String","Function");
                default                         : break;
            }
        }
        else if (type==ValueType.booleanValue)
        {
            bool lhs = content.b;

            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(/)","Boolean","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(/)","Boolean","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Boolean","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Boolean","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Boolean","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Boolean","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Boolean","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.arrayValue)
        {
            Value[] lhs = cast(Value[])(content.a);

            switch (rhs.type)
            {
                case ValueType.numberValue      : Value[] ret;
                                                  string resp = "";
                                                  if (rhs.isBig) {
                                                      for (int kk=0; kk<lhs.length; kk++){
                                                        if ((kk+1)%rhs.content.bi==0){ret ~= new Value(content.a[kk]);}
                                                      }
                                                  }
                                                  else {
                                                      for (int kk=0; kk<lhs.length; kk++){
                                                        if ((kk+1)%rhs.content.i==0){ret ~= new Value(content.a[kk]);}
                                                      }
                                                  }
                                                  return new Value(ret);
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(/)","Array","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Array","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Array","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Array","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Array","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Array","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.dictionaryValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(/)","Dictionary","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(/)","Dictionary","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Dictionary","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Dictionary","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Dictionary","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Dictionary","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Dictionary","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.functionValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(/)","Function","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(/)","Function","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(/)","Function","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(/)","Function","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(/)","Function","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(/)","Function","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(/)","Function","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.noValue)
        {
            return new Value(); // null
        }

        return new Value(); // Control never reaches this point
    }

    Value opBinary(string op)(in Value rhs) const if (op == "%")
    {
        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(lhs % rhs.content.bi); } else { return new Value(lhs % rhs.content.i); }
                    case ValueType.realValue        : throw new ERR_OperationNotPermitted("(%)","Big Number","Real");
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Number","String");
                    case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Number","Boolean");
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return new Value(lhs % rhs.content.bi); } else { return new Value(lhs % rhs.content.i); }
                    case ValueType.realValue        : return new Value(lhs % rhs.content.r);
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Number","String");
                    case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Number","Boolean");
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(%)","Real","Big Number"); } else { return new Value(lhs % rhs.content.i); }
                case ValueType.realValue        : return new Value(lhs % rhs.content.r);
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Real","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Real","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Real","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Real","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Real","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) {
                                                    long len = lhs.length % rhs.content.bi;
                                                    return new Value(lhs[$-len..$]);
                                                  } 
                                                  else {
                                                    long len = lhs.length % rhs.content.i;
                                                    return new Value(lhs[$-len..$]);
                                                  }
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(%)","String","Real");
                case ValueType.stringValue      : return new Value(lhs.split(rhs.content.s));
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","String","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","String","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","String","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","String","Function");
                default                         : break;
            }
        }
        else if (type==ValueType.booleanValue)
        {
            bool lhs = content.b;

            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(%)","Boolean","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(%)","Boolean","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Boolean","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Boolean","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Boolean","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Boolean","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Boolean","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.arrayValue)
        {
            Value[] lhs = cast(Value[])(content.a);

            switch (rhs.type)
            {
                case ValueType.numberValue      : if (rhs.isBig) {
                                                    long len = lhs.length % rhs.content.bi;
                                                    return new Value(lhs[$-len..$]);
                                                  } 
                                                  else {
                                                    long len = lhs.length % rhs.content.i;
                                                    return new Value(lhs[$-len..$]);
                                                  }
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(%)","Array","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Array","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Array","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Array","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Array","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Array","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.dictionaryValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(%)","Dictionary","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(%)","Dictionary","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Dictionary","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Dictionary","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Dictionary","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Dictionary","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Dictionary","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.functionValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(%)","Function","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(%)","Function","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(%)","Function","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(%)","Function","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(%)","Function","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(%)","Function","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(%)","Function","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.noValue)
        {
            return new Value(); // null
        }

        return new Value(); // Control never reaches this point
    }

    Value opBinary(string op)(in Value rhs) const if (op == "^^")
    {
        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(^)","Big Number","Big Number"); } else { throw new ERR_OperationNotPermitted("(^)","Big Number","Number"); }
                    case ValueType.realValue        : throw new ERR_OperationNotPermitted("(^)","Big Number","Real");
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Number","String");
                    case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Number","Boolean");
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(^)","Number","Big Number"); } else { return new Value(lhs ^^ rhs.content.i); }
                    case ValueType.realValue        : return new Value(lhs ^^ rhs.content.r);
                    case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Number","String");
                    case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Number","Boolean");
                    case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Number","Array");
                    case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Number","Dictionary");
                    case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Number","Function");
                    case ValueType.noValue          : return new Value(); // null
                    default                         : break;
                }
            }
            
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_OperationNotPermitted("(^)","Real","Big Number"); } else { return new Value(lhs ^^ rhs.content.i); }
                case ValueType.realValue        : return new Value(lhs ^^ rhs.content.r);
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Real","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Real","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Real","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Real","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Real","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(^)","String","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(^)","String","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","String","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","String","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","String","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","String","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","String","Function");
                default                         : break;
            }
        }
        else if (type==ValueType.booleanValue)
        {
            bool lhs = content.b;

            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(^)","Boolean","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(^)","Boolean","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Boolean","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Boolean","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Boolean","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Boolean","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Boolean","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.arrayValue)
        {
            Value[] lhs = cast(Value[])(content.a);

            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(^)","Array","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(^)","Array","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Array","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Array","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Array","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Array","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Array","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.dictionaryValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(^)","Dictionary","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(^)","Dictionary","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Dictionary","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Dictionary","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Dictionary","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Dictionary","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Dictionary","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.functionValue)
        {
            switch (rhs.type)
            {
                case ValueType.numberValue      : throw new ERR_OperationNotPermitted("(^)","Function","Number");
                case ValueType.realValue        : throw new ERR_OperationNotPermitted("(^)","Function","Real");
                case ValueType.stringValue      : throw new ERR_OperationNotPermitted("(^)","Function","String");
                case ValueType.booleanValue     : throw new ERR_OperationNotPermitted("(^)","Function","Boolean");
                case ValueType.arrayValue       : throw new ERR_OperationNotPermitted("(^)","Function","Array");
                case ValueType.dictionaryValue  : throw new ERR_OperationNotPermitted("(^)","Function","Dictionary");
                case ValueType.functionValue    : throw new ERR_OperationNotPermitted("(^)","Function","Function");
                case ValueType.noValue          : return new Value(); // null
                default                         : break;
            }
        }
        else if (type==ValueType.noValue)
        {
            return new Value(); // null
        }

        return new Value(); // Control never reaches this point
    }

    override bool opEquals(Object rh)
    {
        Value rhs = cast(Value)(rh);

        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return (lhs==rhs.content.bi); } else { return (lhs==rhs.content.i); }
                    case ValueType.realValue        : return false; //return (lhs == rhs.content.r);
                    case ValueType.booleanValue     : return false; //return (lhs == rhs.content.b);
                    default                         : return false;
                }

            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { return (lhs==rhs.content.bi); } else { return (lhs==rhs.content.i); }
                    case ValueType.realValue        : return (lhs == rhs.content.r);
                    case ValueType.booleanValue     : return (lhs == rhs.content.b);
                    default                         : return false;
                }
            }
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { return false; /*return (lhs==rhs.content.bi);*/ } else { return (lhs==rhs.content.i); }
                case ValueType.realValue        : return (lhs == rhs.content.r);
                case ValueType.booleanValue     : return (lhs == rhs.content.b);
                default                         : return false;
            }
        }
        else if (type==ValueType.stringValue)
        {
            if (rhs.type==ValueType.stringValue)
            {
                return (content.s == rhs.content.s);
            }
            else return false;
        }
        else if (type==ValueType.booleanValue) {
            bool lhs = content.b;

            switch (rhs.type) {
                case ValueType.numberValue      : if (rhs.isBig) { return false; /*return (lhs==rhs.content.bi);*/ } else { return (lhs==rhs.content.i); }
                case ValueType.realValue        : return false; //return (lhs == rhs.content.r);
                case ValueType.booleanValue     : return (lhs==rhs.content.b);
                default                         : return false;
            }
        }
        else if (type==ValueType.arrayValue) {
            Value[] lhs = content.a;

            if (lhs.length != rhs.content.a.length) return false;

            foreach (i, Value item; lhs) {
                if (item != rhs.content.a[i]) return false;
            }

            return true;
        }
        else if (type==ValueType.dictionaryValue) {
            Context lhs = content.d;
            foreach (Var v; lhs.variables) {
                Value dv = rhs.getValueFromDict(v.name);

                if (dv is null) { return false; }
                else {
                    if (v.value!=dv) return false;
                }
            }

            return true;
        }
        else if (type==ValueType.functionValue) {
            if (rhs.type==ValueType.functionValue)
            {
                return (content.f == rhs.content.f);
            }
            else return false;
        }
        else if (type==ValueType.noValue) {
            if (rhs.type==ValueType.noValue) return true;
            else return false;
        }

        return (false);
    }

    int opCmp(in Value rhs)
    {
        if (this==rhs) return 0;

        if (type==ValueType.numberValue)
        {
            if (isBig) {
                BigInt lhs = content.bi;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { if (lhs > rhs.content.bi) return 1; else return -1; } else { if (lhs > rhs.content.i) return 1; else return -1; }
                    case ValueType.realValue        : throw new ERR_CannotCompareTypesError("Big Number",rhs.type); /*if (lhs > rhs.content.r) return 1; else return -1;*/
                    default                         : throw new ERR_CannotCompareTypesError(type,rhs.type);
                }
            }
            else {
                long lhs = content.i;

                switch (rhs.type) 
                {
                    case ValueType.numberValue      : if (rhs.isBig) { if (lhs > rhs.content.bi) return 1; else return -1; } else { if (lhs > rhs.content.i) return 1; else return -1; }
                    case ValueType.realValue        : if (lhs > rhs.content.r) return 1; else return -1;
                    default                         : throw new ERR_CannotCompareTypesError(type,rhs.type);
                }
            }
        }
        else if (type==ValueType.realValue)
        {
            real lhs = content.r;

            switch (rhs.type) 
            {
                case ValueType.numberValue      : if (rhs.isBig) { throw new ERR_CannotCompareTypesError(type,"Big Number"); } else { if (lhs > rhs.content.i) return 1; else return -1; }
                case ValueType.realValue        : if (lhs > rhs.content.r) return 1; else return -1;
                default                         : throw new ERR_CannotCompareTypesError(type,rhs.type);
            }
        }
        else if (type==ValueType.stringValue)
        {
            string lhs = content.s;

            switch (rhs.type) 
            {
                case ValueType.stringValue      : if (lhs > rhs.content.s) return 1; else return -1;
                default                         : throw new ERR_CannotCompareTypesError(type,rhs.type);
            }
        }

        throw new ERR_CannotCompareTypesError(type,rhs.type);
        
        //return -1; 
    }

    string str() {
        switch (type) {
            case ValueType.numberValue      : if (isBig) { return to!string(content.bi); } else { return to!string(content.i); }
            case ValueType.realValue        : return to!string(content.r);
            case ValueType.booleanValue     : return to!string(content.b);
            case ValueType.stringValue      : return content.s;
            default                         : return "NULL";
        }
    }

    const string strImmut() {
        switch (type) {
            case ValueType.numberValue      : if (isBig) { return to!string(content.bi); } else { return to!string(content.i); }
            case ValueType.realValue        : return to!string(content.r);
            case ValueType.booleanValue     : return to!string(content.b);
            case ValueType.stringValue      : return content.s;
            default                         : return "NULL";
        }
    }

    string stringify(bool withquotes=true) {
        switch (type) {
            case ValueType.numberValue      : if (isBig) { return to!string(content.bi); } else { return to!string(content.i); }
            case ValueType.realValue        : return to!string(content.r);
            case ValueType.booleanValue     : return to!string(content.b);
            case ValueType.stringValue      : if (withquotes) { return "\"" ~ content.s ~ "\""; } else { return content.s; }
            case ValueType.functionValue    : return "<function: 0x" ~ to!string(&content.f) ~ ">";
            case ValueType.arrayValue       : 
                string ret = "#(";
                string[] items;
                foreach (Value v; content.a) {
                    items ~= v.stringify();
                }
                ret ~= items.join(" ");
                ret ~= ")";
                return ret;
            case ValueType.dictionaryValue  :
                string ret = "#{ ";
                string[] items;
                auto sortedKeys = content.d.variables.keys.array.sort();
                foreach (string key; sortedKeys) {
                //foreach (Value k, Value v; content.d) {
                    //items ~= k.content.s ~ " " ~ v.stringify();
                    Value v = getValueFromDict(key);
                    items ~= key ~ " " ~ v.stringify();
                }
                ret ~= items.join(", ");
                ret ~= " }";
                return ret;
            case ValueType.noValue          : return "null";
            default                         : return "NULL";
        }
    }

    const string stringifyImmut() {
        switch (type) {
            case ValueType.numberValue      : if (isBig) { return to!string(content.bi); } else { return to!string(content.i); }
            case ValueType.realValue        : return to!string(content.r);
            case ValueType.booleanValue     : return to!string(content.b);
            case ValueType.stringValue      : return "\"" ~ content.s ~ "\"";
            case ValueType.functionValue    : return "<function: 0x" ~ to!string(&content.f) ~ ">";
            case ValueType.arrayValue       : 
                string ret = "#(";
                string[] items;
                foreach (const Value v; content.a) {
                    items ~= v.stringifyImmut();
                }
                ret ~= items.join(" ");
                ret ~= ")";
                return ret;
            case ValueType.dictionaryValue  :
                string ret = "#{ ";
                string[] items;
                auto sortedKeys = content.d.variables.keys.array.sort();
                foreach (string key; sortedKeys) {
                //foreach (Value k, Value v; content.d) {
                    //items ~= k.content.s ~ " " ~ v.stringify();
                    Value v = getValueFromDictImmut(key);
                    items ~= key ~ " " ~ v.stringifyImmut();
                }
                ret ~= items.join(", ");
                ret ~= " }";
                return ret;
            case ValueType.noValue          : return "null";
            default                         : return "NULL";
        }
    }

    void print() {
        /*
        JSONValue j = generateJsonValue(this);
        string ret = j.toString();
        write(ret);
        */
        switch (type)
        {
            case ValueType.numberValue      :   if (isBig) { write(to!string(content.bi)); } else { write(to!string(content.i)); } break;
            case ValueType.realValue        :   write(to!string(content.r)); break;
            case ValueType.booleanValue     :   write(to!string(content.b)); break;
            case ValueType.stringValue      :   write(content.s); break;
            case ValueType.arrayValue       :
                write("[");
                for (int i=0; i<content.a.length; i++)
                {
                    content.a[i].print();
                    if (i!=content.a.length-1) write(",");
                }
                write("]"); break;

            case ValueType.dictionaryValue  :
                write("[");
                int i;
                foreach (Var v; content.d.variables)
                {
                    write(v.name);
                    write(" : ");
                    v.value.print();
                    if (i!=content.d.variables.length-1) write(",");
                    i++;
                }
                write("]"); break;
            default:
                break;
        }
    }

    override string toString() {
        string ret = "";
        switch (type)
        {
            case ValueType.numberValue      :   if (isBig) { ret ~= "bigint(" ~ to!string(content.bi) ~ ")"; } else { ret ~= "int(" ~ to!string(content.i) ~ ")"; } break;
            case ValueType.realValue        :   ret ~= "real(" ~ to!string(content.r) ~ ")"; break;
            case ValueType.booleanValue     :   ret ~= "bool(" ~ to!string(content.b) ~ ")"; break;
            case ValueType.stringValue      :   ret ~= "str(" ~ to!string("\"" ~ content.s ~ "\"") ~ ")"; break;
            case ValueType.arrayValue       :
                ret ~= "array([";
                for (int i=0; i<content.a.length; i++)
                {
                    ret ~= content.a[i].toString();
                    if (i!=content.a.length-1) ret ~= ", ";
                }
                ret ~= "])"; break;

            case ValueType.dictionaryValue  :
                ret ~= "dict([";
                int i;
                foreach (Var v; content.d.variables)
                {
                    ret ~= v.name ~ ":" ~ v.value.toString();
                    if (i!=content.d.variables.length-1) ret ~= ", ";
                    i++;
                }
                ret ~= "])"; break;
            default:
                break;
        }
        return ret;
    }

    const string toString() {
        string ret = "";
        switch (type)
        {
            case ValueType.numberValue      :   if (isBig) { ret ~= "bigint(" ~ to!string(content.bi) ~ ")"; } else { ret ~= "int(" ~ to!string(content.i) ~ ")"; } break;
            case ValueType.realValue        :   ret ~= "real(" ~ to!string(content.r) ~ ")"; break;
            case ValueType.booleanValue     :   ret ~= "bool(" ~ to!string(content.b) ~ ")"; break;
            case ValueType.stringValue      :   ret ~= "str(" ~ to!string("\"" ~ content.s ~ "\"") ~ ")"; break;
            case ValueType.arrayValue       :
                ret ~= "array([";
                for (int i=0; i<content.a.length; i++)
                {
                    ret ~= content.a[i].toString();
                    if (i!=content.a.length-1) ret ~= ", ";
                }
                ret ~= "])"; break;

            case ValueType.dictionaryValue  :
                ret ~= "dict([";
                int i;
                foreach (const Var v; content.d.variables)
                {
                    ret ~= v.name ~ ":" ~ v.value.toString();
                    if (i!=content.d.variables.length-1) ret ~= ", ";
                    i++;
                }
                ret ~= "])"; break;
            default:
                break;
        }
        return ret;
    }

    alias HashValue = (X) => toHexString((new SHA1Digest()).digest(X));

    string hash() {
        switch (type) {
            case ValueType.numberValue      :   if (isBig) { return "BIG"; } else { return HashValue(to!string(content.i)); }
            case ValueType.realValue        :   return HashValue(to!string(content.r));
            case ValueType.stringValue      :   return HashValue(content.s);
            case ValueType.booleanValue     :   return HashValue(to!string(content.b));
            case ValueType.arrayValue       :   return HashValue(content.a.map!(v=> v.hash()).join(""));
            case ValueType.dictionaryValue  :   string ret = "";
                                                foreach (Var v; content.d.variables) {
                                                    ret ~= (new Value(v.name)).hash() ~ v.value.hash();
                                                }
                                                return HashValue(ret);
            case ValueType.functionValue    :   return HashValue(to!string(&content.f));
            case ValueType.noValue          :   return "NIL";
            default                         :   return "";
        }
    }

    ~this()
    {
        debug writeln("Destroying: " ~ to!string(this));
    }
}