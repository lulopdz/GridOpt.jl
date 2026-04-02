# src/concrete/utils.jl

# ==============================================================================
# Configuration Structure
struct TEPConfig
    include_network::Bool      # true = multi-node network, false = single node
    use_integer::Bool          # true = binary investments, false = continuous relaxation
    enforce_netzero::Bool      # true = enforce net-zero/emission-cap constraints
    include_carbon_tax::Bool   # true = include carbon tax, false = exclude
    cf_resolution::Symbol      # :system, :regional, or :nodal
    per_unit::Bool             # true = per unit system, false = MW system
    bigM::Float64              # Big-M for candidate line constraints
    solver                     # Optimizer (e.g., GLPK.Optimizer)
end


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
        :nodes => read_df("topology/nodes"),
        :load => read_df("topology/load"),
        :line => read_df("topology/line"),
        # Assets
        :gen => read_df("assets/gen"),
        :gcand => read_df("assets/gcand"),
        :sto => read_df("assets/sto"),
        :stocand => read_df("assets/stocand"),
        :tcand => read_df("assets/tcand"),
        # Economic and scenario data
        :econ => read_df("tech_econ/economic"),
        :gtech => read_df("tech_econ/gtech"),
        :ttech => read_df("tech_econ/ttech"),
        # Technology data (if needed)
        :sce => read_df("timeseries/scenario"),
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