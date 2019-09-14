config = require './config'
require 'fy/codegen'
module = @

type2default_value = (type)->
  switch type.main
    when 't_bool'
      'False'
    when 't_uint256'
      '0'
    when 't_int256'
      '0'
    when 't_address'
      'sp.address()'
    when 't_string_memory_ptr'
      '""'
    when 'map'
      'sp.BigMap()'
    else
      throw new Error("unknown solidity type '#{type}'")

@bin_op_name_map =
  ADD : '+'
  SUB : '-'
  MUL : '*'
  DIV : '/'
  MOD : '%'
  
  
  EQ : '=='
  NE : '!='
  GT : '>'
  LT : '<'
  GTE: '>='
  LTE: '<='
  
  BOOL_AND: 'and'
  BOOL_OR : 'or'
  
  BIT_AND : '&'
  BIT_OR  : '|'
  BIT_XOR : '^'

@bin_op_name_cb_map =
  ASSIGN  : (a, b)-> "#{a} = #{b}"
  ASS_ADD : (a, b)-> "#{a} += #{b}"
  ASS_SUB : (a, b)-> "#{a} -= #{b}"
  ASS_MUL : (a, b)-> "#{a} *= #{b}"
  ASS_DIV : (a, b)-> "#{a} /= #{b}"
  
  INDEX_ACCESS : (a, b)->"#{a}[#{b}]"

@un_op_name_cb_map =
  MINUS   : (a)->"-(#{a})"
  PLUS    : (a)->"+(#{a})"
  BIT_NOT : (a)->"~(#{a})"

class @Gen_context
  parent_ctx  : null
  fn_hash     : {}
  var_hash    : {}
  in_class    : false
  in_fn       : false
  tmp_idx     : 0
  trim_expr   : ''
  
  constructor:()->
    @fn_hash    = {}
    @var_hash   = {}
  
  mk_nest : ()->
    t = new module.Gen_context
    t.parent_ctx = @
    t.var_hash = clone @var_hash
    t.fn_hash  = @fn_hash
    t
    
@gen = (ast, opt = {})->
  ctx = new module.Gen_context
  ret = module._gen ast, opt, ctx
  """
  import smartpy as sp
  #{ret}
  """

@_gen = gen = (ast, opt, ctx)->
  switch ast.constructor.name
    # ###################################################################################################
    #    expr
    # ###################################################################################################
    when "Var"
      {name} = ast
      if ctx.parent_ctx.var_hash[name]
        "self.data.#{name}"
      else if decl = ctx.var_hash[name]
        # TODO arg get case
        if decl._is_arg
          "#{config.params}.#{name}"
        else
          name
      else if ctx.fn_hash[name]
        "self.#{name}"
      else if name == 'msg'
        "msg"
      else
        p "ctx.parent_ctx.var_hash", ctx.parent_ctx.var_hash
        p "ctx.var_hash", ctx.var_hash
        throw new Error "unknown var #{name}"
    
    when "Const"
      switch ast.type.main
        when 'string'
          JSON.stringify ast.val
        else
          ast.val
    
    when 'Bin_op'
      _a = gen ast.a, opt, ctx
      _b = gen ast.b, opt, ctx
      if op = module.bin_op_name_map[ast.op]
        "(#{_a} #{op} #{_b})"
      else if cb = module.bin_op_name_cb_map[ast.op]
        cb(_a, _b, ctx, ast)
      else
        throw new Error "Unknown/unimplemented bin_op #{ast.op}"
    
    when "Un_op"
      if cb = module.un_op_name_cb_map[ast.op]
        cb gen(ast.a, opt, ctx), ctx
      else
        throw new Error "Unknown/unimplemented un_op #{ast.op}"
    
    when "Field_access"
      t = gen ast.t, opt, ctx
      ret = "#{t}.#{ast.name}"
      if ret == 'msg.sender'
        ret = 'sp.sender'
      ret
    
    when "Fn_call"
      fn = gen ast.fn, opt, ctx
      arg_list = []
      for v in ast.arg_list
        arg_list.push gen v, opt, ctx
      
      # HACK  
      if fn == "require"
        arg_list[0]
        # failtext = arg_list[1] or ""
        return """
          sp.verify(#{arg_list[0]})
          """
      
      "#{fn}(#{arg_list.join ', '})"
      
    
    # ###################################################################################################
    #    stmt
    # ###################################################################################################
    when "Scope"
      jl = []
      for v in ast.list
        jl.push gen v, opt, ctx
      jl.push "pass" if jl.length == 0
      join_list jl, ''
    
    when "Var_decl"
      ctx.var_hash[ast.name] = ast
      if ctx.in_class
        return ""
      if ctx.in_fn
        if ast.assign_value
          val = gen ast.assign_value, opt, ctx
        else
          val = type2default_value ast.type
        return "#{ast.name} = #{val}"
        
        return ""
      throw new Error "unknown Var_decl case"
    
    when "Ret_multi"
      if ast.t_list.length > 1
        throw new Error "not implemented ast.t_list.length > 1"
      
      jl = []
      for v in ast.t_list
        jl.push gen v, opt, ctx
      """
      return #{jl.join ', '}
      """
    
    when "If"
      cond = gen ast.cond, opt, ctx
      t    = gen ast.t, opt, ctx
      f    = gen ast.f, opt, ctx
      """
      if #{cond}:
        #{make_tab t, '  '}
      else:
        #{make_tab f, '  '}
      """
    
    when "While"
      cond = gen ast.cond, opt, ctx
      scope= gen ast.scope, opt, ctx
      """
      while #{cond}:
        #{make_tab scope, '  '}
      """
    
    when "Class_decl"
      ctx = ctx.mk_nest()
      ctx.in_class = true
      jl = []
      for v in ast.scope.list
        switch v.constructor.name
          when 'Var_decl'
            ctx.var_hash[v.name] = v
          when 'Fn_decl_multiret'
            ctx.fn_hash[v.name] = v
          else
            throw new Error("unimplemented v.constructor.name=#{v.constructor.name}")
      body = gen ast.scope, opt, ctx
      jl = []
      for k,v of ctx.var_hash
        jl.push "#{k} = #{type2default_value v.type}"
      
      """
      class #{ast.name}(sp.Contract):
        def __init__(self):
          self.init(#{jl.join ',\n      '})
        
        #{make_tab body, '  '}
      """
    
    when "Fn_decl_multiret"
      ctx = ctx.mk_nest()
      ctx.in_fn = true
      for v,idx in ast.arg_name_list
        ctx.var_hash[v] = {
          _is_arg : true
          type : ast.type_i.nest_list[idx]
        }
      body = gen ast.scope, opt, ctx
      """
      def #{ast.name}(self, #{config.params}):
        #{make_tab body, '  '}
      """
    
    else
      if opt.next_gen?
        return opt.next_gen ast, opt, ctx
      ### !pragma coverage-skip-block ###
      perr ast
      throw new Error "unknown ast.constructor.name=#{ast.constructor.name}"
