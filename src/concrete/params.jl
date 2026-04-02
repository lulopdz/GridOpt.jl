# src/concrete/params.jl
include("utils.jl")

function process_tgep_params(data, config::TEPConfig)
    nodes, gen, load, line = data[:nodes], data[:gen], data[:load], data[:line]
    gcand, tcand = data[:gcand], data[:tcand]
    gtech, ttech = data[:gtech], data[:ttech]
    econ, sce = data[:econ], data[:sce]
    sto, stocand = data[:sto], data[:stocand]

    # Unit bases
    Sb = config.per_unit ? 100.0 : 1.0                          
    PriceFactor = config.per_unit ? 1.0e3 : 1.0                 
    default_voll = 1e4 / PriceFactor                       

    # Safe parsing helper for missing data
    parse_float(x, default=0.0) = begin
        if ismissing(x) return default end
        y = tryparse(Float64, string(x))
        return isnothing(y) ? default : y
    end

    # Extract unique hours since scenario.csv is now in long format (multiple rows per hour)
    unique_hours = sort(unique(sce[!, :hour]))

    # ==========================================================================
    # Geographic Topology Mapping
    node_to_region = Dict(r.node_code => r.region for r in eachrow(nodes))

    is_spatial_sce = hasproperty(sce, :node_code)
    
    # 1. Pre-declare dictionaries to fix the UndefVarError scoping issue
    nodal_demand = Dict{Tuple{String, Int}, Float64}()
    nodal_wind   = Dict{Tuple{String, Int}, Float64}()
    nodal_solar  = Dict{Tuple{String, Int}, Float64}()
    
    system_demand = Dict{Int, Float64}()
    system_wind   = Dict{Int, Float64}()
    system_solar  = Dict{Int, Float64}()
    
    hour_weights = Dict{Int, Float64}()

    # 2. Populate the correct dictionaries based on the scenario file format
    if is_spatial_sce
        nodal_demand = Dict((r.node_code, r.hour) => Float64(r.demand_factor) for r in eachrow(sce))
        nodal_wind   = Dict((r.node_code, r.hour) => Float64(r.wind_cf) for r in eachrow(sce) if hasproperty(sce, :wind_cf))
        nodal_solar  = Dict((r.node_code, r.hour) => Float64(r.solar_cf) for r in eachrow(sce) if hasproperty(sce, :solar_cf))
        hour_weights = Dict(r.hour => Float64(r.weight) for r in eachrow(sce))
    else
        system_demand = Dict(r.hour => Float64(r.demand_factor) for r in eachrow(sce))
        system_wind   = Dict(r.hour => Float64(r.wind_cf) for r in eachrow(sce) if hasproperty(sce, :wind_cf))
        system_solar  = Dict(r.hour => Float64(r.solar_cf) for r in eachrow(sce) if hasproperty(sce, :solar_cf))
        hour_weights  = Dict(r.hour => Float64(r.weight) for r in eachrow(sce))
    end

    # ==========================================================================
    # Dynamic Geographic Routers
    # ==========================================================================
    function get_cf(r, h)
        tech = lowercase(r.gen_type)
        if tech ∉ ["wind", "solar"]
            return 1.0 # Default 100% availability for thermal/baseload plants
        end

        target_nodal_dict = tech == "wind" ? nodal_wind : nodal_solar
        target_sys_dict   = tech == "wind" ? system_wind : system_solar

        if config.cf_resolution == :nodal && is_spatial_sce
            return get(target_nodal_dict, (r.node_code, h), 0.0)
            
        elseif config.cf_resolution == :regional && is_spatial_sce
            reg = get(node_to_region, r.node_code, "SYS")
            return get(target_nodal_dict, (reg, h), 0.0)
            
        else 
            return is_spatial_sce ? get(target_nodal_dict, ("SYS", h), 0.0) : get(target_sys_dict, h, 0.0)
        end
    end

    function get_demand(d, h)
        if is_spatial_sce && config.cf_resolution == :nodal
            return get(nodal_demand, (d.node_code, h), 1.0)
        elseif is_spatial_sce && config.cf_resolution == :regional
            reg = get(node_to_region, d.node_code, "SYS")
            return get(nodal_demand, (reg, h), 1.0)
        else
            return is_spatial_sce ? get(nodal_demand, ("SYS", h), 1.0) : get(system_demand, h, 1.0)
        end
    end

    # ==========================================================================
    # Technology Parameter Fallbacks 
    pmin_val(r) = hasproperty(r, :Pmin) ? r.Pmin : get_tech_param(gtech, r.gen_type, :min_output_ratio)
    ramp_val(r) = hasproperty(r, :ramp_rate) ? r.ramp_rate : get_tech_param(gtech, r.gen_type, :ramp_rate)
    om_val(r)   = hasproperty(r, :om_cost) ? r.om_cost : get_tech_param(gtech, r.gen_type, :variable_om_costs)
    fom_val(r)  = hasproperty(r, :fixed_om_cost) ? r.fixed_om_cost : get_tech_param(gtech, r.gen_type, :fixed_om_costs)
    inv_val(r)  = hasproperty(r, :inv_cost) ? r.inv_cost : get_tech_param(gtech, r.gen_type, :capital_cost_CAD_MW_per_year)
    
    # Dedicated storage lookup to avoid KeyErrors
    sto_inv_val(r) = hasproperty(r, :inv_cost) ? r.inv_cost : get_tech_param(gtech, r.gen_type, :capital_cost_CAD_MW_per_year)
    
    line_inv_val(r) = hasproperty(r, :inv_cost) ? r.inv_cost : get_line_tech_param(ttech, r.line_type, :annualized_project_costs_CAD_per_MWyear)
    em_val(r)   = get_tech_param(gtech, r.gen_type, :carbon_emissions)

    # ==========================================================================
    # Economic Data
    years = collect(econ.t)
    ctax = Dict(r.t => parse_float(r.carbon_tax / PriceFactor, 0.0) for r in eachrow(econ))

    netzero_cap = hasproperty(econ, :emission_cap) ?
        Dict(r.t => parse_float(r.emission_cap, Inf) for r in eachrow(econ)) :
        Dict(t => (t == last(years) ? 0.0 : Inf) for t in years)

    # ==========================================================================
    # Final Parameter Dictionary
    return Dict{Symbol, Any}(
        # Existing Generators
        :Pgmax  => Dict(gen.id .=> gen.capacity_mw ./ Sb),
        :Pgmin  => Dict(r.id => pmin_val(r) for r in eachrow(gen)),             
        :Pgramp => Dict(r.id => ramp_val(r) for r in eachrow(gen)),  
        :Pgcost => Dict(r.id => om_val(r) / PriceFactor for r in eachrow(gen)),
        :Pgfixed => Dict(r.id => fom_val(r) / PriceFactor for r in eachrow(gen)),
        :Pgem   => Dict(r.id => em_val(r) for r in eachrow(gen)),
        :Pgtype => Dict(gen.id .=> gen.gen_type),
        # Capacity Factors mapped as Tuple (Generator ID, Hour)
        :Pgcf   => Dict((g.id, h) => get_cf(g, h) for g in eachrow(gen), h in unique_hours),

        # Candidate Generators
        :Pkmax  => Dict(gcand.id .=> gcand.capacity_mw ./ Sb),
        :Pkmin  => Dict(r.id => pmin_val(r) for r in eachrow(gcand)),
        :Pkramp => Dict(r.id => ramp_val(r) for r in eachrow(gcand)),
        :Pkcost => Dict(r.id => om_val(r) / PriceFactor for r in eachrow(gcand)),
        :Pkfixed => Dict(r.id => fom_val(r) / PriceFactor for r in eachrow(gcand)),
        :Pkinv  => Dict(r.id => inv_val(r) / PriceFactor for r in eachrow(gcand)),
        :Pkem   => Dict(r.id => em_val(r) for r in eachrow(gcand)),
        :Pktype => Dict(gcand.id .=> gcand.gen_type),
        # Candidate Capacity Factors mapped as Tuple (Candidate ID, Hour)
        :Pkcf   => Dict((k.id, h) => get_cf(k, h) for k in eachrow(gcand), h in unique_hours),

        # Storage parameters 
        :Emax   => Dict(sto.id .=> sto.energy_mwh ./ Sb),
        :Pscmax => Dict(sto.id .=> sto.ch_capacity_mw ./ Sb),
        :Psdmax => Dict(sto.id .=> sto.dis_capacity_mw ./ Sb),
        :Einit  => Dict(sto.id .=> Float64.(sto.soc_init)),   
        :η_ch   => Dict(sto.id .=> Float64.(sto.ch_eff)),
        :η_dis  => Dict(sto.id .=> Float64.(sto.dis_eff)),

        # Candidate storage parameters
        :Ekmax   => Dict(stocand.id .=> stocand.energy_mwh ./ Sb),
        :Psckmax => Dict(stocand.id .=> stocand.ch_capacity_mw ./ Sb),
        :Psdkmax => Dict(stocand.id .=> stocand.dis_capacity_mw ./ Sb),
        :η_chk  => Dict(stocand.id .=> Float64.(stocand.ch_eff)),
        :η_disk => Dict(stocand.id .=> Float64.(stocand.dis_eff)),
        :Skinv   => Dict(r.id => sto_inv_val(r) / PriceFactor for r in eachrow(stocand)),

        # Network (Lines and Load)
        # Load profile mapped as Tuple (Load ID, Hour)
        :Pd   => Dict(load.id .=> load.demand_mw ./ Sb),
        :Pdf  => Dict((d.id, h) => get_demand(d, h) for d in eachrow(load), h in unique_hours),
        :VoLL => Dict(r.id => (hasproperty(r, :cost_LS) ? parse_float(r.cost_LS) / PriceFactor : default_voll) for r in eachrow(load)),
        
        :Fmax  => Dict(line.id .=> line.ttc_mw ./ Sb),
        :xe    => Dict(r.id => r.reactance_ohms / (config.per_unit ? (r.voltage_kv^2 / Sb) : r.voltage_kv^2) for r in eachrow(line)),
        
        :Fmaxl => Dict(tcand.id .=> tcand.ttc_mw ./ Sb),
        :Flinv => Dict(r.id => line_inv_val(r) / PriceFactor for r in eachrow(tcand)),
        :xl    => Dict(r.id => r.reactance_ohms / (config.per_unit ? (r.voltage_kv^2 / Sb) : r.voltage_kv^2) for r in eachrow(tcand)),

        # Economic / Temporal
        :ρ   => hour_weights,
        :Pdg => Dict(econ.t .=> econ.demand_growth),
        :α   => Dict(econ.t .=> econ.a),
        :Ctax => ctax,
        :NetZeroCap => netzero_cap,

        # Bases 
        :Sbase => Sb,
        :PriceFactor => PriceFactor
    )
end