#=
# internal
function __method_by_ftype(sig, return_several::Bool = false)
	r = Base._methods_by_ftype(sig,	-1, Base.get_world_counter())::Vector{Any}#JET
	if return_several
		return [x.method  for x in r]
	else
		@show(sig, r)
		return only(r).method
	end
end
=#


#internal
function __has_kwargs(m::Method)
	return !isempty(Base.kwarg_decl(m))
	#=
	v = Base._methods_by_ftype(Tuple{typeof(Core.kwcall), Any, 
		m.sig.parameters...},	-1, Base.get_world_counter())
		
	return !isempty(v)=#
end


# internal
function __extract_detailization_from_sig(sig, closure_unionall)
	c = Base.code_typed_by_type(sig)[1][1]::Core.CodeInfo
	types = c.ssavaluetypes[c.ssavaluetypes .<: closure_unionall]
	return [x  for x in types  if x isa DataType]
end


# internal
function __detailize_closures!(tls)
	to_be_app = Type[]

	for (i,t) in enumerate(tls)
		if t <: Tuple  &&  (local ms = t.parameters[1]) isa UnionAll
			detlis = let
				x = __extract_detailization_from_sig.(tls, (ms,))
				unique!(reduce(vcat, x))
			end
			
			if !isempty(detlis)
				tls[i] = Tuple{detlis[1], tls[i].parameters[2:end]...}
			end

			for x in detlis[2:end]
				push!(to_be_app, Tuple{x, tls[i].parameters[2:end]...})
			end
		end
	end

	append!(tls, to_be_app)

	return tls
end


# internal
function __extract_list_of_signatures(jr)
	tls = jr.res.toplevel_signatures
		
	sv = map(tls) do s
		local m = which(s) # __method_by_ftype(s)

		if __has_kwargs(m)
			return false
		end

		if endswith(String(m.name), "##kw")
			return false
		end
		
		return true
	end

	tls = __detailize_closures!(tls[sv])

	return tls
end

