Base.@kwdef mutable struct DefaultsType
		target_modules::Vector{Module} = Module[]
		dev_to_target_modules::Bool = true
		filter__no_unique_method_for_sig::Bool = true
		filter__method_errors_on_generic_sig::Bool = true
		filter__method_errors_on_generic_sig__same_errors::Bool = false
		ignorelist = []
		ignorelist_file = nothing
		gen_temp_proj::Bool = true
		jetconfigs::NamedTuple = (;)
		search_only_in_target_modules::Bool = false
end

defaults = DefaultsType()
