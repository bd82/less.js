@{%
  function sel(match, indices) {
    return match.map(function(m) {
      var arr = [];
        indices.forEach(function(i) {
          arr.push(m[i]);
        });
        return arr;
    });
  }
%}

@builtin "whitespace.ne"
@builtin "postprocessors.ne"

# Here in, the parsing rules/functions (as originally written by Alexis Sellier)
#
# The basic structure of the syntax tree generated is as follows:
#
#   Ruleset ->  Declaration -> Value -> Expression -> Entity
#
# Here's some Less code:
#
#    .class {
#      color: #fff;
#      border: 1px solid #000;
#      width: @w + 4px;
#      > .child {...}
#    }
#
# And here's what the parse tree might look like:
#
#     Ruleset (Selector '.class', [
#         Declaration ("color",  Value ([Expression [Color #fff]]))
#         Declaration ("border", Value ([Expression [Dimension 1px][Keyword "solid"][Color #000]]))
#         Declaration ("width",  Value ([Expression [Operation " + " [Variable "@w"][Dimension 4px]]]))
#         Ruleset (Selector [Element '>', '.child'], [...])
#     ])

Stylesheet
 -> _ Root {% $({'Stylesheet': 1}) %}

Root
 -> Primary {% d => [d[0]] %}
  | Root _ Primary {% d => d[0].concat(d[2]) %}

# The `primary` rule is the main part of the parser.
# The rules here can appear at any level of the parse tree.
#
# The `primary` rule is represented by this simplified grammar:
#
#     primary  →  (ruleset | declaration)+
#     ruleset  →  selector+ block
#     block    →  '{' primary '}'
#
# Only at one point is the primary rule not called from the
# block rule: at the root level.

Primary
 -> Ruleset {% id %}
  | MixinDefinition {% id %}
  | MixinCall _semi {% id %}
  | FunctionCall _semi {% $({'Call': 0}) %}
  | VariableDefinition _semi
  | VariableDefinition (_semi _ Primary):? {% $({'Variable': 0}) %}
  | AtRule _semi {% $({'AtRule': 0}) %}

AtRule
 -> "@" Ident _ [^:] Block:?  # need arguments etc

Ruleset
 -> Comment:? SelectorList _ Block {% d => { return { type: 'Ruleset', comment: d[0], selectors: d[1], rules: d[3]} } %}

Block
 -> "{" _ Rule:* _ "}" {% d => d[2] %}

# Unlike the root, rules in blocks can have a declaration
Rule
 -> Declaration (_semi _ Rule):?  {% d => { return d[1] ? [d[0]].concat(d[1][2]) : d[0] } %}
  | Primary
    
SelectorList 
 -> Selector {% d => { return [{ type: 'Selector', elements: d[0]}] } %}
  | SelectorList _ "," _ Selector {% d => d[0].concat([{ type: 'Selector', elements: d[4]}]) %}

MixinDefinition
 -> ClassOrId "(" Args:? ")" _ (Guard _):? Block {% d => { return { type: 'MixinDefinition', name: d[0], params: d[2], condition: d[4], rules: d[6] } } %}

Selector
 -> Element {% d => [{ type: 'Element', combinator: '', value: d[0]}] %}
  | Selector __ Element {% d => d[0].concat([{ type: 'Element', combinator: ' ', value: d[2]} ]) %}
  | Selector _ Combinator _ Element {% d => d[0].concat([{ type: 'Element', combinator: d[2], value: d[4]}]) %}

Element
 -> Class {% id %}
  | Id {% id %}
  | Ident {% id %}
  | Attr {% id %}
  | "&" {% id %}
  | Pseudo {% id %}
  | "*" {% id %}
  
# Elements
Class 
 -> "." Ident {% d => d[0] + d[1] %}

Id
 -> "#" Ident {% d => d[0] + d[1] %}

Combinator  # Current CSS4 combinators on the end
 -> ">" {% id %}
 | "+" {% id %}
 | "~" {% id %}
 | "|" {% id %}
 | ">>" {% id %}
 | "||" {% id %}
 | ">>>" {% id %}     

Attr
 -> "[" Ident ([|~*$^]:? "=" (Quoted | [^\]]:+)):? (_ "i"):? "]"

Pseudo
 -> ":" ":":? Ident ("(" [^)]:* ")"):?

Extend
 -> ":extend(" _ SelectorList (__ ExtendKeys):? ")"

ExtendKeys
 -> "!":? ("all" | "deep" | "ALL" | "DEEP")

ClassOrId 
 -> Class {% id %}
 | Id {% id %}

Declaration
 -> Ident _ ":" _ Value
    {%
      d => { 
        return {
          type: 'Declaration',
          name: d[0],
          value: d[4]
        }
	    }
	  %}

VariableDefinition
 -> Variable _ ":" _ VariableValue
    {% 
      d => {
        return { 
          type: 'Declaration', 
          name: d[0],
          variable: true,
          value: d[4] 
        }
	    }
    %}
 
VariableValue
 -> Value | DetachedRuleset

DetachedRuleset
 -> Block {% d => { return { type: 'DetachedRuleset', ruleset: { type: 'Ruleset', rules: d[0] } }} %}

Value
 -> ExpressionList (_ "!" _ "important"):? {% d => { return { type: 'Value', value: d[0], important: d[1] ? true : false } } %}

ExpressionList
 -> Expression {% id %}
  | ExpressionList _ "," _ Expression {% d => d[0].concat([d[4]]) %}
  
# Expressions either represent mathematical operations,
# or white-space delimited Entities.
#
#     1px solid black
#     @var * 2
Expression
 -> Entity (__ Entity):* {% d => d[0].concat(d[1]) %}

# Entities are tokens which can be found inside an Expression
Entity
 -> Comment {% id %}
  | Literal {% id %}
  | Url {% id %}
  | Keyword {% id %}
  | "/" {% id %}
  | Javascript {% id %}

  Literal
   -> Quoted
    | UnicodeDescriptor
  
  ExpressionParts
   -> Unit
    | FunctionCall
    | Color
    | Variable
    | PropReference
 
  # QUOTED
  # A string, which supports escaping " and '
  #
  #     "milky way" 'he\'s the one!'
  #
  # TODO - parse vars directly
  Quoted
   -> "\"" ([^\"\n\r] | "\\\"" ):* "\""
     | "'" ([^\'\n\r] | "\\'"):* "'"

  Num        -> (Int:? "."):? Int
  Percentage -> Num "%"
  Dimension  -> Num Ident
  Unit       -> Num ("%" | Ident):?

  # KEYWORD
  # A catch-all word, such as:
  #
  #     black border-collapse
  #
  Keyword -> AlphaDash AlphaNumDash:* {% d => d[0][0] + d[1].join('') %}
 
  # FUNCTION CALL
  #
  #     rgb(255, 0, 255)
  #
  FunctionCall
   -> "if(" _ Condition _ "," _ CommaArgValue _ "," _ CommaArgValue _ ")"
    | "if(" _ Condition _ ";" _ SemiArgValue _ ";" _ SemiArgValue _ ")"
    | "boolean(" _ Condition _ ")"
    | (Ident | "%") "(" Args ")"

  Assignment
   -> Keyword "=" Value 

  Url
   -> "url(" _ (Quoted | [^)]:*) _ ")"     # -- need to extract the url

  Prop -> PropReference | PropReferenceCurly
  Var -> Variable | VariableCurly
  Interpolator -> VariableCurly | PropReferenceCurly

  PropReference
   -> "$" LessIdent

  PropReferenceCurly
   -> "${" LessIdent "}"

  Variable
   -> "@" "@":? LessIdent {% d => d.join('') %}

  VariableCurly
   -> "@{" LessIdent "}" {% d => d.join('') %}

  Color
   -> "#" Hex3 Hex3:? {% d => d.join('') %}

  UnicodeDescriptor
   -> "U+" [0-9a-fA-F?]:+ ("-" [0-9a-fA-F?]:+):? {% d => d.join('') %}

  Javascript
   -> "~":? "`" [^`]:* "`"

MixinCall
 -> MixinSelectors ("(" Args:? ")"):? {% d => [{ type: 'MixinCall', elements: d[0] }] %}
 
MixinSelectors
 -> ClassOrId {% d => { return { type: 'Element', name: d[0] } } %}
  | MixinSelectors _ ">":? _ ClassOrId {% d => d[0].concat([{ type: 'Element', name: d[0], combinator: '>' }]) %}

SemiArgValue
 -> Expression
  | DetachedRuleset

CommaArgValue
 -> ExpressionList
  | DetachedRuleset

_semi -> _ ";" {% d => null %}

Args
 -> CommaArgValue (_ "," _ CommaArgValue):*
  | SemiArgValue _ ";" (_ SemiArgValue):? (_ ";" _ SemiArgValue):*

# TEMP
Guard -> "when" _ Condition
Condition -> "6"

# Comments are collected by the main parsing mechanism and then assigned to nodes
# where the current structure allows it.
Comment
 -> _ Comment _
   | "//" [^\n\r]:* 
   | "/*" CommentChars:* "*/"
        
CommentChars
 -> "*" [^/] 
   | [^*]

# Identifiers - move to moo lexer?
LessIdent -> AlphaNumDash:+ {% d => d[0].join('') %}
Ident
 -> NameStart NameChar:* {% d => d[0] + d[1].join('') %}

# Primitives - move to moo lexer?
Op
 -> "*" | "+" | "-" | "/"
Int
 -> [0-9]:+ {% d => d.join('') %}
Hex3
 -> Hex Hex Hex {% d => d.join('') %}
Hex
 -> [a-fA-F0-9]
NameStart
 -> [a-zA-Z_-] | NonAscii | Escape 
NameChar
 -> AlphaNumDash | NonAscii | Escape 

AlphaDash -> [a-zA-Z_-] 
AlphaNumDash -> [A-Za-z0-9_-]

NonAscii
 -> [\u0080-\uD7FF\uE000-\uFFFD]
Escape
 -> Unicode | "\\" [\u0020-\u007E\u0080-\uD7FF\uE000-\uFFFD]
Unicode
 -> "\\" Hex:+

