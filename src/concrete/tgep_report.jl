using Printf
using Plots
using DataFrames, CSV

include("../utils/plot_defaults.jl")
set_theme()

function capacity_inv_df(model, sets, params)
    K, Sk, T = sets[:K], sets[:Sk], sets[:T]
    pkmax, ekmax = model[:pkmax], model[:ekmax]
    Pkinv, Skinv = params[:Pkinv], params[:Skinv]
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    α = params[:α]

    df = DataFrame([(; gen_id=k, year=t, 
        capacity_added_mw=Sb * value(pkmax[k, t])) for k in K for t in T])
    
    sort!(df, [:gen_id, :year])
    transform!(groupby(df, :gen_id), 
            :capacity_added_mw => cumsum => :cumulative_capacity_mw)

    # Keep both base and year-adjusted prices for transparent reporting.
    df.base_price_per_mw = [Pkinv[k] * PriceFactor for k in df.gen_id]
    df.year_price_factor = [get(α, t, 1.0) for t in df.year]
    df.price_per_mw = df.base_price_per_mw .* df.year_price_factor
    df.annual_investment_cost = df.cumulative_capacity_mw .* df.price_per_mw

    # Round report outputs for readability.
    df.capacity_added_mw = round.(df.capacity_added_mw, digits=2)
    df.cumulative_capacity_mw = round.(df.cumulative_capacity_mw, digits=2)
    df.base_price_per_mw = round.(df.base_price_per_mw, digits=2)
    df.year_price_factor = round.(df.year_price_factor, digits=2)
    df.price_per_mw = round.(df.price_per_mw, digits=2)
    df.annual_investment_cost = round.(df.annual_investment_cost, digits=2)
    
    return df
end

function storage_inv_df(model, sets, params)
    Sk, T = sets[:Sk], sets[:T]
    ekmax = model[:ekmax]
    Skinv = params[:Skinv]
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    α = params[:α]

    df = DataFrame([(; storage_id=s, year=t,
        energy_added_mwh=Sb * value(ekmax[s, t])) for s in Sk for t in T])

    sort!(df, [:storage_id, :year])
    transform!(groupby(df, :storage_id),
            :energy_added_mwh => cumsum => :cumulative_energy_mwh)

    # Keep both base and year-adjusted prices for transparent reporting.
    df.base_price_per_mwh = [Skinv[s] * PriceFactor for s in df.storage_id]
    df.year_price_factor = [get(α, t, 1.0) for t in df.year]
    df.price_per_mwh = df.base_price_per_mwh .* df.year_price_factor
    df.annual_investment_cost = df.cumulative_energy_mwh .* df.price_per_mwh

    # Round report outputs for readability.
    df.energy_added_mwh = round.(df.energy_added_mwh, digits=2)
    df.cumulative_energy_mwh = round.(df.cumulative_energy_mwh, digits=2)
    df.base_price_per_mwh = round.(df.base_price_per_mwh, digits=2)
    df.year_price_factor = round.(df.year_price_factor, digits=2)
    df.price_per_mwh = round.(df.price_per_mwh, digits=2)
    df.annual_investment_cost = round.(df.annual_investment_cost, digits=2)

    return df
end

function gen_dispatch_df(model, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    pg, pk = model[:pg], model[:pk]
    ρ = params[:ρ]
    Sb = params[:Sbase]
    
    existing  = DataFrame([(; type="existing", id=g, year=t, hour=o, weight=ρ[o],
        dispatch_mw=round(Sb * value(pg[g, t, o]), digits=2)) for g in G for t in T for o in O])
    candidate = DataFrame([(; type="candidate", id=k, year=t, hour=o, weight=ρ[o],
        dispatch_mw=round(Sb * value(pk[k, t, o]), digits=2)) for k in K for t in T for o in O])
    
    return vcat(existing, candidate)
end

function load_shedding_df(model, sets, params)
    D, T, O = sets[:D], sets[:T], sets[:O]
    Pd, Pdf, Pdg = params[:Pd], params[:Pdf], params[:Pdg]
    ρ = params[:ρ]
    Sb = params[:Sbase]

    ls_vals = value.(model[:ls])

    df = DataFrame([(; 
        load_id = d, 
        year = t, 
        hour = o, 
        weight = ρ[o],
        shed_mw = round(Sb * ls_vals[d, t, o], digits=2),
        demand_mw = round(Sb * Pd[d] * Pdf[(d, o)] * Pdg[t], digits=2) # <-- Fixed Tuple Indexing
    ) for d in D for t in T for o in O])
    
    df.shed_pct = ifelse.(df.demand_mw .> 0, round.(100.0 .* df.shed_mw ./ df.demand_mw, digits=2), 0.0)
    
    return df
end

function line_inv_df(model, cfg::TEPConfig, sets, params)
    cfg.include_network || return DataFrame()
    L, T = sets[:L], sets[:T]
    β = model[:β]
    Flinv, Fmaxl = params[:Flinv], params[:Fmaxl]
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    α = params[:α]
    
    df = DataFrame([(; line_id=l, year=t, 
            built=(value(β[l, t]) > 0.5)) for l in L for t in T])

    sort!(df, [:line_id, :year])
    transform!(groupby(df, :line_id), 
            :built => (x -> cumsum(Int.(x)) .> 0) => :active)
    
    # Keep both base and year-adjusted prices for transparent reporting.
    df.base_line_cost = [Sb * PriceFactor * Flinv[l] * Fmaxl[l] for l in df.line_id]
    df.year_price_factor = [get(α, t, 1.0) for t in df.year]
    df.line_cost = df.base_line_cost .* df.year_price_factor
    df.annual_investment_cost = [a ? cost : 0.0 for (a, cost) in zip(df.active, df.line_cost)]

    # Round report outputs for readability.
    df.base_line_cost = round.(df.base_line_cost, digits=2)
    df.year_price_factor = round.(df.year_price_factor, digits=2)
    df.line_cost = round.(df.line_cost, digits=2)
    df.annual_investment_cost = round.(df.annual_investment_cost, digits=2)
    
    return df
end


function line_flow_df(model, cfg::TEPConfig, sets, params, year=nothing, hour=nothing)
    cfg.include_network || return DataFrame()
    E, L, T, O = sets[:E], sets[:L], sets[:T], sets[:O]
    f, fl = model[:f], model[:fl]
    Sb = params[:Sbase]
    
    ts = isnothing(year) ? T : [year]
    os = isnothing(hour) ? O : [hour]
    
    existing  = DataFrame([(; type="existing", line_id=e, year=t, hour=o, 
            flow_mw=round(Sb * value(f[e, t, o]), digits=2)) for e in E for t in ts for o in os])
    candidate = DataFrame([(; type="candidate", line_id=l, year=t, hour=o, 
            flow_mw=round(Sb * value(fl[l, t, o]), digits=2)) for l in L for t in ts for o in os])
    
    return vcat(existing, candidate)
end


function cost_breakdown(model, cfg::TEPConfig, sets, params)
    G, K, Sk, L, T, O = sets[:G], sets[:K], sets[:Sk], sets[:L], sets[:T], sets[:O]
    α, ρ = params[:α], params[:ρ]
    Pgcost, Pkcost, Pkinv, Skinv = params[:Pgcost], params[:Pkcost], params[:Pkinv], params[:Skinv]
    Pgfixed, Pkfixed = params[:Pgfixed], params[:Pkfixed]
    VoLL, Pgmax = params[:VoLL], params[:Pgmax]
    Flinv, Fmaxl = params[:Flinv], params[:Fmaxl]
    Ctax = get(params, :Ctax, Dict(t => 0.0 for t in T))
    Sb, PriceFactor = params[:Sbase], params[:PriceFactor]
    has_em = haskey(model, :em)

    op = DataFrame([(; 
        year = t,
        existing_gen = round(Sb * α[t] * sum(ρ[o] * PriceFactor * Pgcost[g] * 
                value(model[:pg][g, t, o]) for g in G, o in O), digits=2),
        candidate_gen = round(Sb * α[t] * sum(ρ[o] * PriceFactor * Pkcost[k] * 
                value(model[:pk][k, t, o]) for k in K, o in O), digits=2),
        load_shed = round(Sb * α[t] * sum(ρ[o] * PriceFactor * VoLL[d] * 
                value(model[:ls][d, t, o]) for d in sets[:D], o in O), digits=2)
    ) for t in T])
    op.total_op = round.(op.existing_gen .+ op.candidate_gen, digits=2)


    inv = DataFrame([(;
        year = t,
        gen_inv = round(Sb * α[t] * sum(PriceFactor * Pkinv[k] * 
                sum(value(model[:pkmax][k, τ]) for τ in 1:t) for k in K), digits=2),
        storage_inv = round(Sb * α[t] * sum(PriceFactor * Skinv[s] *
            sum(value(model[:ekmax][s, τ]) for τ in 1:t) for s in Sk), digits=2),
        line_inv = round(cfg.include_network ? Sb * α[t] * 
                sum(PriceFactor * Flinv[l] * Fmaxl[l] * 
                sum(value(model[:β][l, τ]) for τ in 1:t) for l in L) : 0.0, digits=2)
    ) for t in T])
        inv.total_inv = round.(inv.gen_inv .+ inv.storage_inv .+ inv.line_inv, digits=2)

    fixed = DataFrame([(; 
        year = t,
        existing_fixed = round(Sb * α[t] * 
                sum(PriceFactor * Pgfixed[g] * Pgmax[g] for g in G), digits=2),
        candidate_fixed = round(Sb * α[t] * 
                sum(PriceFactor * Pkfixed[k] * 
                sum(value(model[:pkmax][k, τ]) for τ in 1:t) for k in K), digits=2)
    ) for t in T])
    fixed.total_fixed = round.(fixed.existing_fixed .+ fixed.candidate_fixed, digits=2)

    if cfg.include_carbon_tax
        carbon = DataFrame([(; 
            year = t,
            carbon_cost = round(has_em ? α[t] * 
                    sum(ρ[o] * PriceFactor * Ctax[t] * 
                    value(model[:em][t, o]) for o in O) : 0.0, digits=2)
        ) for t in T])
    else
        carbon = DataFrame([(; year = t, carbon_cost = 0.0) for t in T])
    end

    total_op, total_load_shed, total_inv = sum(op.total_op), sum(op.load_shed), sum(inv.total_inv)
    total_fixed, total_carbon = sum(fixed.total_fixed), sum(carbon.carbon_cost)
    total_cost = total_op + total_load_shed + total_inv + total_fixed + total_carbon
    summary = DataFrame(
        category=["Operating Cost", "Load Shedding Cost", "Investment Cost", "Fixed O&M Cost", "Carbon Cost", "Total Cost"],
        value=round.([total_op, total_load_shed, total_inv, total_fixed, total_carbon, total_cost], digits=2)
    )
    
    return (summary=summary, operating=op, investment=inv, fixed=fixed, carbon=carbon)
end

function yearly_supply_demand(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    S, Sk = sets[:S], sets[:Sk] # Brought in storage sets
    
    ρ, Pdf, Pdg = params[:ρ], params[:Pdf], params[:Pdg]
    Pd = params[:Pd]
    Sb = params[:Sbase]
    
    gwh = 1.0 / 1000.0
    
    # Extract variable values once for speed
    pg = value.(model[:pg])
    pk = value.(model[:pk])
    ls = value.(model[:ls])
    
    pch, pdis = value.(model[:pch]), value.(model[:pdis])
    pchk, pdisk = value.(model[:pchk]), value.(model[:pdisk])

    results = []

    for t in T
        # 1. Base Demand (Fixed Tuple Indexing)
        demand_gwh = sum(ρ[o] * Sb * Pd[d] * Pdf[(d, o)] * Pdg[t] for d in D, o in O) * gwh
        
        # 2. Load Shedding (Unmet Demand)
        shed_gwh = sum(ρ[o] * Sb * ls[d, t, o] for d in D, o in O) * gwh

        # 3. Generation Supply
        exist_gen_gwh = sum(ρ[o] * Sb * pg[g, t, o] for g in G, o in O) * gwh
        cand_gen_gwh = sum(ρ[o] * Sb * pk[k, t, o] for k in K, o in O) * gwh
        
        # 4. Net Storage Supply (Discharge minus Charge)
        exist_sto_net_gwh = sum(ρ[o] * Sb * (pdis[s, t, o] - pch[s, t, o]) for s in S, o in O) * gwh
        cand_sto_net_gwh = sum(ρ[o] * Sb * (pdisk[s, t, o] - pchk[s, t, o]) for s in Sk, o in O) * gwh
        
        # 5. Totals and Balance
        total_supply_gwh = exist_gen_gwh + cand_gen_gwh + exist_sto_net_gwh + cand_sto_net_gwh
        
        # The balance gap should be extremely close to 0.0 (accounting for load shedding)
        balance_gap_gwh = (total_supply_gwh + shed_gwh) - demand_gwh

        push!(results, (;
            year = t,
            demand_gwh = demand_gwh,
            load_shed_gwh = shed_gwh,
            existing_gen_gwh = exist_gen_gwh,
            candidate_gen_gwh = cand_gen_gwh,
            existing_sto_net_gwh = exist_sto_net_gwh,
            candidate_sto_net_gwh = cand_sto_net_gwh,
            total_supply_gwh = total_supply_gwh,
            balance_gap_gwh = balance_gap_gwh
        ))
    end
    
    return DataFrame(results)
end

function save_results(model, cfg::TEPConfig, sets, params, out_dir::String)
    mkpath(out_dir)
    mkpath(joinpath(out_dir, "csv"))
    # Core outputs used for post-analysis
    CSV.write(joinpath(out_dir, "csv", "cap_gen_inv.csv"), capacity_inv_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "cap_storage_inv.csv"), storage_inv_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "gen_dispatch.csv"), gen_dispatch_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "load_shedding.csv"), load_shedding_df(model, sets, params))

    if cfg.include_network
        CSV.write(joinpath(out_dir, "csv", "line_inv.csv"), line_inv_df(model, cfg, sets, params))
        CSV.write(joinpath(out_dir, "csv", "line_flows.csv"), line_flow_df(model, cfg, sets, params))
    end

    costs = cost_breakdown(model, cfg, sets, params)
    CSV.write(joinpath(out_dir, "csv", "cost_summary.csv"), costs.summary)
    CSV.write(joinpath(out_dir, "csv", "op_costs.csv"), costs.operating)
    CSV.write(joinpath(out_dir, "csv", "inv_costs.csv"), costs.investment)
    CSV.write(joinpath(out_dir, "csv", "fixed_costs.csv"), costs.fixed)
    CSV.write(joinpath(out_dir, "csv", "carbon_costs.csv"), costs.carbon)

    println("\n✓ Results saved to: $out_dir")
end

function summarize_results(model, cfg::TEPConfig, sets, params; save_to::Union{String,Nothing}=nothing)
    println("\n" * "="^50)
    println("             TEGP - RESULTS SUMMARY")
    println("="^50)

    # Physics view: annual demand and supply split
    yearly = yearly_supply_demand(model, sets, params)
    fmt2(x) = Printf.@sprintf("%.2f", x)
    fmtc(x) = replace(fmt2(x), r"(?<=\d)(?=(\d{3})+\.)" => ",")
    fmtcol(x, w=12) = lpad(fmtc(x), w)
    println("\n⚡ DEMAND AND GENERATION BY YEAR")
    println("="^50)
    println("Y  | Demand (GWh) | Ex gen (GWh) | Ca gen (GWh) | Total (GWh)  | Gap (GWh)")
    for row in eachrow(yearly)
        println("$(row.year)  | $(fmtcol(row.demand_gwh)) | $(fmtcol(row.existing_gen_gwh)) | $(fmtcol(row.candidate_gen_gwh)) | $(fmtcol(row.total_supply_gwh)) | $(fmtcol(row.balance_gap_gwh))")
    end

    costs = cost_breakdown(model, cfg, sets, params)
    println("\n📊 COST BREAKDOWN")
    println("="^50)
    for row in eachrow(costs.summary)
        println("  $(rpad(row.category, 20)): \$$(round(row.value, digits=2))")
    end

    cap = capacity_inv_df(model, sets, params)
    built_cap = filter(row -> row.capacity_added_mw > 0.01, cap)
    if nrow(built_cap) > 0
        println("\n⚡ GENERATION CAPACITY INVESTMENTS")
        println("="^50)
        if nrow(built_cap) <= 10
            for row in eachrow(built_cap)
                println("  Year $(row.year), Gen $(row.gen_id): $(round(row.capacity_added_mw, digits=2)) MW (\$$(round(row.annual_investment_cost, digits=2)))")
            end
        else
            println("  $(nrow(built_cap)) build decisions found. Showing yearly summary:")
            yearly_cap = combine(
                groupby(built_cap, :year),
                :gen_id => length => :units_built,
                :capacity_added_mw => sum => :added_mw,
                :annual_investment_cost => sum => :new_investment_cost
            )
            sort!(yearly_cap, :year)
            for row in eachrow(yearly_cap)
                println("  Year $(row.year): $(row.units_built) builds, $(round(row.added_mw, digits=2)) MW added, new investment \$$(round(row.new_investment_cost, digits=2))")
            end
        end
    end

    storage = storage_inv_df(model, sets, params)
    built_storage = filter(row -> row.energy_added_mwh > 0.01, storage)
    if nrow(built_storage) > 0
        println("\n🔋 STORAGE CAPACITY INVESTMENTS")
        println("="^50)
        if nrow(built_storage) <= 10
            for row in eachrow(built_storage)
                println("  Year $(row.year), Storage $(row.storage_id): $(round(row.energy_added_mwh, digits=2)) MWh (\$$(round(row.annual_investment_cost, digits=2)))")
            end
        else
            println("  $(nrow(built_storage)) build decisions found. Showing yearly summary:")
            yearly_storage = combine(
                groupby(built_storage, :year),
                :storage_id => length => :units_built,
                :energy_added_mwh => sum => :added_mwh,
                :annual_investment_cost => sum => :new_investment_cost
            )
            sort!(yearly_storage, :year)
            for row in eachrow(yearly_storage)
                println("  Year $(row.year): $(row.units_built) builds, $(round(row.added_mwh, digits=2)) MWh added, new investment \$$(round(row.new_investment_cost, digits=2))")
            end
        end
    end

    if cfg.include_network
        line = line_inv_df(model, cfg, sets, params)
        built_lines = filter(row -> row.built, line)
        if nrow(built_lines) > 0
            println("\n🔌 TRANSMISSION LINE INVESTMENTS")
            println("="^50)
            for row in eachrow(built_lines)
                println("  Year $(row.year), Line $(row.line_id): Built (\$$(round(row.annual_investment_cost, digits=2)))")
            end
        else
            println("\n🔌 TRANSMISSION LINE INVESTMENTS")
            println("="^50)
            println("  None")
        end
    end

    !isnothing(save_to) && save_results(model, cfg, sets, params, save_to)
end

function plot_cap_dem(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    
    # Safely pull the base directly from the parsed parameters
    Sb = params[:Sbase]
    yrs = collect(T)

    # Performance optimization: extract all candidate capacities at once
    pkmax_vals = value.(model[:pkmax])

    # Calculate Existing and Candidate Capacities (with safe initializers)
    ex_cap = fill(sum(params[:Pgmax][g] for g in G; init=0.0) * Sb, length(yrs))
    add_yr = [sum(pkmax_vals[k, t] for k in K; init=0.0) * Sb for t in yrs]
    cand_cap = cumsum(add_yr)

    # Calculate Peak Demand using the geographic tuple index: Pdf[(d, o)]
    peak_dem = [
        maximum(sum(params[:Pd][d] * params[:Pdf][(d, o)] * params[:Pdg][t] for d in D; init=0.0) * Sb for o in O) 
        for t in yrs
    ]

    # Plotting Architecture
    p = areaplot(
        yrs, [ex_cap cand_cap],
        seriestype=:bar,
        label=["Ex Cap" "Cand Cap"],
        color=[PLOT_COLORS.gray PLOT_COLORS.purple],
        lw=0, yformatter=:plain,
        xlabel="Years", ylabel="Cap (MW)", 
        # Bulletproof y-axis scaling
        ylims=(0, max(maximum(ex_cap) + maximum(cand_cap), maximum(peak_dem; init=0.0)) * 1.5)
    )

    plot!(
        p, yrs, peak_dem,
        lw=3, marker=:circle, color=PLOT_COLORS.green, label="Peak Dem"
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end

function plot_cap_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    # 1. Bring in the Candidate Storage Set (Sk)
    K, Sk, T = sets[:K], sets[:Sk], sets[:T]
    Sb = params[:Sbase] # Use centralized Sbase
    yrs = collect(T)

    ptype = get(params, :Pktype, Dict())
    ktyp(k) = lowercase(strip(string(get(ptype, k, "other"))))
    
    typs = sort(unique(ktyp.(K)))
    isempty(typs) && (typs = ["none"])

    # Performance Optimization: Extract values once
    pkmax_vals = value.(model[:pkmax])
    ekmax_vals = value.(model[:ekmax])

    # 2. Base Generator Matrix
    cap_mat = [
        sum((pkmax_vals[k, t] for k in K if ktyp(k) == typ); init=0.0) * Sb / 1000.0 
        for t in yrs, typ in typs
    ]

    # 3. Storage Discharge Matrix
    sto_mat = [
        sum((ekmax_vals[s, t] / 4.0 for s in Sk); init=0.0) * Sb / 1000.0
        for t in yrs
    ]

    # 4. Combine Matrices and Labels
    full_mat = hcat(cap_mat, sto_mat)
    
    stack_labels = [t == "none" ? "N/A" : t for t in typs]
    push!(stack_labels, "storage_discharge")
    lbls = permutedims(stack_labels)

    # Calculate safe upper bound for plotting
    y_max = isempty(full_mat) ? 1.0 : maximum(sum(full_mat, dims=2); init=0.0) * 1.5

    p = areaplot(
        yrs, full_mat,
        seriestype=:bar,
        label=lbls,
        lw=0, yformatter=:plain,
        legend=:outertop, 
        xlabel="Years", ylabel="New Cap (GW)", 
        ylims=(0, y_max) 
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
    
end

function plot_total_cap_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    # 1. Bring in Storage Sets
    G, K, S, Sk, T = sets[:G], sets[:K], sets[:S], sets[:Sk], sets[:T]
    Sb = params[:Sbase]
    yrs = collect(T)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])

    # Performance Optimization: Extract values once
    pkmax_vals = value.(model[:pkmax])
    ekmax_vals = value.(model[:ekmax]) # Grab Energy instead of Discharge Power

    # 2. Base Generator Matrices
    ex_cap = [
        sum((params[:Pgmax][g] for g in G if gtyp(g) == typ); init=0.0) * Sb / 1000.0 
        for typ in typs
    ]
    
    new_cap = [
        sum((pkmax_vals[k, t] for k in K if ktyp(k) == typ); init=0.0) * Sb / 1000.0 
        for t in yrs, typ in typs
    ]
    
    gen_mat = permutedims(ex_cap) .+ cumsum(new_cap, dims=1)

    # 3. Storage Power Estimation (Energy / 4 hours)
    # Estimate existing storage power
    ex_sto_cap = sum((params[:Emax][s] / 4.0 for s in S); init=0.0) * Sb / 1000.0
    
    # Estimate candidate storage power
    new_sto_cap = [
        sum((ekmax_vals[s, t] / 4.0 for s in Sk); init=0.0) * Sb / 1000.0
        for t in yrs
    ]
    
    sto_mat = ex_sto_cap .+ cumsum(new_sto_cap)

    # 4. Combine Matrices and Labels
    full_mat = hcat(gen_mat, sto_mat)
    
    stack_labels = [t == "none" ? "N/A" : t for t in typs]
    push!(stack_labels, "Storage") # Updated label for clarity
    lbls = permutedims(stack_labels)

    # Safe y-axis scaling limit
    y_max = isempty(full_mat) ? 1.0 : maximum(sum(full_mat, dims=2); init=0.0) * 1.2

    p = areaplot(
        yrs, full_mat,
        seriestype=:bar,
        label=lbls,
        lw=0, yformatter=:plain,
        legend=:outertop,
        legendcolumns=4,
        xlabel="Year", ylabel="Total Capacity (GW)",
        ylims=(0, max(y_max, 1.0))
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end

end

function plot_hourly_dispatch(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    G, K, D, S, Sk, T, O = sets[:G], sets[:K], sets[:D], sets[:S], sets[:Sk], sets[:T], sets[:O]
    Sb = params[:Sbase] # Use centralized Sbase
    hrs = collect(O)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])
    pdf, pdg = params[:Pdf], params[:Pdg]
    
    stack_labels = [typ == "none" ? "N/A" : typ for typ in typs]
    push!(stack_labels, "Storage Discharge")
    push!(stack_labels, "Storage Charge")
    push!(stack_labels, "Load Shed")
    lbls = permutedims(stack_labels)

    # Group generators once by type
    g_by_typ = Dict(typ => [g for g in G if gtyp(g) == typ] for typ in typs)
    k_by_typ = Dict(typ => [k for k in K if ktyp(k) == typ] for typ in typs)

    # Hourly demand profile: Fixed tuple indexing pdf[(d, o)]
    demand_base = [sum(params[:Pd][d] * pdf[(d, o)] for d in D; init=0.0) * Sb for o in hrs]

    plots = Dict{Any, Any}()
    demand_max = maximum(demand_base; init=0.0) * maximum(values(pdg); init=1.0)

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
    end

    # Performance Optimization: Extract solver values once before looping
    pg_val = value.(model[:pg])
    pk_val = value.(model[:pk])
    pdis_val = value.(model[:pdis])
    pdisk_val = value.(model[:pdisk])
    pch_val = value.(model[:pch])
    pchk_val = value.(model[:pchk])
    ls_val = value.(model[:ls])

    for t in T
        disp_core = [
            (
                sum((pg_val[g, t, o] for g in g_by_typ[typ]); init=0.0) +
                sum((pk_val[k, t, o] for k in k_by_typ[typ]); init=0.0)
            ) * Sb
            for o in hrs, typ in typs
        ]

        dem = [demand_base[i] * pdg[t] for i in eachindex(hrs)]
        
        dis_sto = [
            (
                sum((pdis_val[s, t, o] for s in S); init=0.0) +
                sum((pdisk_val[s, t, o] for s in Sk); init=0.0)
            ) * Sb
            for o in hrs
        ]
        
        ch_sto = [
            -(
                sum((pch_val[s, t, o] for s in S); init=0.0) +
                sum((pchk_val[s, t, o] for s in Sk); init=0.0)
            ) * Sb
            for o in hrs
        ]
        
        shed = [sum(ls_val[d, t, o] for d in D; init=0.0) * Sb for o in hrs]
        
        disp_mat = hcat(disp_core, dis_sto, ch_sto, shed)

        # Include negative charging in axis limits so storage operation is visible.
        pos_stack = [sum(max(v, 0.0) for v in disp_mat[i, :]) for i in eachindex(hrs)]
        neg_stack = [sum(min(v, 0.0) for v in disp_mat[i, :]) for i in eachindex(hrs)]
        y_max = max(maximum(pos_stack; init=0.0), maximum(dem; init=0.0), demand_max) * 1.2
        y_min = min(minimum(neg_stack; init=0.0) * 1.2, 0.0)

        p = areaplot(
            hrs, disp_mat,
            label=lbls,
            legend=:outertop, lw=0,
            legendcolumns=4,
            xlabel="Hour", ylabel="Dispatch (MW)", yformatter=:plain,
            ylims=(y_min, y_max)
        )

        plot!(
            p, hrs, dem,
            lw=2, color=PLOT_COLORS.black, label="Demand"
        )

        if !isnothing(pdf_path)
            base, ext = splitext(pdf_path)
            out_path = isempty(ext) ? "$(pdf_path)_t$(t).pdf" : "$(base)_t$(t)$(ext)"
            savefig(p, out_path)
            println("✓ Saved: $out_path")
        end

        plots[t] = p
    end
    
end

function plot_emissions_by_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    haskey(model, :em_e) || return nothing
    
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    ρ = params[:ρ]
    yrs = collect(T)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])
    
    em_e, em_k = model[:em_e], model[:em_k]

    # Yearly emissions by type: sum across hours weighted by representative hour weight ρ
    em_mat = [
        sum((ρ[o] * value(em_e[g, t, o]) for g in G if gtyp(g) == typ for o in O); init=0.0) +
        sum((ρ[o] * value(em_k[k, t, o]) for k in K if ktyp(k) == typ for o in O); init=0.0)
        for t in yrs, typ in typs
    ]

    lbls = permutedims([t == "none" ? "N/A" : t for t in typs])

    p = areaplot(
        yrs, em_mat / 1e6,  # Convert to MtCO2
        seriestype=:bar,
        label=lbls,
        lw=0, yformatter=:plain,
        legend=:outertop,
        legendcolumns=4,
        xlabel="Year", ylabel="Emissions (MtCO2)",
        ylims=(0, maximum(sum(em_mat, dims=2); init=0.0) / 1e6 * 1.2)
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end

function save_plots(model, cfg::TEPConfig, sets, params, dir::String)
    println("\nSaving plots...")
    pdir = joinpath(dir, "plots")
    mkpath(pdir)
    
    plot_cap_dem(model, cfg, sets, params; pdf_path=joinpath(pdir, "cap_dem.pdf"))
    plot_cap_type(model, cfg, sets, params; pdf_path=joinpath(pdir, "cap_type.pdf"))
    plot_total_cap_type(model, cfg, sets, params; pdf_path=joinpath(pdir, "total_cap_type.pdf"))
    plot_emissions_by_type(model, cfg, sets, params; pdf_path=joinpath(pdir, "emissions_by_type.pdf"))
    plot_hourly_dispatch(model, cfg, sets, params; pdf_path=joinpath(pdir, "hourly_dispatch.pdf"))
end

function report_solution(model, cfg::TEPConfig, sets, params)
    G, K, Sk, L, E, T, O = sets[:G], sets[:K], sets[:Sk], sets[:L], sets[:E], sets[:T], sets[:O]
    pg, pk, pkmax, ekmax, β = model[:pg], model[:pk], model[:pkmax], model[:ekmax], model[:β]
    t, o = last(T), first(O)

    println("")
    println("Generation dispatch (t=$t, o=$o):")
    for g in G
        println("  Gen $g: ", round(value(pg[g, t, o]), digits=2), " MW")
    end

    println("Candidate generation (t=$t):")
    for k in K
        cap = round(value(sum(pkmax[k, τ] for τ in 1:t)), digits=2)
        disp = round(value(pk[k, t, o]), digits=2)
        println("  Cand Gen $k: $disp MW (Capacity: $cap MW)")
    end

    println("Candidate storage (t=$t):")
    for s in Sk
        ecap = round(value(sum(ekmax[s, τ] for τ in 1:t)), digits=2)
        println("  Cand Storage $s: Capacity: $ecap MWh")
    end

    if cfg.include_network
        f, fl = model[:f], model[:fl]
        println("Line investments (t=$t):")
        for l in L
            built = value(sum(β[l, τ] for τ in 1:t)) > 0.5
            println("  Line $l: ", built ? "Built" : "Not built")
        end
        println("Line flows (t=$t, o=$o):")
        for e in E
            println("  Existing Line $e: ", round(value(f[e, t, o]), digits=2), " MW")
        end
        for l in L
            println("  Candidate Line $l: ", round(value(fl[l, t, o]), digits=2), " MW")
        end
    end
end
