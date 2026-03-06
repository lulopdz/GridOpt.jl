# src/concrete/params.jl
include("utils.jl")
function process_tgep_params(data, config::TEPConfig)
    gen, load, line = data[:gen], data[:load], data[:line]
    gcand, tcand = data[:gcand], data[:tcand]
    gtech, ttech = data[:gtech], data[:ttech]
    econ, sce = data[:econ], data[:sce]

    # Per unit conversion for reactances and cost scaling
    Sb = config.per_unit ? 100.0 : 1.0
    PriceFactor = config.per_unit ? 1.0e3 : 1.0
    default_voll = 10_000.0 / PriceFactor

    # Pre-process capacity factors 
    wind_cf = hasproperty(sce, :wind_cf) ? Dict(sce.hour .=> Float64.(sce.wind_cf)) : Dict()
    solar_cf = hasproperty(sce, :solar_cf) ? Dict(sce.hour .=> Float64.(sce.solar_cf)) : Dict()

    # Getting generator parameters with tech fallback
    pmin_val(r) = hasproperty(r, :Pmin) ? r.Pmin : get_tech_param(gtech, r.gen_type, :min_output_ratio) * r.capacity_mw
    om_val(r)   = hasproperty(r, :om_cost) ? r.om_cost : get_tech_param(gtech, r.gen_type, :variable_om_costs)
    inv_val(r)  = hasproperty(r, :inv_cost) ? r.inv_cost : get_tech_param(gtech, r.gen_type, :capital_cost_CAD_MW_per_year) * r.capacity_mw

    return (
        # Existing Generators
        Pgmax  = Dict(gen.id .=> gen.capacity_mw ./ Sb),
        Pgmin  = Dict(r.id => pmin_val(r) / Sb for r in eachrow(gen)),
        Pgcost = Dict(r.id => om_val(r) / PriceFactor for r in eachrow(gen)),
        Pgtype = Dict(gen.id .=> gen.gen_type),
        Pgcf   = Dict((g.id, h) => get_cf(g.gen_type, h, wind_cf, solar_cf) for g in eachrow(gen), h in sce.hour),

        # Candidate Generators
        Pkmax  = Dict(gcand.id .=> gcand.capacity_mw ./ Sb),
        Pkmin  = Dict(r.id => pmin_val(r) / Sb for r in eachrow(gcand)),
        Pkcost = Dict(r.id => om_val(r) / PriceFactor for r in eachrow(gcand)),
        Pkinv  = Dict(r.id => inv_val(r) / PriceFactor for r in eachrow(gcand)),
        Pktype = Dict(gcand.id .=> gcand.gen_type),
        Pkcf   = Dict((k.id, h) => get_cf(k.gen_type, h, wind_cf, solar_cf) for k in eachrow(gcand), h in sce.hour),

        # Network (Lines and Load)
        Pd   = Dict(load.id .=> load.demand_mw ./ Sb),
        VoLL = Dict(load.id .=> (hasproperty(load, :cost_LS) ? load.cost_LS ./ PriceFactor : default_voll)),
        
        Fmax  = Dict(line.id .=> line.ttc_mw ./ Sb),
        xe    = Dict(r.id => r.reactance / (config.per_unit ? (r.voltage^2 / Sb) : 1.0) for r in eachrow(line)),
        
        Fmaxl = Dict(tcand.id .=> tcand.ttc_mw ./ Sb),
        Flinv = Dict(tcand.id .=> tcand.inv_cost ./ PriceFactor),
        xl    = Dict(r.id => r.reactance / (config.per_unit ? (r.voltage^2 / Sb) : 1.0) for r in eachrow(tcand)),

        # Economic / Temporal
        ρ   = Dict(sce.hour .=> sce.weight),
        Pdf = Dict(sce.hour .=> sce.demand_factor),
        Pdg = Dict(econ.t .=> econ.demand_growth),
        α   = Dict(econ.t .=> econ.a)
    )
end