# internal
function __report_call_method(m::Method;
		analyzer::Type{Analyzer} = JET.JETAnalyzer,
		source::Union{Nothing,AbstractString} = nothing,
		jetconfigs...) where {Analyzer<:JET.AbstractAnalyzer}
	
	analyzer = Analyzer(; jetconfigs...)
	JET.may_init_cache!(analyzer)
	analyzer, result = JET.analyze_method!(analyzer, m)

	if isnothing(source)
		source = string(nameof(JET.var"@report_call"), " ", 
			sprint(Base.show_tuple_as_call, Symbol(""), m.sig))
	end

	return JET.JETCallResult(result, analyzer, source; jetconfigs...)
end