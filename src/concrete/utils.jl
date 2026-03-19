# src/concrete/utils.jl
# ==============================================================================
# Data Loading
function load_tgep_data(data_path::String, project::String)
    dfpath(name) = joinpath(data_path, project, string(name, ".csv"))
    
    return Dict{Symbol, Any}(
        # Existing infrastructure
        :nodes => CSV.read(dfpath("nodes"), DataFrame),
        :gen => CSV.read(dfpath("gen"), DataFrame),
        :load => CSV.read(dfpath("load"), DataFrame),
        :line => CSV.read(dfpath("line"), DataFrame),
        # Candidate infrastructure
        :gcand => CSV.read(dfpath("gcand"), DataFrame),
        :tcand => CSV.read(dfpath("tcand"), DataFrame),
        # Economic and scenario data
        :econ => CSV.read(dfpath("economic"), DataFrame),
        :sce => CSV.read(dfpath("scenario"), DataFrame),
        # Technology data (if needed)
        :gtech => CSV.read(dfpath("gtech"), DataFrame),
        :ttech => CSV.read(dfpath("ttech"), DataFrame),
    )
end

# ==============================================================================
# Parameter Processing
function get_tech_param(gtech::DataFrame, gen_type, col::Symbol; default=0.0)
    if isempty(gtech) || !(col in propertynames(gtech)) || ismissing(gen_type)
        return default
    end
    # Find the row for this tech type
    target = lowercase(strip(String(gen_type)))
    idx = findfirst(==(target), lowercase.(strip.(string.(gtech.gen_type))))
    isnothing(idx) && return default
    
    val = gtech[idx, col]
    if ismissing(val)
        return default
    end
    sval = strip(lowercase(string(val)))
    if sval in ("", "n/a", "na", "null", "missing")
        return default
    end
    parsed = tryparse(Float64, string(val))
    return isnothing(parsed) ? default : parsed
end

function get_line_tech_param(ttech::DataFrame, line_type, col::Symbol; default=0.0)
    if isempty(ttech) || !(col in propertynames(ttech)) || !(:line_type in propertynames(ttech)) || ismissing(line_type)
        return default
    end
    target = lowercase(strip(String(line_type)))
    idx = findfirst(==(target), lowercase.(strip.(string.(ttech.line_type))))
    isnothing(idx) && return default

    val = ttech[idx, col]
    if ismissing(val)
        return default
    end
    sval = strip(lowercase(string(val)))
    if sval in ("", "n/a", "na", "null", "missing")
        return default
    end
    parsed = tryparse(Float64, string(val))
    return isnothing(parsed) ? default : parsed
end

function get_cf(gen_type, hour, wind_cf_dict, solar_cf_dict)
    ismissing(gen_type) && return 1.0
    gtype = lowercase(String(gen_type))
    if occursin("wind", gtype)
        return get(wind_cf_dict, hour, 1.0)
    elseif occursin("solar", gtype)
        return get(solar_cf_dict, hour, 1.0)
    else
        return 1.0
    end
end