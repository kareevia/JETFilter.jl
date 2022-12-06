# internal
function check_if_belongs_to_modules(mod::Module, modset::AbstractSet)
	if mod ∈ modset
		return true
	end

	premod = mod
	if mod ∈ modset
		return true
	end

	while mod ∉ (Base, Core)  &&  (mod = parentmodule(mod)) !== premod
		if mod ∈ modset
			return true
		end

		premod = mod
	end

	return false
end


# internal
function method_to_string(m::Method, a2vreplacer)
	return a2vreplacer("$(m.module).$m")
end


# internal
function filter_on_methodsignature_list(reports, ignorelist, a2vreplacer)
	return map(reports) do rep
		for f in rep.vst
			local m = f.linfo.def
			local frasig = method_to_string(m, a2vreplacer)
			for ignsig in ignorelist
				if startswith(frasig, ignsig)
					return false
				end
			end
		end

		return true
	end
end


# internal
function filter_report_incode_flags(reports)
	return map(reports) do rep
		for f in rep.vst
			if f.file::Symbol == :JETFilter__JET_ignore
				return false
			end
		end

		return true
	end
end


# internal 
function extract_call_sig(vf::JET.VirtualFrame)
	scocou = 0
	begin
		local n = length(vf.sig._sig)
		sigele = sizehint!([], n)
		sigelescolev = sizehint!([], n)
	end

	posnonfinele = false
	for x in vf.sig._sig
		if x isa JET.AnnotationMaker
		elseif x isa Union{Union, UnionAll, Type, Core.TypeofBottom}
			push!(sigele, x)
			push!(sigelescolev, scocou)
			posnonfinele = true
		elseif x isa JET.Repr
			push!(sigele, typeof(x.val))
			push!(sigelescolev, scocou)
			posnonfinele = true
		elseif x isa GlobalRef
			push!(sigele, typeof(getproperty(x.mod, x.name)))
			push!(sigelescolev, scocou)
			posnonfinele = true
		elseif !(x isa Union{Symbol, String, Char,})
			push!(sigele, typeof(x))
			push!(sigelescolev, scocou)
			posnonfinele = true				
		elseif x in ('(', '[', '{')
			if posnonfinele
				posnonfinele = false
				pop!(sigele)
				pop!(sigelescolev)
			end

			scocou += 1
		elseif x in (')', ']', '}')
			posnonfinele = false
			scocou -= 1
		elseif x == ", "
			posnonfinele = false
		elseif x == "..."
			if posnonfinele
				posnonfinele = false
				local e = pop!(sigele)
				local ei = pop!(sigelescolev)
				if !(e isa Union{Union, Core.TypeofBottom})  &&  e <: Tuple
					for x in e.parameters
						push!(sigele, x)
						push!(sigelescolev, ei)
					end
				end
			end
		elseif x == '.'
			if posnonfinele
				posnonfinele = false
				pop!(sigele)
				pop!(sigelescolev)
			end
		end
	end

	# @show(sigele, sigelescolev)
	tarlev = sigelescolev[end]+1 # minimum(sigelescolev)
	l = fill(false, length(sigelescolev))
	for i in length(sigelescolev)-1:-1:1
		if sigelescolev[i] == tarlev
			l[i] = true
		elseif sigelescolev[i] < tarlev
			break
		end
	end
	
	return sigele[l]
end


# internal
function check_if_have_unique_method(tt)
	match, _ = Core.Compiler._findsup(tt, nothing, Base.get_world_counter())
	return match !== nothing
end


# internal
function filter_report_non_single_methods(reports)
	return map(reports) do rep
		for (i,f) in enumerate(rep.vst[begin:end-1])
			local sig = extract_call_sig(rep.vst[i])
			local metinsspetyp = Base.unwrap_unionall(
				rep.vst[i+1].linfo.specTypes).parameters

			if length(sig) != length(metinsspetyp) - 1
				continue
			end

			local methea = metinsspetyp[1]
			if !check_if_have_unique_method(Tuple{methea, sig...})
				return false
			end
		end

		return true
	end
end


# internal 
function report_minisig(report)
	reptyp = (typeof(report), report.sig)
	vstsig = [x.linfo  for x in report.vst]
	return (reptyp, vstsig)
end

# internal
function is_report_ends_as(report, other_repminisig)
	rep1__sig = report_minisig(report)
	return length(rep1__sig[2]) >= length(other_repminisig[2])  && 
		rep1__sig[1] == other_repminisig[1]  &&
		rep1__sig[2][end - length(other_repminisig[2]) + 1:end] == 
			other_repminisig[2]
end


# TODO filterout only if the same error

# internal
# check if any of frames chain is erroneous even with method-sig -- if such
# method is not from excmod module, then discard the report (return false)
function filter_report_based_on_error_of_methodsig(reports, 
		tarmod::AbstractSet{Module}, excmod::AbstractSet{Module};
		filterout_only_on_same_error= true)

	excmod = union(excmod, tarmod)
	# report_call cache
	repcalcac = Dict{Any, Any}()
	
	return map(reports) do rep
		lastarmod = findlast(rep.vst) do f::JET.VirtualFrame
			check_if_belongs_to_modules(f.linfo.def.module, tarmod)
		end

		for (i,f) in enumerate(rep.vst[lastarmod+1:end])
			local m::Method = f.linfo.def
			if check_if_belongs_to_modules(m.module, excmod)
				continue
			end

			if m.sig == f.linfo.specTypes
				return false
			end
			
			local repsiglis = get!(repcalcac, m.sig) do
				jr = __report_call_method(m)
				return report_minisig.(JET.get_reports(jr))
			end
			
			if filterout_only_on_same_error
				for x in repsiglis
					if is_report_ends_as(rep, x)
						return false
					end
				end
			elseif !isempty(repsiglis)
				return false
			end
		end

		return true
	end
end

