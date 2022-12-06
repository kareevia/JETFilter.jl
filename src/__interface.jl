export report_package,  report,  show_signature_strings_for_ignorelist,
	report_file,  report_text,  report_module


# internal
#__default_modules_to_exclude_from_filtering = Set()#[Base, Core])


# public
Base.@kwdef struct FilteredJETReportWrapper
	jetconfigs
	actual2virtual = []
	x
end


# internal
function gen_actual2virtual_replacer(a2v)
	replis = let
		x = map(a2v) do (actualmod, virtualmod)::JET.Actual2Virtual
			actual  = string(actualmod)
			virtual = string(virtualmod) * "."
			#=return actualmod === Main ?
						["Main." => "", virtual => actual] :
						[virtual => actual]=#
			return virtual => ""	
		end

		#reduce(vcat, x)
		x
	end

	return function replacer(s)
		return replace(s, replis...)
	end	
end


# public
function show_signature_strings_for_ignorelist(io,res::FilteredJETReportWrapper)
	a2vrepfun = gen_actual2virtual_replacer(res.actual2virtual)

	for (ri, r) in enumerate(res.x)
		println(io, "Report $ri:")
		for (fi, f) in enumerate(r.vst)
			m = f.linfo.def
			sigstr = a2vrepfun("$(m.module).$m")
			sigstr = replace(sigstr,  "*" => "\\*",  "?" => "\\?",  "..." => "\\...")
			println(io, "$fi) $sigstr")
		end	
		println(io)
	end

	return
end

function show_signature_strings_for_ignorelist(res::FilteredJETReportWrapper)
	return var"#self#"(stdout, res)
end


# public
function Base.show(io::IO, res::FilteredJETReportWrapper) 
	JET.print_reports(io, res.x, gen_actual2virtual_replacer(res.actual2virtual);
		res.jetconfigs...)
	return
end


# internal
function apply_glob_for_sig_pattern(s)
	s = replace(s, 
		"\\*" => "*",  "*" => "\\E[^.(),{} \"]*\\Q", 
		"\\?" => "?",  "?" => "\\E[^.(),{} \"]\\Q",
		"\\..." => "...",  "..." => "\\E.*\\Q")

	return Regex("\\Q$s\\E")
end


# internal
function read_ignorelist(source)
	linlis = strip.(readlines(source))
	l = map(linlis) do l
		return l != ""  &&  !startswith(l, "#")
	end

	return linlis[l]
end


# internal
function process_signatures_list(siglis; jetconfigs = (;), 
		target_modules = defaults.target_modules, 
		dev_to_target_modules::Bool = defaults.dev_to_target_modules, 
		filter__no_unique_method_for_sig::Bool = 
			defaults.filter__no_unique_method_for_sig, 
		filter__method_errors_on_generic_sig::Bool = 
			defaults.filter__method_errors_on_generic_sig, 
		filter__method_errors_on_generic_sig__same_errors::Bool = 
			defaults.filter__method_errors_on_generic_sig__same_errors,
		a2vreplacer = identity, 
		ignorelist = defaults.ignorelist, 
		ignorelist_file = defaults.ignorelist_file)

	global __default_modules_to_exclude_from_filtering

	ignlisfrofil = ignorelist_file !== nothing ? 
		read_ignorelist(ignorelist_file) : []

	ignlisregexp = apply_glob_for_sig_pattern.(Iterators.flatten((ignorelist,
		ignlisfrofil)))

	replis = let 
		x = JET.get_reports.(__report_call_method.(which.(siglis); max_methods= 1,	
			jetconfigs...))
			
		reduce(vcat, x)
	end

	tarmod = let 
		modset = Set{Module}()
		for r in replis
			push!(modset, r.vst[1].linfo.def.module)
		end

		if dev_to_target_modules
			for (pi, mod) in Base.loaded_modules
				local x = get(Pkg.dependencies(), pi.uuid, nothing)
				if x !== nothing  &&  x.is_tracking_path
					push!(modset, mod)
				end
			end
		end

		union!(modset, target_modules)
	end

	filreplis = let
		local l = filter_report_incode_flags(replis)

		if !isempty(ignlisregexp)
			l[l] = filter_on_methodsignature_list(view(replis, l), ignlisregexp, 
				a2vreplacer)
		end

		if filter__no_unique_method_for_sig
			l[l] = filter_report_non_single_methods(view(replis, l))
		end

		if filter__method_errors_on_generic_sig
			local lv = view(replis, l)
			l[l] = filter_report_based_on_error_of_methodsig(lv, tarmod,Set{Module}();
				filterout_only_on_same_error= 
					filter__method_errors_on_generic_sig__same_errors)
		end
		
		replis[l]
	end

	return FilteredJETReportWrapper(; x= filreplis, jetconfigs)
end



# internal
function generate_temp_project_and_try_to_make_compatible(func, pac)
	curpropat = Base.active_project()
	try
		redirect_stderr(devnull) do 
			curpaclis = Pkg.dependencies()
			local tarpropat = let 
				s = Base.find_package(string(pac))
				a = splitpath(s::String)
				b = a[begin:end-1]
				b[end] = "Project.toml"
				joinpath(b)
			end

			Base.set_active_project(tarpropat)
			tarpacuidlis = Set([x[1]  for x in Pkg.dependencies()])
			tarpacdic = Dict([x  for x in Pkg.dependencies()  if x[2].is_direct_dep])
			
			Pkg.activate(; temp= true)

			pacto_ = (;
				add = sizehint!(Pkg.PackageSpec[], length(curpaclis)),
				dev = sizehint!(Pkg.PackageSpec[], length(curpaclis)),
				del = sizehint!(Pkg.PackageSpec[], length(curpaclis))
			)

			for (uuid, pacinf) in curpaclis
				if uuid ∉ tarpacuidlis
					continue
				end

				if pacinf.is_tracking_path
					push!(pacto_.dev, Pkg.PackageSpec(; path= pacinf.source))
				else
					push!(pacto_.add, Pkg.PackageSpec(; pacinf.name, uuid, pacinf.version))
				end
			end
			
			if !isempty(pacto_.add)
				Pkg.add(pacto_.add; preserve= Pkg.PRESERVE_ALL)
			end
			if !isempty(pacto_.dev)
				Pkg.develop(pacto_.dev; preserve= Pkg.PRESERVE_ALL)
			end

			empty!(pacto_.add)
			empty!(pacto_.dev)

			for (uuid, pacinf) in tarpacdic
				if haskey(curpaclis, uuid)
					continue
				end

				local ps = if pacinf.is_tracking_path
					push!(pacto_.dev, Pkg.PackageSpec(; path= pacinf.source))
				else
					push!(pacto_.add, Pkg.PackageSpec(; pacinf.name, uuid, pacinf.version))
				end
			end

			if !isempty(pacto_.add)
				Pkg.add(pacto_.add; preserve= Pkg.PRESERVE_ALL)
			end
			if !isempty(pacto_.dev)
				Pkg.develop(pacto_.dev; preserve= Pkg.PRESERVE_ALL)
			end

			for (uuid, pacinf) in curpaclis
				if uuid ∈ tarpacuidlis && !haskey(tarpacdic, uuid)
					push!(pacto_.del, Pkg.PackageSpec(; uuid))
				end
			end

			if !isempty(pacto_.del)
				Pkg.rm(pacto_.del)
			end

			return func()
		end
	finally
		Base.set_active_project(curpropat)
	end
end


# public
function report_package(packages::Union{AbstractString, Module}...; 
		jetconfigs = (;),  gen_temp_proj = defaults.gen_temp_proj,  kwargs...)

	act2__virset = Set{JET.Actual2Virtual}()

	siglis = let
		if !isempty(packages) 
			x = map(packages) do pac
				res = if gen_temp_proj
					generate_temp_project_and_try_to_make_compatible(pac) do
						JET.report_package(pac; jetconfigs..., 
							analyze_from_definitions= true)
					end
				else
					JET.report_package(pac; jetconfigs..., 
						analyze_from_definitions= true)
				end

				if !isempty(res.res.toplevel_error_reports)
					display(res)
				end

				push!(act2__virset, res.res.actual2virtual)
				return __extract_list_of_signatures(res)
			end 
			reduce(vcat, x)
		else
			res = JET.report_package(; jetconfigs..., 
				analyze_from_definitions= true)
			push!(act2__virset, res.res.actual2virtual)
			__extract_list_of_signatures(res)
		end
	end

	a2v = collect(act2__virset)

	fr = process_signatures_list(siglis; jetconfigs, kwargs..., 
		a2vreplacer= gen_actual2virtual_replacer(a2v))
	
	@reset fr.actual2virtual = a2v

	return fr
end


# public
function report_file(files::AbstractString...;  jetconfigs = (;),  kwargs...)

	act2__virset = Set{JET.Actual2Virtual}()

	siglis = let
		x = map(files) do fil
			res = JET.report_file(fil; jetconfigs..., 
				analyze_from_definitions= true)

			if !isempty(res.res.toplevel_error_reports)
				display(res)
			end

			push!(act2__virset, res.res.actual2virtual)
			return __extract_list_of_signatures(res)
		end 
		reduce(vcat, x)
	end

	a2v = collect(act2__virset)

	fr = process_signatures_list(siglis; jetconfigs, kwargs..., 
		a2vreplacer= gen_actual2virtual_replacer(a2v))
	
	@reset fr.actual2virtual = a2v

	return fr
end


# public
function report_text(texts::AbstractString...;  jetconfigs = (;),  kwargs...)

	act2__virset = Set{JET.Actual2Virtual}()

	siglis = let
		x = map(texts) do tex
			res = JET.report_text(tex; jetconfigs..., 
				analyze_from_definitions= true)

			if !isempty(res.res.toplevel_error_reports)
				display(res)
			end

			push!(act2__virset, res.res.actual2virtual)
			return __extract_list_of_signatures(res)
		end 
		reduce(vcat, x)
	end

	a2v = collect(act2__virset)

	fr = process_signatures_list(siglis; jetconfigs, kwargs..., 
		a2vreplacer= gen_actual2virtual_replacer(a2v))
	
	@reset fr.actual2virtual = a2v

	return fr
end


# public
function report_module(modules::Module...;  jetconfigs = (;),
		search_only_in_target_modules::Bool = defaults.search_only_in_target_modules,
		kwargs...)

	siglis = gather_methods_from_module(modules; search_only_in_target_modules)
	return process_signatures_list(siglis; jetconfigs, kwargs...)
end


# public
function report(func; jetconfigs = (;), kwargs...)
	siglis = map(methods(func)) do m
		if !isempty(Base.kwarg_decl(m))
			bf = Base.bodyfunction(m)
			if bf === nothing
				return m.sig
			else
				return methods(bf)[1].sig
			end
		else
			return m.sig
		end
	end

	return process_signatures_list(siglis; jetconfigs, kwargs...)
end


# public
function report(sig::Union{DataType, UnionAll}; jetconfigs = (;), kwargs...)
	return process_signatures_list([sig]; jetconfigs, kwargs...)
end


# public
function report(m::Method; jetconfigs = (;), kwargs...)
	sig = if !isempty(Base.kwarg_decl(m))
		bf = Base.bodyfunction(m)
		if bf === nothing
			m.sig
		else
			methods(bf)[1].sig
		end
	else
		m.sig
	end


	return process_signatures_list([sig]; jetconfigs, kwargs...)
end


