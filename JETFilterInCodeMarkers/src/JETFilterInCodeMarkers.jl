module JETFilterInCodeMarkers
export @JET_ignore,  @JET_onanalyze


# internal
function handle_newline_in_macro_arg(x)
	if Meta.isexpr(x, :call)  &&  x.args[1] === :~  &&  Meta.isexpr(x.args[2],
			:braces)  &&  length(x.args[2].args) == 0
		return x.args[3]
	else
		return x
	end	
end


# public
macro JET_ignore(e)
	e2 = handle_newline_in_macro_arg(e)
	e3 = Expr(:block, LineNumberNode(1, :JETFilter__JET_ignore), e2)
	return esc(e3)
end


# public
macro JET_onanalyze(e)
	check_name(mod) = match(r"^##JETVirtualModule#[0-9]+$", 
		String(nameof(mod))) !== nothing

	premod = mod = __module__
	in_virmod = false

	if check_name(mod)
		in_virmod = true
	else
		while (mod = parentmodule(mod)) != premod
			if check_name(mod)
				in_virmod = true
				break
			end

			premod = mod
		end
	end

	if in_virmod
		return esc(e)
	else
		return :()
	end
end

end # module JETFilterInCodeMarkers
