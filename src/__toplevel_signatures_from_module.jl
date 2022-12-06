# internal
function __methods(obj)
	if obj isa Union
		return Method[]
	end

	r = Base._methods_by_ftype(Tuple{obj, Vararg{Any}}, -1, 
		Base.get_world_counter())::Vector{Any}#JET

	return [x.method  for x in r]
end

function __methods(func::Function)
	#println(sig)
	r = Base._methods_by_ftype(Tuple{typeof(func), Vararg{Any}}, -1, 
		Base.get_world_counter())::Vector{Any}#JET

	return [x.method  for x in r]
end

#=
# internal
function unwrap_unionall_upperbound(ua::UnionAll)
	global X = ua
	return var"#self#"(ua{ua.var.ub})
end

unwrap_unionall_upperbound(x) = x
=#
# internal
function get_kw_actual_method(m::Method)
	if isempty(Base.kwarg_decl(m))
		return m
	end
	
	kwc = which(Core.kwcall, Tuple{Any, m.sig.parameters...})
	cod = Base.uncompressed_ast(kwc)
	gr = cod.code[end-1].args[1]::GlobalRef
	fun = getproperty(m.module, gr.name)
	
	return only(methods(fun))
end


# internal
function expand_with_child_modules!(stored_modules!::Set{Module}, mod::Module)
	if mod ∈ stored_modules!
		return stored_modules!
	end

	push!(stored_modules!, mod)

	for n in names(mod; all= true)
		if isdefined(mod, n) 
			v = getproperty(mod, n)
			if v isa Module  &&  v !== mod  &&  parentmodule(v) === mod  &&  
					v ∉ (Base, Core)

				var"#self#"(stored_modules!, v)
			end
		end
	end

	return stored_modules!
end


# internal
function collect_child_modules(modules_list)
	modset = Set{Module}()
	expand_with_child_modules!.((modset,), modules_list)

	return modset
end


# internal 
function collect_signatures!(sigs!::Vector, target_modules::Set{Module}, 
		something, n::Symbol)
	return sigs!
end

function collect_signatures!(sigs!::Vector, target_modules::Set{Module}, 
		ml::Vector{Method}, n::Symbol)

	for m in ml
		if m.module ∈ target_modules
			if !isempty(Base.kwarg_decl(m))
				local bf = Base.bodyfunction(m)
				push!(sigs!, only(methods(bf)).sig)
			else
				push!(sigs!, m.sig)
			end
		end
	end
	return sigs!
end

function collect_signatures!(sigs!::Vector, target_modules::Set{Module}, 
		func::Function, n::Symbol)
	var"#self#"(sigs!, target_modules, __methods(func), n)
	return sigs!
end

function collect_signatures!(sigs!::Vector, target_modules::Set{Module}, 
		obj::DataType, n::Symbol)
	
	bad_functions = (Function, Any)

	if obj ∈ bad_functions  ||  startswith(String(n), "#")
		return sigs!
	else
		var"#self#"(sigs!, target_modules, __methods(obj), n)
		return sigs!
	end
end

function collect_signatures!(sigs!::Vector, target_modules::Set{Module}, 
		obj::UnionAll, n::Symbol)
	
	if !startswith(String(n), "#")
		local unwobj = Base.unwrap_unionall(obj)
		var"#self#"(sigs!, target_modules, __methods(unwobj), n)
	end

	return sigs!
end


# internal
function gather_method_signatures_from_module!(sigs!::Vector, 
		target_modules::Set{Module},  mod::Module)

	for n in names(mod; all= true)
		if isdefined(mod, n) 
			v = getproperty(mod, n)

			if v isa Module  &&  v !== mod  &&  parentmodule(v) === mod  &&
					v ∉ (Base, Core)

				var"#self#"(sigs!, target_modules, v)
			else
				collect_signatures!(sigs!, target_modules, v, n)
			end
		end
	end

	return sigs!
end


# internal
function gather_methods_from_module(target_modules; 
		search_only_in_target_modules::Bool = false)

	siglis = Vector()
	tarmodwitchiset = collect_child_modules(target_modules)
	
	if search_only_in_target_modules
		gather_method_signatures_from_module!.((siglis,), (tarmodwitchiset,), 
			target_modules)
	else
		gather_method_signatures_from_module!.((siglis,), (tarmodwitchiset,), 
			values(Base.loaded_modules))
	end

	return unique(siglis)
end

function gather_methods_from_module(target_module::Module;  kwargs...)
	return var"#self#"([target_module]; kwargs...)
end