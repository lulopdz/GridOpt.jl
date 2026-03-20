using Printf
using Plots
using DataFrames, CSV

include("../utils/plot_defaults.jl")
set_theme()

function capacity_inv_df(model, cfg::TEPConfig, sets, params)
    K, T = sets[:K], sets[:T]
    pkmax, pkinv = model[:pkmax], params[:Pkinv]
    Sb = cfg.per_unit ? 100.0 : 1.0
    df = DataFrame([(; gen_id=k, year=t, capacity_added_mw= Sb * value(pkmax[k, t])) for k in K, t in T][:])
    
    sort!(df, [:gen_id, :year])
    transform!(groupby(df, :gen_id), :capacity_added_mw => cumsum => :cumulative_capacity_mw)
    # Annual payment stream: once built, capacity keeps incurring investment cost in later years.
    df.annual_investment_cost = df.capacity_added_mw .* [pkinv[k] for k in df.gen_id]
    df.investment_cost = df.cumulative_capacity_mw .* [pkinv[k] for k in df.gen_id]
    
    return df
end

function line_inv_df(model, cfg::TEPConfig, sets, params)
    cfg.include_network || return DataFrame()
    L, T = sets[:L], sets[:T]
    β, flinv = model[:β], params[:Flinv]
    Fmaxl = params[:Fmaxl]
    
    df = DataFrame([(; line_id=l, year=t, built=(value(β[l, t]) > 0.5)) for l in L, t in T][:])
    sort!(df, [:line_id, :year])
    transform!(groupby(df, :line_id), :built => (x -> cumsum(Int.(x)) .> 0) => :active)
    df.annual_investment_cost = [b ? flinv[l] * Fmaxl[l] : 0.0 for (b, l) in zip(df.built, df.line_id)]
    df.investment_cost = [a ? flinv[l] * Fmaxl[l] : 0.0 for (a, l) in zip(df.active, df.line_id)]
    
    return df
end

function gen_dispatch_df(model, cfg::TEPConfig, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    pg, pk = model[:pg], model[:pk]
    Sb = cfg.per_unit ? 100.0 : 1.0
    
    existing  = DataFrame([(; type="existing", id=g, year=t, hour=o, dispatch_mw=value(pg[g, t, o])) for g in G, t in T, o in O][:])
    candidate = DataFrame([(; type="candidate", id=k, year=t, hour=o, dispatch_mw=value(pk[k, t, o])) for k in K, t in T, o in O][:])
    
    return vcat(existing, candidate)
end

function line_flow_df(model, cfg::TEPConfig, sets, params, year=nothing, hour=nothing)
    cfg.include_network || return DataFrame()
    E, L, T, O = sets[:E], sets[:L], sets[:T], sets[:O]
    
    ts = isnothing(year) ? T : [year]
    os = isnothing(hour) ? O : [hour]
    
    existing  = DataFrame([(; type="existing", line_id=e, year=t, hour=o, flow_mw=value(model[:f][e, t, o])) for e in E, t in ts, o in os][:])
    candidate = DataFrame([(; type="candidate", line_id=l, year=t, hour=o, flow_mw=value(model[:fl][l, t, o])) for l in L, t in ts, o in os][:])
    
    return vcat(existing, candidate)
end

function load_shedding_df(model, cfg::TEPConfig, sets, params)
    haskey(model, :ls) || return DataFrame(load_id=Int[], year=Int[], hour=Int[], shed_mw=Float64[], demand_mw=Float64[], shed_pct=Float64[], weighted_shed_mwh=Float64[])
    
    D, T, O = sets[:D], sets[:T], sets[:O]
    Pd, Pdf, Pdg = params[:Pd], params[:Pdf], params[:Pdg]
    ρ = get(params, :ρ, Dict(o => 1.0 for o in O))
    ls = model[:ls]

    df = DataFrame([(; 
        load_id = d, year = t, hour = o, 
        shed_mw = value(ls[d, t, o]),
        demand_mw = Pd[d] * Pdf[o] * Pdg[t]
    ) for d in D, t in T, o in O][:])
    
    df.shed_pct = ifelse.(df.demand_mw .> 0, 100.0 .* df.shed_mw ./ df.demand_mw, 0.0)
    df.weighted_shed_mwh = [ρ[o] for o in df.hour] .* df.shed_mw
    
    return df
end

function cost_breakdown(model, cfg::TEPConfig, sets, params)
    G, K, L, T, O = sets[:G], sets[:K], sets[:L], sets[:T], sets[:O]
    α, ρ = params[:α], params[:ρ]
    pgcost, pkcost, pkinv, flinv = params[:Pgcost], params[:Pkcost], params[:Pkinv], params[:Flinv]
    fmaxl = params[:Fmaxl]
    pgfixed, pkfixed = params[:Pgfixed], params[:Pkfixed]
    pgmax = params[:Pgmax]
    ctax = get(params, :Ctax, Dict(t => 0.0 for t in T))
    sb = cfg.per_unit ? 100.0 : 1.0
    has_em = haskey(model, :em)

    op = DataFrame([(; 
        year = t,
        existing_gen = sb * α[t] * sum(ρ[o] * pgcost[g] * value(model[:pg][g, t, o]) for g in G, o in O),
        candidate_gen = sb * α[t] * sum(ρ[o] * pkcost[k] * value(model[:pk][k, t, o]) for k in K, o in O),
        load_shed = sb * α[t] * sum(ρ[o] * params[:VoLL][d] * value(model[:ls][d, t, o]) for d in sets[:D], o in O)
    ) for t in T])
    op.total_op = op.existing_gen .+ op.candidate_gen .+ op.load_shed

    inv = DataFrame([(;
        year = t,
        gen_inv = sb * α[t] * sum(pkinv[k] * sum(value(model[:pkmax][k, τ]) for τ in 1:t) for k in K),
        line_inv = cfg.include_network ? sb * α[t] * sum(flinv[l] * fmaxl[l] * sum(value(model[:β][l, τ]) for τ in 1:t) for l in L) : 0.0
    ) for t in T])
    inv.total_inv = inv.gen_inv .+ inv.line_inv

    fixed = DataFrame([(; 
        year = t,
        existing_fixed = sb * α[t] * sum(pgfixed[g] * pgmax[g] for g in G),
        candidate_fixed = sb * α[t] * sum(pkfixed[k] * sum(value(model[:pkmax][k, τ]) for τ in 1:t) for k in K)
    ) for t in T])
    fixed.total_fixed = fixed.existing_fixed .+ fixed.candidate_fixed

    carbon = DataFrame([(; 
        year = t,
        carbon_cost = has_em ? α[t] * sum(ρ[o] * ctax[t] * value(model[:em][t, o]) for o in O) : 0.0
    ) for t in T])

    total_op, total_inv = sum(op.total_op), sum(inv.total_inv)
    total_fixed, total_carbon = sum(fixed.total_fixed), sum(carbon.carbon_cost)
    summary = DataFrame(
        category=["Operating Cost", "Investment Cost", "Fixed O&M Cost", "Carbon Cost", "Total Cost"],
        value=[total_op, total_inv, total_fixed, total_carbon, total_op + total_inv + total_fixed + total_carbon]
    )
    
    return (summary=summary, operating=op, investment=inv, fixed=fixed, carbon=carbon)
end

function yearly_supply_demand(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    ρ, pdf, pdg = params[:ρ], params[:Pdf], params[:Pdg]
    
    gwh = 1.0 / 1000.0
    df = DataFrame([(;
        year = t,
        demand_gwh = sum(ρ[o] * params[:Pd][d] * pdf[o] * pdg[t] for d in D, o in O) * gwh,
        existing_gen_gwh = sum(ρ[o] * value(model[:pg][g, t, o]) for g in G, o in O) * gwh,
        candidate_gen_gwh = sum(ρ[o] * value(model[:pk][k, t, o]) for k in K, o in O) * gwh
    ) for t in T])
    
    df.total_gen_gwh = df.existing_gen_gwh .+ df.candidate_gen_gwh
    df.balance_gap_gwh = df.total_gen_gwh .- df.demand_gwh
    return df
end

function save_results(model, cfg::TEPConfig, sets, params, out_dir::String)
    mkpath(out_dir)
    mkpath(joinpath(out_dir, "csv"))
    # Core outputs used for post-analysis
    CSV.write(joinpath(out_dir, "csv", "generation_dispatch.csv"), gen_dispatch_df(model, cfg, sets, params))
    CSV.write(joinpath(out_dir, "csv", "capacity_investments.csv"), capacity_inv_df(model, cfg, sets, params))
    CSV.write(joinpath(out_dir, "csv", "load_shedding.csv"), load_shedding_df(model, cfg, sets, params))

    if cfg.include_network
        CSV.write(joinpath(out_dir, "csv", "line_investments.csv"), line_inv_df(model, cfg, sets, params))
        CSV.write(joinpath(out_dir, "csv", "line_flows.csv"), line_flow_df(model, cfg, sets, params))
    end

    costs = cost_breakdown(model, cfg, sets, params)
    CSV.write(joinpath(out_dir, "csv", "cost_summary.csv"), costs.summary)
    CSV.write(joinpath(out_dir, "csv", "operating_costs.csv"), costs.operating)
    CSV.write(joinpath(out_dir, "csv", "investment_costs.csv"), costs.investment)
    CSV.write(joinpath(out_dir, "csv", "fixed_costs.csv"), costs.fixed)
    CSV.write(joinpath(out_dir, "csv", "carbon_costs.csv"), costs.carbon)

    println("\n✓ Results saved to: $out_dir")
end

function summarize_results(model, cfg::TEPConfig, sets, params; save_to::Union{String,Nothing}=nothing)
    Sb = cfg.per_unit ? 100.0 : 1.0

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
        println("$(row.year)  | $(fmtcol(row.demand_gwh)) | $(fmtcol(row.existing_gen_gwh)) | $(fmtcol(row.candidate_gen_gwh)) | $(fmtcol(row.total_gen_gwh)) | $(fmtcol(row.balance_gap_gwh))")
    end

    costs = cost_breakdown(model, cfg, sets, params)
    println("\n📊 COST BREAKDOWN")
    println("="^50)
    for row in eachrow(costs.summary)
        println("  $(rpad(row.category, 20)): \$$(round(row.value, digits=2))")
    end

    cap = capacity_inv_df(model, cfg, sets, params)
    built_cap = filter(row -> row.capacity_added_mw > 0.01, cap)
    if nrow(built_cap) > 0
        println("\n⚡ GENERATION CAPACITY INVESTMENTS")
        println("="^50)
        if nrow(built_cap) <= 10
            for row in eachrow(built_cap)
                println("  Year $(row.year), Gen $(row.gen_id): $(round(row.capacity_added_mw, digits=2)) MW (\$$(round(row.investment_cost, digits=2)))")
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

    if cfg.include_network
        line = line_inv_df(model, cfg, sets, params)
        built_lines = filter(row -> row.built, line)
        if nrow(built_lines) > 0
            println("\n🔌 TRANSMISSION LINE INVESTMENTS")
            println("="^50)
            for row in eachrow(built_lines)
                println("  Year $(row.year), Line $(row.line_id): Built (\$$(round(row.investment_cost, digits=2)))")
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
    Sb = cfg.per_unit ? 100.0 : 1.0
    yrs = collect(T)

    ex_cap = fill(sum(params[:Pgmax][g] for g in G) * Sb, length(yrs))
    add_yr = [sum(value(model[:pkmax][k, t]) for k in K; init=0.0) * Sb for t in yrs]
    cand_cap = cumsum(add_yr)

    peak_dem = [
        maximum(sum(params[:Pd][d] * params[:Pdf][o] * params[:Pdg][t] for d in D) * Sb for o in O) 
        for t in yrs
    ]

    p = areaplot(
        yrs, [ex_cap cand_cap],
        seriestype=:bar,
        label=["Ex Cap" "Cand Cap"],
        color=[PLOT_COLORS.gray PLOT_COLORS.purple],
        lw=0, yformatter=:plain,
        xlabel="Years", ylabel="Cap (MW)", 
        ylims=(0, (maximum(ex_cap) + maximum(cand_cap)) * 1.5)
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
    K, T = sets[:K], sets[:T]
    Sb = cfg.per_unit ? 100.0 : 1.0
    yrs = collect(T)

    ptype = get(params, :Pktype, Dict())
    ktyp(k) = lowercase(strip(string(get(ptype, k, "other"))))
    
    typs = sort(unique(ktyp.(K)))
    isempty(typs) && (typs = ["none"])

    cap_mat = [
        sum((value(model[:pkmax][k, t]) for k in K if ktyp(k) == typ); init=0.0) * Sb / 1000.0 
        for t in yrs, typ in typs
    ]

    lbls = permutedims([t == "none" ? "N/A" : t for t in typs])

    p = areaplot(
        yrs, cap_mat,
        seriestype=:bar,
        label=lbls,
        lw=0, yformatter=:plain,
        legend=:outertop, 
        xlabel="Years", ylabel="New Cap (GW)", 
        ylims=(0, maximum(sum(cap_mat, dims=2); init=0.0) * 1.5)
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end

function plot_total_cap_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    G, K, T = sets[:G], sets[:K], sets[:T]
    sb = cfg.per_unit ? 100.0 : 1.0
    yrs = collect(T)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])

    ex_cap = [
        sum((params[:Pgmax][g] for g in G if gtyp(g) == typ); init=0.0) * sb / 1000.0 
        for typ in typs
    ]
    
    new_cap = [
        sum((value(model[:pkmax][k, t]) for k in K if ktyp(k) == typ); init=0.0) * sb / 1000.0 
        for t in yrs, typ in typs
    ]
    
    cap_mat = permutedims(ex_cap) .+ cumsum(new_cap, dims=1)

    lbls = permutedims([t == "none" ? "N/A" : t for t in typs])

    p = areaplot(
        yrs, cap_mat,
        seriestype=:bar,
        label=lbls,
        lw=0, yformatter=:plain,
        legend=:outertop,
        legendcolumns=4,
        xlabel="Year", ylabel="Total Capacity (GW)",
        ylims=(0, maximum(sum(cap_mat, dims=2); init=0.0) * 1.2)
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end

function plot_hourly_dispatch(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    sb = cfg.per_unit ? 100.0 : 1.0
    hrs = collect(O)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])
    pdf, pdg = params[:Pdf], params[:Pdg]
    stack_labels = [typ == "none" ? "N/A" : typ for typ in typs]
    push!(stack_labels, "Load Shed")
    lbls = permutedims(stack_labels)

    # Group generators once by type to avoid repeated filtering in hourly loops.
    g_by_typ = Dict(typ => [g for g in G if gtyp(g) == typ] for typ in typs)
    k_by_typ = Dict(typ => [k for k in K if ktyp(k) == typ] for typ in typs)

    # Hourly demand profile (without yearly growth) is reused for every year.
    demand_base = [sum(params[:Pd][d] * pdf[o] for d in D; init=0.0) * sb for o in hrs]

    plots = Dict{Any, Any}()
    y_max = maximum(demand_base; init=0.0) * maximum(values(pdg); init=1.0) * 1.2

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
    end

    for t in T
        disp_core = [
            (
                sum((value(model[:pg][g, t, o]) for g in g_by_typ[typ]); init=0.0) +
                sum((value(model[:pk][k, t, o]) for k in k_by_typ[typ]); init=0.0)
            ) * sb
            for o in hrs, typ in typs
        ]

        dem = [demand_base[i] * pdg[t] for i in eachindex(hrs)]
        shed = [sum(value(model[:ls][d, t, o]) for d in D; init=0.0) * sb for o in hrs]
        disp_mat = hcat(disp_core, shed)

        p = areaplot(
            hrs, disp_mat,
            label=lbls,
            legend=:outertop, lw=0,
            legendcolumns=4,
            xlabel="Hour", ylabel="Dispatch (MW)", yformatter=:plain,
            ylims=(0, y_max)
        )

        plot!(
            p, hrs, dem,
            lw=2, color=PLOT_COLORS.black, label="Demand"
        )

        if !isnothing(pdf_path)
            mkpath(dirname(pdf_path))
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
    G, K, L, E, T, O = sets[:G], sets[:K], sets[:L], sets[:E], sets[:T], sets[:O]
    pg, pk, pkmax, β = model[:pg], model[:pk], model[:pkmax], model[:β]
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
