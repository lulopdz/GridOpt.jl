
# ==============================================================================
# Extract Results to DataFrames
function extract_generation_dispatch(model, sets, params)
    G, K, T, O = sets.G, sets.K, sets.T, sets.O
    pg, pk = model[:pg], model[:pk]
    
    results = DataFrame(
        type = String[],
        id = Int[],
        year = Int[],
        hour = Int[],
        dispatch_mw = Float64[]
    )
    
    for g in G, t in T, o in O
        push!(results, ("existing", g, t, o, value(pg[g, t, o])))
    end
    
    for k in K, t in T, o in O
        push!(results, ("candidate", k, t, o, value(pk[k, t, o])))
    end
    
    return results
end

function extract_capacity_investments(model, sets, params)
    K, T = sets.K, sets.T
    pkmax = model[:pkmax]
    Pkinv = params.Pkinv
    
    results = DataFrame(
        gen_id = Int[],
        year = Int[],
        capacity_added_mw = Float64[],
        cumulative_capacity_mw = Float64[],
        investment_cost = Float64[]
    )
    
    for k in K
        cum_cap = 0.0
        for t in T
            cap_added = value(pkmax[k, t])
            cum_cap += cap_added
            push!(results, (k, t, cap_added, cum_cap, cap_added * Pkinv[k]))
        end
    end
    
    return results
end

function extract_line_investments(model, config::TEPConfig, sets, params)
    if !config.include_network
        return DataFrame()
    end
    
    L, T = sets.L, sets.T
    β = model[:β]
    Flinv = params.Flinv
    
    results = DataFrame(
        line_id = Int[],
        year = Int[],
        built = Bool[],
        investment_cost = Float64[]
    )
    
    for l in L, t in T
        built = value(β[l, t]) > 0.5
        cost = built ? Flinv[l] : 0.0
        push!(results, (l, t, built, cost))
    end
    
    return results
end

function extract_line_flows(model, config::TEPConfig, sets, params, year=nothing, hour=nothing)
    if !config.include_network
        return DataFrame()
    end
    
    E, L, T, O = sets.E, sets.L, sets.T, sets.O
    f, fl = model[:f], model[:fl]
    
    # Use specific year/hour or defaults
    t_vals = isnothing(year) ? T : [year]
    o_vals = isnothing(hour) ? O : [hour]
    
    results = DataFrame(
        type = String[],
        line_id = Int[],
        year = Int[],
        hour = Int[],
        flow_mw = Float64[]
    )
    
    for e in E, t in t_vals, o in o_vals
        push!(results, ("existing", e, t, o, value(f[e, t, o])))
    end
    
    for l in L, t in t_vals, o in o_vals
        push!(results, ("candidate", l, t, o, value(fl[l, t, o])))
    end
    
    return results
end

function compute_cost_breakdown(model, config::TEPConfig, sets, params)
    G, K, L, T, O = sets.G, sets.K, sets.L, sets.T, sets.O
    α, ρ = sets.α, sets.ρ
    pg, pk, pkmax, β = model[:pg], model[:pk], model[:pkmax], model[:β]
    Pgcost, Pkcost, Pkinv, Flinv = params.Pgcost, params.Pkcost, params.Pkinv, params.Flinv
    
    # Operating costs by year
    op_costs = DataFrame(year = Int[], existing_gen = Float64[], candidate_gen = Float64[], total_op = Float64[])
    
    for t in T
        existing_cost = α[t] * sum(ρ[o] * sum(Pgcost[g] * value(pg[g, t, o]) for g in G) for o in O)
        candidate_cost = α[t] * sum(ρ[o] * sum(Pkcost[k] * value(pk[k, t, o]) for k in K) for o in O)
        push!(op_costs, (t, existing_cost, candidate_cost, existing_cost + candidate_cost))
    end
    
    # Investment costs by year
    inv_costs = DataFrame(year = Int[], gen_inv = Float64[], line_inv = Float64[], total_inv = Float64[])
    
    for t in T
        gen_cost = α[t] * sum(Pkinv[k] * value(pkmax[k, t]) for k in K)
        line_cost = config.include_network ? α[t] * sum(Flinv[l] * value(β[l, t]) for l in L) : 0.0
        push!(inv_costs, (t, gen_cost, line_cost, gen_cost + line_cost))
    end
    
    # Total summary
    total_op = sum(op_costs.total_op)
    total_inv = sum(inv_costs.total_inv)
    
    summary = DataFrame(
        category = ["Operating Cost", "Investment Cost", "Total Cost"],
        value = [total_op, total_inv, total_op + total_inv]
    )
    
    return (summary=summary, operating=op_costs, investment=inv_costs)
end

# ==============================================================================
# Save Results to Files
function save_tep_results(model, config::TEPConfig, sets, params, output_dir::String)
    # Create output directory if it doesn't exist
    mkpath(output_dir)
    
    # Extract and save all results
    gen_dispatch = extract_generation_dispatch(model, sets, params)
    CSV.write(joinpath(output_dir, "generation_dispatch.csv"), gen_dispatch)
    
    cap_inv = extract_capacity_investments(model, sets, params)
    CSV.write(joinpath(output_dir, "capacity_investments.csv"), cap_inv)
    
    if config.include_network
        line_inv = extract_line_investments(model, config, sets, params)
        CSV.write(joinpath(output_dir, "line_investments.csv"), line_inv)
        
        line_flows = extract_line_flows(model, config, sets, params)
        CSV.write(joinpath(output_dir, "line_flows.csv"), line_flows)
    end
    
    costs = compute_cost_breakdown(model, config, sets, params)
    CSV.write(joinpath(output_dir, "cost_summary.csv"), costs.summary)
    CSV.write(joinpath(output_dir, "operating_costs.csv"), costs.operating)
    CSV.write(joinpath(output_dir, "investment_costs.csv"), costs.investment)
    
    println("\n✓ Results saved to: $output_dir")
end

# ==============================================================================
# Comprehensive Summary
function summarize_tep_results(model, config::TEPConfig, sets, params; save_to::Union{String,Nothing}=nothing)
    println("\n" * "="^70)
    println("TRANSMISSION AND GENERATION EXPANSION PLANNING - RESULTS SUMMARY")
    println("="^70)
    
    # Cost breakdown
    costs = compute_cost_breakdown(model, config, sets, params)
    println("\n📊 COST BREAKDOWN")
    println("-" * "="^69)
    for row in eachrow(costs.summary)
        println("  $(rpad(row.category, 20)): \$$(round(row.value, digits=2))")
    end
    
    # Capacity investments
    cap_inv = extract_capacity_investments(model, sets, params)
    total_cap = filter(row -> row.capacity_added_mw > 0.01, cap_inv)
    
    if nrow(total_cap) > 0
        println("\n⚡ GENERATION CAPACITY INVESTMENTS")
        println("-" * "="^69)
        for row in eachrow(total_cap)
            println("  Year $(row.year), Gen $(row.gen_id): $(round(row.capacity_added_mw, digits=2)) MW (\$$(round(row.investment_cost, digits=2)))")
        end
    end
    
    # Line investments
    if config.include_network
        line_inv = extract_line_investments(model, config, sets, params)
        built_lines = filter(row -> row.built, line_inv)
        
        if nrow(built_lines) > 0
            println("\n🔌 TRANSMISSION LINE INVESTMENTS")
            println("-" * "="^69)
            for row in eachrow(built_lines)
                println("  Year $(row.year), Line $(row.line_id): Built (\$$(round(row.investment_cost, digits=2)))")
            end
        else
            println("\n🔌 TRANSMISSION LINE INVESTMENTS: None")
        end
    end
    
    println("\n" * "="^70)
    
    # Save if requested
    if !isnothing(save_to)
        save_tep_results(model, config, sets, params, save_to)
    end
    
    return costs
end