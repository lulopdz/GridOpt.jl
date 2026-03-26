# src/concrete/utils.jl
# ==============================================================================
# Data Loading
function load_tgep_data(data_path::String, project::String)
    dfpath(name) = joinpath(data_path, project, string(name, ".csv"))
    read_df(name) = begin
        fp = dfpath(name)
        isfile(fp) || error("Missing data file: $fp")
        CSV.read(fp, DataFrame)
    end

    proj_path = joinpath(data_path, project)
    isdir(proj_path) || error("Project data folder not found: $proj_path")
    
    return Dict{Symbol, Any}(
        # Existing infrastructure
        :nodes => read_df("nodes"),
        :gen => read_df("gen"),
        :load => read_df("load"),
        :line => read_df("line"),
        # Candidate infrastructure
        :gcand => read_df("gcand"),
        :tcand => read_df("tcand"),
        # Economic and scenario data
        :econ => read_df("economic"),
        :sce => read_df("scenario"),
        # Technology data (if needed)
        :gtech => read_df("gtech"),
        :ttech => read_df("ttech"),
        # Storage infrastructure
        :sto => read_df("sto"),
        :stocand => read_df("stocand"),
    )
end

# ==============================================================================
# Parameter Processing
norm_key(x) = lowercase(strip(string(x)))

function parse_param_value(x, default=0.0)
    if ismissing(x)
        return default
    end
    sval = norm_key(x)
    if sval in ("", "n/a", "na", "null", "missing")
        return default
    end
    parsed = tryparse(Float64, string(x))
    return isnothing(parsed) ? default : parsed
end

function get_tech_param(gtech::DataFrame, gen_type, col::Symbol; default=0.0)
    if isempty(gtech) || !(col in propertynames(gtech)) || !(:gen_type in propertynames(gtech)) || ismissing(gen_type)
        return default
    end
    # Find the row for this tech type
    target = norm_key(gen_type)
    idx = findfirst(==(target), norm_key.(gtech.gen_type))
    isnothing(idx) && return default
    
    val = gtech[idx, col]
    return parse_param_value(val, default)
end

function get_line_tech_param(ttech::DataFrame, line_type, col::Symbol; default=0.0)
    if isempty(ttech) || !(col in propertynames(ttech)) || !(:line_type in propertynames(ttech)) || ismissing(line_type)
        return default
    end
    target = norm_key(line_type)
    idx = findfirst(==(target), norm_key.(ttech.line_type))
    isnothing(idx) && return default

    val = ttech[idx, col]
    return parse_param_value(val, default)
end

function get_cf(gen_type, hour, wind_cf_dict, solar_cf_dict)
    ismissing(gen_type) && return 1.0
    gtype = norm_key(gen_type)
    if occursin("wind", gtype)
        return get(wind_cf_dict, hour, 1.0)
    elseif occursin("solar", gtype)
        return get(solar_cf_dict, hour, 1.0)
    else
        return 1.0
    end
end