using Printf
using Plots

include("../utils/plot_defaults.jl")
set_theme()

function gen_dispatch_df(model, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    pg, pk = model[:pg], model[:pk]
    df = DataFrame(type=String[], id=Int[], year=Int[], hour=Int[], dispatch_mw=Float64[])
    for g in G, t in T, o in O
        push!(df, ("existing", g, t, o, value(pg[g, t, o])))
    end
    for k in K, t in T, o in O
        push!(df, ("candidate", k, t, o, value(pk[k, t, o])))
    end
    df
end

function capacity_inv_df(model, sets, params)
    K, T = sets[:K], sets[:T]
    pkmax, pkinv = model[:pkmax], params[:Pkinv]
    df = DataFrame(gen_id=Int[], year=Int[], capacity_added_mw=Float64[], cumulative_capacity_mw=Float64[], investment_cost=Float64[])
    for k in K
        cum = 0.0
        for t in T
            add = value(pkmax[k, t])
            cum += add
            push!(df, (k, t, add, cum, add * pkinv[k]))
        end
    end
    df
end

function line_inv_df(model, cfg::TEPConfig, sets, params)
    cfg.include_network || return DataFrame()
    L, T = sets[:L], sets[:T]
    β, flinv = model[:β], params[:Flinv]
    df = DataFrame(line_id=Int[], year=Int[], built=Bool[], investment_cost=Float64[])
    for l in L, t in T
        built = value(β[l, t]) > 0.5
        push!(df, (l, t, built, built ? flinv[l] : 0.0))
    end
    df
end

function line_flow_df(model, cfg::TEPConfig, sets, params, year=nothing, hour=nothing)
    cfg.include_network || return DataFrame()
    E, L, T, O = sets[:E], sets[:L], sets[:T], sets[:O]
    f, fl = model[:f], model[:fl]
    ts = isnothing(year) ? T : [year]
    os = isnothing(hour) ? O : [hour]
    df = DataFrame(type=String[], line_id=Int[], year=Int[], hour=Int[], flow_mw=Float64[])
    for e in E, t in ts, o in os
        push!(df, ("existing", e, t, o, value(f[e, t, o])))
    end
    for l in L, t in ts, o in os
        push!(df, ("candidate", l, t, o, value(fl[l, t, o])))
    end
    df
end

function cost_breakdown(model, cfg::TEPConfig, sets, params)
    G, K, L, T, O = sets[:G], sets[:K], sets[:L], sets[:T], sets[:O]
    α, ρ = params[:α], params[:ρ]
    pg, pk, pkmax, β = model[:pg], model[:pk], model[:pkmax], model[:β]
    pgcost, pkcost, pkinv, flinv = params[:Pgcost], params[:Pkcost], params[:Pkinv], params[:Flinv]

    op = DataFrame(year=Int[], existing_gen=Float64[], candidate_gen=Float64[], total_op=Float64[])
    for t in T
        existing = α[t] * sum(ρ[o] * sum(pgcost[g] * value(pg[g, t, o]) for g in G) for o in O)
        candidate = α[t] * sum(ρ[o] * sum(pkcost[k] * value(pk[k, t, o]) for k in K) for o in O)
        push!(op, (t, existing, candidate, existing + candidate))
    end

    inv = DataFrame(year=Int[], gen_inv=Float64[], line_inv=Float64[], total_inv=Float64[])
    for t in T
        gen_cost = α[t] * sum(pkinv[k] * value(pkmax[k, t]) for k in K)
        line_cost = cfg.include_network ? α[t] * sum(flinv[l] * value(β[l, t]) for l in L) : 0.0
        push!(inv, (t, gen_cost, line_cost, gen_cost + line_cost))
    end

    total_op = sum(op.total_op)
    total_inv = sum(inv.total_inv)
    summary = DataFrame(category=["Operating Cost", "Investment Cost", "Total Cost"], value=[total_op, total_inv, total_op + total_inv])
    (summary=summary, operating=op, investment=inv)
end

function yearly_supply_demand(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    ρ, pdf, pdg = params[:ρ], params[:Pdf], params[:Pdg]
    pg, pk, pd = model[:pg], model[:pk], params[:Pd]
    gwh = 1.0 / 1000.0
    df = DataFrame(year=Int[], demand_gwh=Float64[], existing_gen_gwh=Float64[], candidate_gen_gwh=Float64[], total_gen_gwh=Float64[], balance_gap_gwh=Float64[])
    for t in T
        demand = sum(ρ[o] * sum(pd[d] * pdf[o] * pdg[t] for d in D) for o in O)
        existing = sum(ρ[o] * sum(value(pg[g, t, o]) for g in G) for o in O)
        candidate = sum(ρ[o] * sum(value(pk[k, t, o]) for k in K) for o in O)
        total = existing + candidate
        push!(df, (t, demand * gwh, existing * gwh, candidate * gwh, total * gwh, (total - demand) * gwh))
    end
    df
end

function load_shedding_df(model, sets, params)
    D, T, O = sets[:D], sets[:T], sets[:O]
    Pd, Pdf, Pdg = params[:Pd], params[:Pdf], params[:Pdg]
    ρ = get(params, :ρ, Dict(o => 1.0 for o in O))

    ls = try
        model[:ls]
    catch
        return DataFrame(load_id=Int[], year=Int[], hour=Int[], shed_mw=Float64[], demand_mw=Float64[], shed_pct=Float64[], weighted_shed_mwh=Float64[])
    end

    df = DataFrame(load_id=Int[], year=Int[], hour=Int[], shed_mw=Float64[], demand_mw=Float64[], shed_pct=Float64[], weighted_shed_mwh=Float64[])
    for d in D, t in T, o in O
        demand = Pd[d] * Pdf[o] * Pdg[t]
        shed = value(ls[d, t, o])
        shed_pct = demand > 0 ? 100.0 * shed / demand : 0.0
        push!(df, (d, t, o, shed, demand, shed_pct, ρ[o] * shed))
    end
    df
end

function plot_capacity_and_demand(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    pd, pgmax = params[:Pd], params[:Pgmax]
    pdf, pdg = params[:Pdf], params[:Pdg]
    pkmax = model[:pkmax]
    sb = cfg.per_unit ? 100.0 : 1.0

    years = collect(T)
    existing_cap_mw = [sum(pgmax[g] for g in G) * sb for _ in years]
    candidate_cap_mw = [sum(value(pkmax[k, τ]) for k in K for τ in years if τ <= t) * sb for t in years]
    peak_demand_mw = [maximum((sum(pd[d] * pdf[o] * pdg[t] for d in D) * sb for o in O); init=0.0) for t in years]

    combined = areaplot(
        years,
        seriestype=:bar,
        [existing_cap_mw candidate_cap_mw],
        label=["Existing Capacity" "Candidate Capacity"],
        color=[PLOT_COLORS.gray PLOT_COLORS.purple],
        xlabel="Years",
        ylabel="Capacity (MW)",
        yformatter=:plain,
        lw = 0.0,
        ylims=(0, maximum(existing_cap_mw) + maximum(candidate_cap_mw) * 1.2)
    )

    plot!(
        combined,
        years,
        peak_demand_mw,
        seriestype=:line,
        linewidth=3,
        marker=:circle,
        color=PLOT_COLORS.green,
        label="Peak Demand"
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(combined, pdf_path)
        println("✓ Plot saved to: $pdf_path")
    end

    return combined
end

function plot_new_capacity_by_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    K, T = sets[:K], sets[:T]
    pktype = get(params, :Pktype, Dict{Any, Any}())
    pkmax = model[:pkmax]
    sb = cfg.per_unit ? 100.0 : 1.0

    norm_type(x) = lowercase(strip(string(x)))
    k_type(k) = norm_type(get(pktype, k, "other"))

    years = collect(T)
    types = sort(unique([k_type(k) for k in K]))
    if isempty(types)
        types = ["none"]
    end

    cap_by_type = Dict(
        typ => [sum(value(pkmax[k, t]) for k in K if k_type(k) == typ) * sb / 1000.0 for t in years]
        for typ in types
    )
    cap_matrix = hcat([cap_by_type[typ] for typ in types]...)
    cap_labels = [typ == "none" ? "No Type" : typ for typ in types]

    p = areaplot(
        years,
        cap_matrix,
        xlabel="Year",
        ylabel="New Capacity (GW)",
        label=permutedims(cap_labels),
        legend = :outertop,
        seriestype = :bar,
        yformatter=:plain,
        lw = 0.0,
        ylims=(0, maximum(sum(cap_matrix, dims=2)) * 1.5)
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Plot saved to: $pdf_path")
    end

    return p
end

function save_plots(model, cfg::TEPConfig, sets, params, out_dir::String)
    mkpath(out_dir * "/plots")
    plot_capacity_and_demand(model, cfg, sets, params; pdf_path=joinpath(out_dir, "plots", "capacity_and_demand.pdf"))
    plot_new_capacity_by_type(model, cfg, sets, params; pdf_path=joinpath(out_dir, "plots", "new_capacity_by_type.pdf"))
end

function save_results(model, cfg::TEPConfig, sets, params, out_dir::String)
    mkpath(out_dir)
    mkpath(joinpath(out_dir, "csv"))
    # Core outputs used for post-analysis
    CSV.write(joinpath(out_dir, "csv", "generation_dispatch.csv"), gen_dispatch_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "capacity_investments.csv"), capacity_inv_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "load_shedding.csv"), load_shedding_df(model, sets, params))

    if cfg.include_network
        CSV.write(joinpath(out_dir, "csv", "line_investments.csv"), line_inv_df(model, cfg, sets, params))
        CSV.write(joinpath(out_dir, "csv", "line_flows.csv"), line_flow_df(model, cfg, sets, params))
    end

    costs = cost_breakdown(model, cfg, sets, params)
    CSV.write(joinpath(out_dir, "csv", "cost_summary.csv"), costs.summary)
    CSV.write(joinpath(out_dir, "csv", "operating_costs.csv"), costs.operating)
    CSV.write(joinpath(out_dir, "csv", "investment_costs.csv"), costs.investment)

    save_plots(model, cfg, sets, params, out_dir)

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
        println("$(row.year)  | $(fmtcol(row.demand_gwh)) | $(fmtcol(row.existing_gen_gwh)) | $(fmtcol(row.candidate_gen_gwh)) | $(fmtcol(row.total_gen_gwh)) | $(fmtcol(row.balance_gap_gwh))")
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
        for row in eachrow(built_cap)
            println("  Year $(row.year), Gen $(row.gen_id): $(round(row.capacity_added_mw, digits=2)) MW (\$$(round(row.investment_cost, digits=2)))")
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
            println("\n🔌 TRANSMISSION LINE INVESTMENTS: None")
        end
    end

    !isnothing(save_to) && save_results(model, cfg, sets, params, save_to)
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

