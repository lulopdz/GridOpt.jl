# src/concrete/params.jl
include("utils.jl")
function process_tgep_params(data, config::TEPConfig)
    gen, load, line = data[:gen], data[:load], data[:line]
    gcand, tcand = data[:gcand], data[:tcand]
    gtech, ttech = data[:gtech], data[:ttech]
    econ, sce = data[:econ], data[:sce]

    # Unit bases
    Sb = config.per_unit ? 100.0 : 1.0                          # Power base (MW)
    PriceFactor = config.per_unit ? 1.0e3 : 1.0                 # Price scaling (to kCAD/MWh)
    default_voll = 1e4 / PriceFactor                       # Default Value of Lost Load ($/MWh)

    # Pre-process capacity factors 
    wind_cf = hasproperty(sce, :wind_cf) ? Dict(sce.hour .=> Float64.(sce.wind_cf)) : Dict()
    solar_cf = hasproperty(sce, :solar_cf) ? Dict(sce.hour .=> Float64.(sce.solar_cf)) : Dict()

    # Getting generator parameters with tech fallback
    pmin_val(r) = hasproperty(r, :Pmin) ? r.Pmin : get_tech_param(gtech, r.gen_type, :min_output_ratio)
    ramp_val(r) = hasproperty(r, :ramp_rate) ? r.ramp_rate : get_tech_param(gtech, r.gen_type, :ramp_rate)
    om_val(r)   = hasproperty(r, :om_cost) ? r.om_cost : get_tech_param(gtech, r.gen_type, :variable_om_costs)
    fom_val(r)  = hasproperty(r, :fixed_om_cost) ? r.fixed_om_cost : get_tech_param(gtech, r.gen_type, :fixed_om_costs)
    inv_val(r)  = hasproperty(r, :inv_cost) ? r.inv_cost : get_tech_param(gtech, r.gen_type, :capital_cost_CAD_MW_per_year)
    line_inv_val(r) = hasproperty(r, :inv_cost) ? r.inv_cost : get_line_tech_param(ttech, r.line_type, :annualized_project_costs_CAD_per_MWyear)
    
    # Emission intensity is defined at the technology level (tCO2 per MWh).
    em_val(r)   = get_tech_param(gtech, r.gen_type, :carbon_emissions)

    parse_float(x, default=0.0) = begin
        if ismissing(x)
            return default
        end
        y = tryparse(Float64, string(x))
        return isnothing(y) ? default : y
    end

    years = collect(econ.t)
    ctax = Dict(r.t => parse_float(r.carbon_tax / PriceFactor, 0.0) for r in eachrow(econ))

    # If no cap trajectory is provided, enforce net-zero in final period only.
    netzero_cap = hasproperty(econ, :emission_cap) ?
        Dict(r.t => parse_float(r.emission_cap, Inf) for r in eachrow(econ)) :
        Dict(t => (t == last(years) ? 0.0 : Inf) for t in years)

    return Dict{Symbol, Any}(
        # Existing Generators
        :Pgmax  => Dict(gen.id .=> gen.capacity_mw ./ Sb),
        :Pgmin  => Dict(r.id => pmin_val(r) for r in eachrow(gen)),             # Ratio
        :Pgramp => Dict(r.id => ramp_val(r) for r in eachrow(gen)),  # Ratio of Pmax per hour
        :Pgcost => Dict(r.id => om_val(r) / PriceFactor for r in eachrow(gen)),
        :Pgfixed => Dict(r.id => fom_val(r) / PriceFactor for r in eachrow(gen)),
        :Pgem => Dict(r.id => em_val(r) for r in eachrow(gen)),
        :Pgtype => Dict(gen.id .=> gen.gen_type),
        :Pgcf   => Dict((g.id, h) => get_cf(g.gen_type, h, wind_cf, solar_cf) for g in eachrow(gen), h in sce.hour),

        # Candidate Generators
        :Pkmax  => Dict(gcand.id .=> gcand.capacity_mw ./ Sb),
        :Pkmin  => Dict(r.id => pmin_val(r) for r in eachrow(gcand)),
        :Pkramp => Dict(r.id => ramp_val(r) for r in eachrow(gcand)),
        :Pkcost => Dict(r.id => om_val(r) / PriceFactor for r in eachrow(gcand)),
        :Pkfixed => Dict(r.id => fom_val(r) / PriceFactor for r in eachrow(gcand)),
        :Pkinv  => Dict(r.id => inv_val(r) / PriceFactor for r in eachrow(gcand)),
        :Pkem   => Dict(r.id => em_val(r) for r in eachrow(gcand)),
        :Pktype => Dict(gcand.id .=> gcand.gen_type),
        :Pkcf   => Dict((k.id, h) => get_cf(k.gen_type, h, wind_cf, solar_cf) for k in eachrow(gcand), h in sce.hour),

        # Network (Lines and Load)
        :Pd   => Dict(load.id .=> load.demand_mw ./ Sb),
        :VoLL => Dict(load.id .=> (hasproperty(load, :cost_LS) ? load.cost_LS / PriceFactor : default_voll)),
        
        :Fmax  => Dict(line.id .=> line.ttc_mw ./ Sb),
        :xe    => Dict(r.id => r.reactance / (config.per_unit ? (r.voltage^2 / Sb) : r.voltage^2) for r in eachrow(line)),
        
        :Fmaxl => Dict(tcand.id .=> tcand.ttc_mw ./ Sb),
        :Flinv => Dict(r.id => line_inv_val(r) / PriceFactor for r in eachrow(tcand)),
        :xl    => Dict(r.id => r.reactance / (config.per_unit ? (r.voltage^2 / Sb) : r.voltage^2) for r in eachrow(tcand)),

        # Economic / Temporal
        :ρ   => Dict(sce.hour .=> sce.weight),
        :Pdf => Dict(sce.hour .=> sce.demand_factor),
        :Pdg => Dict(econ.t .=> econ.demand_growth),
        :α   => Dict(econ.t .=> econ.a),
        :Ctax => ctax,
        :NetZeroCap => netzero_cap,

        # Bases 
        :Sbase => Sb,
        :PriceFactor => PriceFactor
    )
end