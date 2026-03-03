# src/concrete/params.jl
function process_tgep_params(data, config::TEPConfig)
    gen, load, line = data[:gen], data[:load], data[:line]
    gcand, tcand = data[:gcand], data[:tcand]
    tech = data[:tech]
    econ, sce = data[:econ], data[:sce]

    # Per unit conversion for reactances and cost scaling
    if config.per_unit
        Sb = 100.0  # Base power in MVA
        PriceFactor = 1.0e3  # Cost conversion from $/MWh to $/pu
        xe = Dict(line.id .=> line.reactance ./ (line.voltage .^2 / Sb))
        xl = Dict(tcand.id .=> tcand.reactance ./ (tcand.voltage .^2 / Sb))
    else
        Sb = 1.0    # No per unit conversion
        PriceFactor = 1.0    # No cost conversion
        xe = Dict(line.id .=> line.reactance)
        xl = Dict(tcand.id .=> tcand.reactance)
    end

    # Capacity factors based on generation type and scenario data
    type_cf(gen_type::AbstractString, o, wind_cf::Dict, solar_cf::Dict) =
        occursin("wind", gen_type) ? wind_cf[o] :
        occursin("solar", gen_type) ? solar_cf[o] : 1.0

    wind_cf = hasproperty(sce, :wind_cf) ? Dict(sce.hour .=> Float64.(sce.wind_cf)) : Dict(sce.hour .=> ones(length(sce.hour)))
    solar_cf = hasproperty(sce, :solar_cf) ? Dict(sce.hour .=> Float64.(sce.solar_cf)) : Dict(sce.hour .=> ones(length(sce.hour)))
    pgtype = Dict(gen.id .=> gen.gen_type)
    pktype = Dict(gcand.id .=> gcand.gen_type)

    # Load VoLL: use load-specific cost if available, 
    # otherwise default to 10,000 $/MWh (or $/pu) scaled by PriceFactor
    default_voll = 10_000.0
    VoLL = hasproperty(load, :cost_LS) ?
        Dict(load.id .=> load.cost_LS ./ PriceFactor) :
        Dict(load.id .=> fill(default_voll / PriceFactor, nrow(load)))


    # Parameters with potential missing values and tech-based defaults
    parse_float_or_missing(v) =
        ismissing(v) ? missing :
        v isa Number ? Float64(v) :
        v isa AbstractString ? begin
            sv = strip(v)
            (isempty(sv) || lowercase(sv) == "n/a") ? missing : something(tryparse(Float64, sv), missing)
        end : missing

    tech_col_exists(c::Symbol) = !isempty(tech) && c in names(tech)
    tech_row_ix = if !isempty(tech) && :gen_type in names(tech)
        Dict(String(row.gen_type) => i for (i, row) in enumerate(eachrow(tech)))
    else
        Dict{String, Int}()
    end

    function tech_lookup(gen_type::AbstractString, col::Symbol; default=missing)
        haskey(tech_row_ix, gen_type) || return default
        tech_col_exists(col) || return default
        ix = tech_row_ix[String(gen_type)]
        v = parse_float_or_missing(tech[ix, col])
        ismissing(v) ? default : v
    end

    has_gen_pmin = :Pmin in names(gen)
    has_gen_om = :om_cost in names(gen)
    has_gcand_pmin = :Pmin in names(gcand)
    has_gcand_om = :om_cost in names(gcand)
    has_gcand_inv = :inv_cost in names(gcand)
    
    Pgmin = Dict(
        row.id => (has_gen_pmin ? Float64(row.Pmin) : Float64(tech_lookup(row.gen_type, :min_output_ratio; default=0.0) * row.capacity_mw)) / Sb
        for row in eachrow(gen)
    )
    Pgcost = Dict(
        row.id => (has_gen_om ? Float64(row.om_cost) : Float64(tech_lookup(row.gen_type, :variable_om_costs; default=0.0))) / PriceFactor
        for row in eachrow(gen)
    )
    Pkmin = Dict(
        row.id => (has_gcand_pmin ? Float64(row.Pmin) : Float64(tech_lookup(row.gen_type, :min_output_ratio; default=0.0) * row.capacity_mw)) / Sb
        for row in eachrow(gcand)
    )
    Pkcost = Dict(
        row.id => (has_gcand_om ? Float64(row.om_cost) : Float64(tech_lookup(row.gen_type, :variable_om_costs; default=0.0))) / PriceFactor
        for row in eachrow(gcand)
    )
    Pkinv = Dict(
        row.id => (
            has_gcand_inv ? Float64(row.inv_cost) :
            Float64(tech_lookup(row.gen_type, :capital_cost_CAD_MW_per_year; default=0.0) * row.capacity_mw)
        ) / PriceFactor
        for row in eachrow(gcand)
    )

    return Dict{Symbol, Any}(
        # Existing infrastructure parameters
        :Pgmax => Dict(gen.id .=> gen.capacity_mw ./ Sb),
        :Pgmin => Pgmin,
        :Pgcost => Pgcost,
        :Pgtype => pgtype,
        :Pgcf => Dict((g, o) => type_cf(pgtype[g], o, wind_cf, solar_cf) for g in gen.id for o in sce.hour),
        :Pd => Dict(load.id .=> load.demand_mw ./ Sb),
        :VoLL => VoLL,
        :Fmax => Dict(line.id .=> line.ttc_mw ./ Sb),
        :xe => xe,
        # Candidate infrastructure parameters
        :Pkmax => Dict(gcand.id .=> gcand.capacity_mw ./ Sb),
        :Pkmin => Pkmin,
        :Pkcost => Pkcost,
        :Pkinv => Pkinv,
        :Pktype => pktype,
        :Pkcf => Dict((k, o) => type_cf(pktype[k], o, wind_cf, solar_cf) for k in gcand.id for o in sce.hour),
        :Flinv => Dict(tcand.id .=> tcand.inv_cost ./ PriceFactor),
        :Fmaxl => Dict(tcand.id .=> tcand.ttc_mw ./ Sb),
        :xl => xl,
        # Economic and scenario parameters
        :ρ => Dict(sce.hour .=> sce.weight),
        :Pdf => Dict(sce.hour .=> sce.demand_factor),
        :Pdg => Dict(econ.t .=> econ.demand_growth),
        :α => Dict(econ.t .=> econ.a),
    )
end
