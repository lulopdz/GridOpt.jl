# ==============================================================================
# Investment reporting for TGEP
function gen_inv_df(model, sets, params)
    K, T = sets[:K], sets[:T]
    Pkinv = params[:Pkinv]
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    α = params[:α]

    pkmax_val = value.(model[:pkmax])

    df = DataFrame([(; 
        gen_id = k, 
        year = t, 
        added_mw = Sb * pkmax_val[k, t]
    ) for k in K for t in T])
    
    sort!(df, [:gen_id, :year])
    transform!(groupby(df, :gen_id), :added_mw => cumsum => :total_mw)

    df.base_cost = [Pkinv[k] * PriceFactor for k in df.gen_id]
    df.year_factor = [get(α, t, 1.0) for t in df.year]
    df.unit_cost = df.base_cost .* df.year_factor
    df.inv_cost = df.total_mw .* df.unit_cost

    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end
    
    return df
end

function sto_inv_df(model, sets, params)
    Sk, T = sets[:Sk], sets[:T]
    Skinv = params[:Skinv]
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    α = params[:α]

    ekmax_val = value.(model[:ekmax])

    df = DataFrame([(; 
        storage_id = s, 
        year = t,
        added_mwh = Sb * ekmax_val[s, t]
    ) for s in Sk for t in T])

    sort!(df, [:storage_id, :year])
    transform!(groupby(df, :storage_id), :added_mwh => cumsum => :total_mwh)

    df.base_cost = [Skinv[s] * PriceFactor for s in df.storage_id]
    df.year_factor = [get(α, t, 1.0) for t in df.year]
    df.unit_cost = df.base_cost .* df.year_factor
    df.inv_cost = df.total_mwh .* df.unit_cost

    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end

    return df
end

function line_inv_df(model, cfg::TEPConfig, sets, params)
    cfg.include_network || return DataFrame()
    
    L, T = sets[:L], sets[:T]
    Flinv, Fmaxl = params[:Flinv], params[:Fmaxl]
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    α = params[:α]
    
    β_val = value.(model[:β])

    df = DataFrame([(; 
        line_id = l, 
        year = t, 
        built = β_val[l, t] > 0.5
    ) for l in L for t in T])

    sort!(df, [:line_id, :year])
    transform!(groupby(df, :line_id), :built => (x -> cumsum(Int.(x)) .> 0) => :active)
    
    df.base_cost = [Sb * PriceFactor * Flinv[l] * Fmaxl[l] for l in df.line_id]
    df.year_factor = [get(α, t, 1.0) for t in df.year]
    df.unit_cost = df.base_cost .* df.year_factor
    df.inv_cost = [a ? cost : 0.0 for (a, cost) in zip(df.active, df.unit_cost)]

    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end
    
    return df
end

# ==============================================================================
# Operation reporting

function gen_dispatch_df(model, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    ρ, Sb = params[:ρ], params[:Sbase]
    
    pg_val = value.(model[:pg])
    pk_val = value.(model[:pk])
    
    ex_df = DataFrame([(; 
        type = "existing", gen_id = g, year = t, hour = o, weight = ρ[o],
        dispatch_mw = Sb * pg_val[g, t, o]
    ) for g in G for t in T for o in O])
    
    cand_df = DataFrame([(; 
        type = "candidate", gen_id = k, year = t, hour = o, weight = ρ[o],
        dispatch_mw = Sb * pk_val[k, t, o]
    ) for k in K for t in T for o in O])
    
    df = vcat(ex_df, cand_df)

    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end
    
    return df
end

function load_shedding_df(model, sets, params)
    D, T, O = sets[:D], sets[:T], sets[:O]
    Pd, Pdf, Pdg = params[:Pd], params[:Pdf], params[:Pdg]
    ρ, Sb = params[:ρ], params[:Sbase]

    ls_val = value.(model[:ls])

    df = DataFrame([(; 
        load_id = d, 
        year = t, 
        hour = o, 
        weight = ρ[o],
        shed_mw = Sb * ls_val[d, t, o],
        demand_mw = Sb * Pd[d] * Pdf[(d, o)] * Pdg[t] 
    ) for d in D for t in T for o in O])
    
    df.shed_pct = ifelse.(df.demand_mw .> 0, 100.0 .* df.shed_mw ./ df.demand_mw, 0.0)
    
    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end
    
    return df
end

function sto_operation_df(model, sets, params)
    S, Sk, T, O = sets[:S], sets[:Sk], sets[:T], sets[:O]
    ρ, Sb = params[:ρ], params[:Sbase]

    # Quick exit if no storage exists to prevent type inference issues on empty arrays
    if isempty(S) && isempty(Sk)
        return DataFrame(storage_id=String[], status=String[], year=Int[], hour=Int[], 
                         weight=Float64[], charge_mw=Float64[], discharge_mw=Float64[], 
                         net_discharge_mw=Float64[], soc_mwh=Float64[])
    end

    pch_val, pdis_val, soc_val = value.(model[:pch]), value.(model[:pdis]), value.(model[:soc])
    pchk_val, pdisk_val, sock_val = value.(model[:pchk]), value.(model[:pdisk]), value.(model[:sock])

    ex_df = DataFrame([(;
        storage_id = s, status = "existing", year = t, hour = o, weight = ρ[o],
        charge_mw = Sb * pch_val[s, t, o],
        discharge_mw = Sb * pdis_val[s, t, o],
        soc_mwh = Sb * soc_val[s, t, o]
    ) for s in S for t in T for o in O])
    
    cand_df = DataFrame([(;
        storage_id = s, status = "candidate", year = t, hour = o, weight = ρ[o],
        charge_mw = Sb * pchk_val[s, t, o],
        discharge_mw = Sb * pdisk_val[s, t, o],
        soc_mwh = Sb * sock_val[s, t, o]
    ) for s in Sk for t in T for o in O])

    df = vcat(ex_df, cand_df)

    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end

    return df
end

function line_flow_df(model, cfg::TEPConfig, sets, params, year=nothing, hour=nothing)
    cfg.include_network || return DataFrame()
    
    E, L, T, O = sets[:E], sets[:L], sets[:T], sets[:O]
    Sb = params[:Sbase]
    Fmax, Fmaxl = params[:Fmax], params[:Fmaxl]
    
    ts = isnothing(year) ? T : [year]
    os = isnothing(hour) ? O : [hour]
    
    f_val = value.(model[:f])
    fl_val = value.(model[:fl])
    
    ex_df = DataFrame([(; 
        type = "existing", line_id = e, year = t, hour = o, 
        flow_mw = Sb * f_val[e, t, o],
        limit_mw = Sb * Fmax[e],
        loading_pct = (abs(f_val[e, t, o]) / Fmax[e]) * 100.0
    ) for e in E for t in ts for o in os])
    
    cand_df = DataFrame([(; 
        type = "candidate", line_id = l, year = t, hour = o, 
        flow_mw = Sb * fl_val[l, t, o],
        limit_mw = Sb * Fmaxl[l],
        # Protect against division by zero if a candidate line has 0 capacity defined
        loading_pct = Fmaxl[l] > 0 ? (abs(fl_val[l, t, o]) / Fmaxl[l]) * 100.0 : 0.0
    ) for l in L for t in ts for o in os])
    
    df = vcat(ex_df, cand_df)

    # Dynamic rounding block applies cleanly to the new Float columns too
    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end
    
    return df
end

# ==============================================================================
# Cost summary

function cost_breakdown(model, cfg::TEPConfig, sets, params)
    G, K, Sk, L, D, T, O = sets[:G], sets[:K], sets[:Sk], sets[:L], sets[:D], sets[:T], sets[:O]
    α, ρ = params[:α], params[:ρ]
    Pgcost, Pkcost, Pkinv, Skinv = params[:Pgcost], params[:Pkcost], params[:Pkinv], params[:Skinv]
    Pgfixed, Pkfixed = params[:Pgfixed], params[:Pkfixed]
    VoLL, Pgmax = params[:VoLL], params[:Pgmax]
    Flinv, Fmaxl = params[:Flinv], params[:Fmaxl]
    Ctax = get(params, :Ctax, Dict(t => 0.0 for t in T))
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    
    has_em = haskey(model, :em)

    # 1. Extract all solver values upfront
    pg_val = value.(model[:pg])
    pk_val = value.(model[:pk])
    ls_val = value.(model[:ls])
    pkmax_val = value.(model[:pkmax])
    ekmax_val = value.(model[:ekmax])
    β_val = cfg.include_network ? value.(model[:β]) : nothing
    em_val = has_em ? value.(model[:em]) : nothing

    results = []

    # 2. Build the Yearly DataFrame
    for t in T
        mult = Sb * α[t] * PriceFactor 

        # Operating Costs
        op_ex   = mult * sum(ρ[o] * Pgcost[g] * pg_val[g, t, o] for g in G, o in O; init=0.0)
        op_cand = mult * sum(ρ[o] * Pkcost[k] * pk_val[k, t, o] for k in K, o in O; init=0.0)
        op_shed = mult * sum(ρ[o] * VoLL[d] * ls_val[d, t, o] for d in D, o in O; init=0.0)

        # Investment Costs
        inv_gen  = mult * sum(Pkinv[k] * sum(pkmax_val[k, τ] for τ in 1:t) for k in K; init=0.0)
        inv_sto  = mult * sum(Skinv[s] * sum(ekmax_val[s, τ] for τ in 1:t) for s in Sk; init=0.0)
        inv_line = cfg.include_network ? mult * sum(Flinv[l] * Fmaxl[l] * sum(β_val[l, τ] for τ in 1:t) for l in L; init=0.0) : 0.0

        # Fixed O&M Costs
        fix_ex   = mult * sum(Pgfixed[g] * Pgmax[g] for g in G; init=0.0)
        fix_cand = mult * sum(Pkfixed[k] * sum(pkmax_val[k, τ] for τ in 1:t) for k in K; init=0.0)

        # Carbon Costs
        carbon = (has_em && cfg.include_carbon_tax) ? (α[t] * PriceFactor * Ctax[t] * sum(ρ[o] * em_val[t, o] for o in O; init=0.0)) : 0.0

        push!(results, (;
            year = t,
            op_existing = op_ex,
            op_candidate = op_cand,
            op_shedding = op_shed,
            inv_gen = inv_gen,
            inv_storage = inv_sto,
            inv_line = inv_line,
            fixed_existing = fix_ex,
            fixed_candidate = fix_cand,
            carbon = carbon,
            # Core Subtotals per year
            total_op = op_ex + op_cand,
            total_inv = inv_gen + inv_sto + inv_line,
            total_fixed = fix_ex + fix_cand
        ))
    end

    yearly_df = DataFrame(results)
    yearly_df.total_cost = yearly_df.total_op .+ yearly_df.op_shedding .+ yearly_df.total_inv .+ yearly_df.total_fixed .+ yearly_df.carbon

    # 3. Create a Detailed, Hierarchical Summary DataFrame
    summary_df = DataFrame(
        Category = [
            "Operations", "Operations", "Operations", "Operations",
            "Investment", "Investment", "Investment", "Investment",
            "Fixed O&M", "Fixed O&M", "Fixed O&M",
            "Carbon", 
            "System Total"
        ],
        Subcategory = [
            "Existing Generation", "Candidate Generation", "Load Shedding", "SUBTOTAL",
            "Generation", "Storage", "Transmission Lines", "SUBTOTAL",
            "Existing Generation", "Candidate Generation", "SUBTOTAL",
            "Total Carbon Tax", 
            "GRAND TOTAL"
        ],
        Cost = [
            sum(yearly_df.op_existing), 
            sum(yearly_df.op_candidate), 
            sum(yearly_df.op_shedding), 
            sum(yearly_df.total_op) + sum(yearly_df.op_shedding),
            
            sum(yearly_df.inv_gen), 
            sum(yearly_df.inv_storage), 
            sum(yearly_df.inv_line), 
            sum(yearly_df.total_inv),
            
            sum(yearly_df.fixed_existing), 
            sum(yearly_df.fixed_candidate), 
            sum(yearly_df.total_fixed),
            
            sum(yearly_df.carbon), 
            sum(yearly_df.total_cost)
        ]
    )

    # 4. Dynamic Rounding for both DataFrames
    for df in (yearly_df, summary_df)
        for col in names(df)
            if eltype(df[!, col]) <: AbstractFloat
                df[!, col] = round.(df[!, col], digits=2)
            end
        end
    end
    
    return (summary=summary_df, yearly=yearly_df)
end

# ==============================================================================
# Yearly summary for reporting

function yearly_supply_demand(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    S, Sk = sets[:S], sets[:Sk]
    
    ρ, Pdf, Pdg = params[:ρ], params[:Pdf], params[:Pdg]
    Pd, Sb = params[:Pd], params[:Sbase]
    gwh = 1.0 / 1000.0
    
    pg, pk, ls = value.(model[:pg]), value.(model[:pk]), value.(model[:ls])
    pch, pdis = value.(model[:pch]), value.(model[:pdis])
    pchk, pdisk = value.(model[:pchk]), value.(model[:pdisk])

    # Replaced 'results = []' with a fast comprehension
    df = DataFrame([begin
        dem = sum(ρ[o] * Sb * Pd[d] * Pdf[(d, o)] * Pdg[t] for d in D, o in O; init=0.0) * gwh
        shed = sum(ρ[o] * Sb * ls[d, t, o] for d in D, o in O; init=0.0) * gwh
        
        ex_gen = sum(ρ[o] * Sb * pg[g, t, o] for g in G, o in O; init=0.0) * gwh
        cand_gen = sum(ρ[o] * Sb * pk[k, t, o] for k in K, o in O; init=0.0) * gwh
        
        ex_sto = sum(ρ[o] * Sb * (pdis[s, t, o] - pch[s, t, o]) for s in S, o in O; init=0.0) * gwh
        cand_sto = sum(ρ[o] * Sb * (pdisk[s, t, o] - pchk[s, t, o]) for s in Sk, o in O; init=0.0) * gwh
        
        tot_sup = ex_gen + cand_gen + ex_sto + cand_sto
        gap = (tot_sup + shed) - dem

        (; year = t, demand_gwh = dem, load_shed_gwh = shed,
           existing_gen_gwh = ex_gen, candidate_gen_gwh = cand_gen,
           existing_sto_net_gwh = ex_sto, candidate_sto_net_gwh = cand_sto,
           total_supply_gwh = tot_sup, balance_gap_gwh = gap)
    end for t in T])
    
    for col in names(df)
        if eltype(df[!, col]) <: AbstractFloat
            df[!, col] = round.(df[!, col], digits=2)
        end
    end

    return df
end