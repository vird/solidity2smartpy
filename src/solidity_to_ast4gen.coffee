Type = require 'type'
ast = require './ast'

bin_op_map =
  '+'   : 'ADD'
  '-'   : 'SUB'
  '*'   : 'MUL'
  '/'   : 'DIV'
  '%'   : 'MOD'
  
  '&' : 'BIT_AND'
  '|' : 'BIT_OR'
  '^' : 'BIT_XOR'
  
  '&&' : 'BOOL_AND'
  '||' : 'BOOL_OR'
  
  '==' : 'EQ'
  '!=' : 'NE'
  '>'  : 'GT'
  '<'  : 'LT'
  '>=' : 'GTE'
  '<=' : 'LTE'
  
  '='  : 'ASSIGN'
  '+=' : 'ASS_ADD'
  '-=' : 'ASS_SUB'
  '*=' : 'ASS_MUL'
  '/=' : 'ASS_DIV'

is_complex_assign_op =
  'ASS_ADD' : true
  'ASS_SUB' : true
  'ASS_MUL' : true
  'ASS_DIV' : true

un_op_map =
  '-' : 'MINUS'
  '+' : 'PLUS'
  '~' : 'BIT_NOT'

class Context
  current_contract  : null
  constructor:()->

module.exports = (root)->
  walk_type = (ast_tree, ctx)->
    switch ast_tree.nodeType
      when 'ElementaryTypeName'
        new Type ast_tree.typeDescriptions.typeIdentifier
      when 'Mapping'
        ret = new Type "map"
        ret.nest_list.push walk_type ast_tree.keyType, ctx
        ret.nest_list.push walk_type ast_tree.valueType, ctx
        ret
      else
        p ast_tree
        throw new Error("walk_type unknown nodeType '#{ast_tree.nodeType}'")
  
  walk_param = (ast_tree, ctx)->
    switch ast_tree.nodeType
      when 'ParameterList'
        ret = []
        for v in ast_tree.parameters
          ret.append walk_param v, ctx
        ret
      when 'VariableDeclaration'
        if ast_tree.value
          throw new Error("ast_tree.value not implemented")
        ret = []
        t = new Type ast_tree.typeDescriptions.typeIdentifier
        # HACK INJECT
        t._name = ast_tree.name
        ret.push t
        ret
      else
        p ast_tree
        throw new Error("walk_param unknown nodeType '#{ast_tree.nodeType}'")
    
  
  walk_exec = (ast_tree, ctx)->
    switch ast_tree.nodeType
      # ###################################################################################################
      #    expr
      # ###################################################################################################
      when 'Identifier'
        ret = new ast.Var
        ret.name = ast_tree.name
        ret.type = new Type ast_tree.typeDescriptions.typeIdentifier
        ret
      
      when 'Literal'
        ret = new ast.Const
        ret.type  = new Type ast_tree.kind
        ret.val   = ast_tree.value
        ret
      
      when 'Assignment'
        ret = new ast.Bin_op
        ret.op = bin_op_map[ast_tree.operator]
        if !ret.op
          throw new Error("unknown bin_op #{ast_tree.operator}")
        ret.a = walk_exec ast_tree.leftHandSide, ctx
        ret.b = walk_exec ast_tree.rightHandSide, ctx
        ret
      
      when 'BinaryOperation'
        ret = new ast.Bin_op
        ret.op = bin_op_map[ast_tree.operator]
        if !ret.op
          throw new Error("unknown bin_op #{ast_tree.operator}")
        ret.a = walk_exec ast_tree.leftExpression, ctx
        ret.b = walk_exec ast_tree.rightExpression, ctx
        ret
      
      when 'MemberAccess'
        ret = new ast.Field_access
        ret.t = walk_exec ast_tree.expression, ctx
        ret.name = ast_tree.memberName
        ret
      
      when 'IndexAccess'
        ret = new ast.Bin_op
        ret.op = 'INDEX_ACCESS'
        ret.a = walk_exec ast_tree.baseExpression, ctx
        ret.b = walk_exec ast_tree.indexExpression, ctx
        ret
      
      when 'UnaryOperation'
        ret = new ast.Un_op
        ret.op = un_op_map[ast_tree.operator]
        if !ret.op
          throw new Error("unknown un_op #{ast_tree.operator}")
        ret.a = walk_exec ast_tree.subExpression, ctx
        ret
      
      when 'FunctionCall'
        ret = new ast.Fn_call
        ret.fn = new ast.Var
        ret.fn.name = ast_tree.expression.name
        
        for v in ast_tree.arguments
          ret.arg_list.push walk_exec v, ctx
        ret
      
      # ###################################################################################################
      #    stmt
      # ###################################################################################################
      when 'ExpressionStatement'
        walk_exec ast_tree.expression, ctx
      
      when 'VariableDeclarationStatement'
        if ast_tree.declarations.length != 1
          throw new Error("ast_tree.declarations.length != 1")
        decl = ast_tree.declarations[0]
        if decl.value
          throw new Error("decl.value not implemented")
        
        ret = new ast.Var_decl
        ret.name = decl.name
        ret.type = new Type decl.typeDescriptions.typeIdentifier
        if ast_tree.initialValue
          ret.assign_value = walk_exec ast_tree.initialValue, ctx
        ret
      
      when "Block"
        ret = new ast.Scope
        for node in ast_tree.statements
          ret.list.push walk_exec node, ctx
        ret
      
      when "IfStatement"
        ret = new ast.If
        ret.cond = walk_exec ast_tree.condition, ctx
        ret.t    = walk_exec ast_tree.trueBody,  ctx
        if ast_tree.falseBody
          ret.f    = walk_exec ast_tree.falseBody, ctx
        ret
      
      when 'WhileStatement'
        ret = new ast.While
        ret.cond = walk_exec ast_tree.condition, ctx
        ret.scope= walk_exec ast_tree.body, ctx
        ret
      
      when 'ForStatement'
        ret = new ast.Scope
        ret._phantom = true # HACK
        if ast_tree.initializationExpression
          ret.list.push walk_exec ast_tree.initializationExpression, ctx
        ret.list.push inner = new ast.While
        inner.cond = walk_exec ast_tree.condition, ctx
        
        loc = walk_exec ast_tree.body, ctx
        if loc.constructor.name == 'Scope'
          inner.scope = loc
        else
          inner.scope.list.push loc
        
        # т.к. у нас нет continue, то можно
        inner.scope.list.push walk_exec ast_tree.loopExpression, ctx
        ret
      
      # ###################################################################################################
      #    control flow
      # ###################################################################################################
      when 'Return'
        ret = new ast.Ret_multi
        ret.t_list.push walk_exec ast_tree.expression, ctx
        ret
      
      else
        p ast_tree
        throw new Error("walk_exec unknown nodeType '#{ast_tree.nodeType}'")
    
  
  walk = (ast_tree, ctx)->
    switch ast_tree.nodeType
      when "PragmaDirective"
        name = ast_tree.literals[0]
        return if name == 'solidity'
        return if name == 'experimental'
        throw new Error("unknown pragma '#{name}'")
      when "VariableDeclaration"
        ret = new ast.Var_decl
        ret._const = ast_tree.constant
        ret.name = ast_tree.name
        ret.type = walk_type ast_tree.typeName, ctx
        # ret.type = new Type ast_tree.typeDescriptions.typeIdentifier
        if ast_tree.value
          ret.assign_value = walk_exec ast_tree.value, ctx
        # ast_tree.typeName
        # storage : ast_tree.storageLocation
        # state   : ast_tree.stateVariable
        # visibility   : ast_tree.visibility
        ret
        
      when "FunctionDefinition"
        fn = ctx.current_function = new ast.Fn_decl_multiret
        fn.name = ast_tree.name or 'constructor'
        
        fn.type_i =  new Type 'function'
        fn.type_o =  new Type 'function'
        
        fn.type_i.nest_list = walk_param ast_tree.parameters, ctx
        fn.type_o.nest_list = walk_param ast_tree.returnParameters, ctx
        
        for v in fn.type_i.nest_list
          fn.arg_name_list.push v._name
        # ctx.stateMutability
        if ast_tree.modifiers.length
          throw new "ast_tree.modifiers not implemented"
        
        if ast_tree.body
          fn.scope = walk_exec ast_tree.body, ctx
        else
          fn.scope = new ast.Scope
        fn
        
      when "ContractDefinition"
        ctx.current_contract = new ast.Class_decl
        ctx.current_contract.name = ast_tree.name
        for node in ast_tree.nodes
          ctx.current_contract.scope.list.push walk node, ctx
        ctx.current_contract
      else
        p ast_tree
        throw new Error("walk unknown nodeType '#{ast_tree.nodeType}'")
    
  
  # first pass
  ret = new ast.Scope
  ctx = new Context
  for node in root.nodes
    loc = walk node, ctx  
    ret.list.push loc if loc
  
  ret
