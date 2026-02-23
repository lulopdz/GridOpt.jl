
# ==============================================================================
# Add Generation Constraints
function add_generation_constraints!(model, sets, params)
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    pg, pk, pkmax = model[:pg], model[:pk], model[:pkmax]
    Pgmax, Pgmin, Pkmin, Pkmax = params.Pgmax, params.Pgmin, params.Pkmin, params.Pkmax
    
    # Existing generator limits
    @constraint(model, [g in G, t in T, o in O], Pgmin[g] <= pg[g, t, o])
    @constraint(model, [g in G, t in T, o in O], pg[g, t, o] <= Pgmax[g])
    
    # Candidate generator limits
    @constraint(model, [k in K, t in T, o in O], Pkmin[k] <= pk[k, t, o])
    @constraint(model, [k in K, t in T, o in O], pk[k, t, o] <= sum(pkmax[k, τ] for τ in 1:t))
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
# Add Network Constraints - Multi-Node with DC Power Flow
function add_network_constraints!(model, config::TEPConfig, sets, params)
    B, E, L, T, O = sets[:B], sets[:E], sets[:L], sets[:T], sets[:O]
    G, K = sets[:G], sets[:K]
    Ωg, Ωk, Ωd = sets[:Ωg], sets[:Ωk], sets[:Ωd]
    fr, to, frn, ton = sets[:fr], sets[:to], sets[:frn], sets[:ton]
    Pdf, Pdg = sets[:Pdf], sets[:Pdg]
    pg, pk = model[:pg], model[:pk]
    θ, f, fl, β = model[:θ], model[:f], model[:fl], model[:β]
    xe, xl, Fmax, Fmaxl, Pd = params.xe, params.xl, params.Fmax, params.Fmaxl, params.Pd
    M = config.bigM
    
    # Power balance at each bus
    @constraint(model, demand[b in B, t in T, o in O],
        sum(pg[g, t, o] for g in Ωg[b]) + sum(pk[k, t, o] for k in Ωk[b]) +
        sum(f[e, t, o] for e in E if to[e] == b)   - sum(f[e, t, o] for e in E if fr[e] == b) +
        sum(fl[l, t, o] for l in L if ton[l] == b) - sum(fl[l, t, o] for l in L if frn[l] == b)
        == sum(Pd[d]*Pdf[o]*Pdg[t] for d in Ωd[b])
    )
    
    # DC power flow for existing lines
    @constraint(model, [e in E, t in T, o in O], f[e, t, o] == (θ[fr[e], t, o] - θ[to[e], t, o]) / xe[e])
    @constraint(model, [e in E, t in T, o in O], -Fmax[e] <= f[e, t, o] <= Fmax[e])
    
    # DC power flow for candidate lines (with Big-M)
    @constraint(model, [l in L, t in T, o in O], 
        fl[l, t, o] - (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] <= M * (1 - sum(β[l, τ] for τ in 1:t)))
    @constraint(model, [l in L, t in T, o in O], 
        (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] - fl[l, t, o] <= M * (1 - sum(β[l, τ] for τ in 1:t)))
    
    # Candidate line capacity limits
    @constraint(model, [l in L, t in T, o in O], -Fmaxl[l] * sum(β[l, τ] for τ in 1:t) <= fl[l, t, o])
    @constraint(model, [l in L, t in T, o in O], fl[l, t, o] <= Fmaxl[l] * sum(β[l, τ] for τ in 1:t))
    
    # Reference bus
    @constraint(model, [t in T, o in O], θ[first(B), t, o] == 0.0)
end

# ==============================================================================
# Add Single Node Constraints - Copper Plate
function add_single_node_constraints!(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    pg, pk = model[:pg], model[:pk]
    Pd = params.Pd
    
    # Simple power balance: total generation = total load
    @constraint(model, demand[t in T, o in O],
        sum(pg[g, t, o] for g in G) + sum(pk[k, t, o] for k in K) == sum(Pd[d] for d in D)
    )
end
