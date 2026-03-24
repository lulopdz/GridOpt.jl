# src/concrete/constraints.jl
# ==============================================================================
# Add Generation Constraints
function add_generation_constraints!(model, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    pg, pk, pkmax = model[:pg], model[:pk], model[:pkmax]
    Pgmax, Pgmin, Pkmin, Pkmax = params[:Pgmax], params[:Pgmin], params[:Pkmin], params[:Pkmax]
    Pgcf, Pkcf = params[:Pgcf], params[:Pkcf]
    
    # Existing generator limits
    @constraint(model, [g in G, t in T, o in O], Pgmin[g] * Pgmax[g] <= pg[g, t, o])
    @constraint(model, [g in G, t in T, o in O], pg[g, t, o] <= Pgmax[g] * Pgcf[(g, o)])
    
    # Candidate generator limits
    @constraint(model, [k in K, t in T, o in O], Pkmin[k] * sum(pkmax[k, τ] for τ in 1:t) <= pk[k, t, o])
    @constraint(model, [k in K, t in T, o in O], pk[k, t, o] <= sum(pkmax[k, τ] for τ in 1:t) * Pkcf[(k, o)])
    @constraint(model, [k in K, t in T], sum(pkmax[k, τ] for τ in 1:t) <= Pkmax[k])
end

# ==============================================================================
# Add Investment Constraints
function add_investment_constraints!(model, sets)
    L, T = sets[:L], sets[:T]
    β = model[:β]
    
    # Line can be built at most once across all years
    @constraint(model, [l in L, t in T], sum(β[l, τ] for τ in 1:t) <= 1)
end

# ==============================================================================
# Add Emissions Constraints and Net-Zero Policy
function add_emissions_constraints!(model, cfg::TEPConfig, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    pg, pk = model[:pg], model[:pk]
    em_e, em_k, em = model[:em_e], model[:em_k], model[:em]
    ρ = params[:ρ]
    Pgem, Pkem = params[:Pgem], params[:Pkem]
    caps_in = get(params, :NetZeroCap, Dict())
    caps = Dict(t => get(caps_in, t, Inf) for t in T)
    finite_cap_years = [t for t in T if isfinite(caps[t])]
    Sb = cfg.per_unit ? 100.0 : 1.0

    @constraint(model, [g in G, t in T, o in O], em_e[g, t, o] == Pgem[g] * Sb * pg[g, t, o])
    @constraint(model, [k in K, t in T, o in O], em_k[k, t, o] == Pkem[k] * Sb * pk[k, t, o])
    @constraint(model, [t in T, o in O], em[t, o] == sum(em_e[g, t, o] for g in G) + sum(em_k[k, t, o] for k in K))

    # Annual weighted emissions must respect cap trajectory (defaults to final-year net-zero).
    if !isempty(finite_cap_years)
        @constraint(model, [t in finite_cap_years], sum(ρ[o] * em[t, o] for o in O) <= caps[t])
    end
end

# ==============================================================================
# Add Network Constraints - Multi-Node with DC Power Flow
function add_network_constraints!(model, config::TEPConfig, sets, params)
    B, D, E, L, T, O = sets[:B], sets[:D], sets[:E], sets[:L], sets[:T], sets[:O]
    G, K = sets[:G], sets[:K]
    Ωg, Ωk, Ωd = sets[:Ωg], sets[:Ωk], sets[:Ωd]
    fr, to, frn, ton = sets[:fr], sets[:to], sets[:frn], sets[:ton]
    Pdf, Pdg = params[:Pdf], params[:Pdg]
    pg, pk, ls = model[:pg], model[:pk], model[:ls]
    θ, f, fl, β = model[:θ], model[:f], model[:fl], model[:β]
    xe, xl, Fmax, Fmaxl, Pd = params[:xe], params[:xl], params[:Fmax], params[:Fmaxl], params[:Pd]
    M = config.bigM
    Sb = params[:Sbase]
    
    # Power balance at each bus
    @constraint(model, demand[b in B, t in T, o in O],
        sum(pg[g, t, o] for g in Ωg[b]) + sum(pk[k, t, o] for k in Ωk[b]) +
        sum(f[e, t, o] for e in E if to[e] == b)   - sum(f[e, t, o] for e in E if fr[e] == b) +
        sum(fl[l, t, o] for l in L if ton[l] == b) - sum(fl[l, t, o] for l in L if frn[l] == b)
        == sum(Pd[d]*Pdf[o]*Pdg[t] for d in Ωd[b]) - sum(ls[d, t, o] for d in Ωd[b])
    )

    # Load shedding cannot exceed demand
    @constraint(model, [d in D, t in T, o in O], ls[d, t, o] <= Pd[d] * Pdf[o] * Pdg[t])
    
    # DC power flow for existing lines
    @constraint(model, [e in E, t in T, o in O], f[e, t, o] == (θ[fr[e], t, o] - θ[to[e], t, o]) / xe[e])
    @constraint(model, [e in E, t in T, o in O], -Fmax[e] <= f[e, t, o] <= Fmax[e])
    
    # DC power flow for candidate lines (with Big-M, scaled by Sb for per-unit consistency)
    @constraint(model, [l in L, t in T, o in O], 
        fl[l, t, o] - (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] <= M * (1 - sum(β[l, τ] for τ in 1:t)))
    @constraint(model, [l in L, t in T, o in O], 
        (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] - fl[l, t, o] <= M * (1 - sum(β[l, τ] for τ in 1:t)))
    
    # Candidate line capacity limits
    @constraint(model, [l in L, t in T, o in O], -Fmaxl[l] * sum(β[l, τ] for τ in 1:t) <= fl[l, t, o])
    @constraint(model, [l in L, t in T, o in O], fl[l, t, o] <= Fmaxl[l] * sum(β[l, τ] for τ in 1:t))
    
    # Reference bus
    @constraint(model, [t in T, o in O], θ[first(B), t, o] == 0.0)
    @constraint(model, [b in B, t in T, o in O], -2π <= θ[b, t, o] <= 2π)
end

# ==============================================================================
# Add Single Node Constraints - Copper Plate
function add_single_node_constraints!(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    pg, pk, ls = model[:pg], model[:pk], model[:ls]
    Pdf, Pdg = params[:Pdf], params[:Pdg]
    Pd = params[:Pd]
    
    # Simple power balance: total generation = total load
    @constraint(model, demand[t in T, o in O],
        sum(pg[g, t, o] for g in G) + sum(pk[k, t, o] for k in K) + sum(ls[d, t, o] for d in D) == sum(Pd[d]*Pdf[o]*Pdg[t] for d in D)
    )

    @constraint(model, [d in D, t in T, o in O], ls[d, t, o] <= Pd[d] * Pdf[o] * Pdg[t])
end
