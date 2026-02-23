
function process_tgep_params(data, config::TEPConfig)
    gen, load, line, gcand, tcand = data[:gen], data[:load], data[:line], data[:gcand], data[:tcand]
    
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


    return (
        # Existing infrastructure parameters
        Pgmax = Dict(gen.id .=> gen.capacity_mw ./ Sb),
        Pgmin = Dict(gen.id .=> gen.Pmin ./ Sb),
        Pgcost = Dict(gen.id .=> gen.om_cost ./ PriceFactor),
        Pd = Dict(load.id .=> load.demand_mw ./ Sb),
        Fmax = Dict(line.id .=> line.ttc_mw ./ Sb),
        # Candidate infrastructure parameters
        Pkmax = Dict(gcand.id .=> gcand.capacity_mw ./ Sb),
        Pkmin = Dict(gcand.id .=> gcand.Pmin ./ Sb),
        Pkcost = Dict(gcand.id .=> gcand.om_cost ./ PriceFactor),
        Pkinv = Dict(gcand.id .=> gcand.inv_cost ./ PriceFactor),
        Flinv = Dict(tcand.id .=> tcand.inv_cost ./ PriceFactor),
        Fmaxl = Dict(tcand.id .=> tcand.ttc_mw ./ Sb),
        xe,
        xl,
    )
end
