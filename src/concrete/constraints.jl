# src/concrete/constraints.jl

# ==============================================================================
# Add Generation Constraints
function add_generation_constraints!(model, sets, params)
    T, O = sets[:T], sets[:O]
    G, K = sets[:G], sets[:K]
    pg, pk = model[:pg], model[:pk]
    pkmax = model[:pkmax]
    Pgmax, Pgmin = params[:Pgmax], params[:Pgmin] 
    Pkmin, Pkmax = params[:Pkmin], params[:Pkmax]
    Pgcf, Pkcf = params[:Pgcf], params[:Pkcf]
    Pgramp, Pkramp = params[:Pgramp], params[:Pkramp]

    # Existing generator limits
    @constraint(model, [g in G, t in T, o in O], Pgmin[g] * Pgmax[g] <= pg[g, t, o])
    @constraint(model, [g in G, t in T, o in O], pg[g, t, o] <= Pgmax[g] * Pgcf[(g, o)])
    @constraint(model, [g in G, t in T, o in O[2:end]], 
        pg[g, t, o] - pg[g, t, o-1] <= Pgramp[g] * Pgmax[g]) # Ramp Up
    @constraint(model, [g in G, t in T, o in O[2:end]], 
        pg[g, t, o-1] - pg[g, t, o] <= Pgramp[g] * Pgmax[g]) # Ramp Down
    
    # Candidate generator limits
    @expression(model, cum_pkmax[k in K, t in T], sum(pkmax[k, τ] for τ in T if τ <= t))

    @constraint(model, [k in K, t in T, o in O], Pkmin[k] * cum_pkmax[k, t] <= pk[k, t, o])
    @constraint(model, [k in K, t in T, o in O], pk[k, t, o] <= cum_pkmax[k, t] * Pkcf[(k, o)])
    @constraint(model, [k in K, t in T], cum_pkmax[k, t] <= Pkmax[k])
    
    @constraint(model, [k in K, t in T, o in O[2:end]], 
        pk[k, t, o] - pk[k, t, o-1] <= Pkramp[k] * cum_pkmax[k, t]) # Ramp Up
    @constraint(model, [k in K, t in T, o in O[2:end]], 
        pk[k, t, o-1] - pk[k, t, o] <= Pkramp[k] * cum_pkmax[k, t]) # Ramp Down

end

# ==============================================================================
# Add Investment Constraints
function add_investment_constraints!(model, sets)
    L, T = sets[:L], sets[:T]
    β = model[:β]
    
    # Line can be built at most once across all years
    @constraint(model, [l in L, t in T], sum(β[l, τ] for τ in T if τ <= t) <= 1)
end


# ==============================================================================
# Add Storage Constraints
function add_storage_constraints!(model, sets, params)
    T, O =  sets[:T], sets[:O]
    S, Sk = sets[:S], sets[:Sk]
    soc, pch, pdis = model[:soc], model[:pch], model[:pdis]
    η_ch, η_dis = params[:η_ch], params[:η_dis]
    Emax, Einit = params[:Emax], params[:Einit]
    Pscmax, Psdmax = params[:Pscmax], params[:Psdmax]

    Ekmax = params[:Ekmax]
    Psckmax, Psdkmax = params[:Psckmax], params[:Psdkmax]
    η_chk, η_disk = params[:η_chk], params[:η_disk]

    # Storage operation constraints
    @constraint(model, [s in S, t in T, o in O], soc[s, t, o] <= Emax[s])
    @constraint(model, [s in S, t in T, o in O], pch[s, t, o] <= Pscmax[s])
    @constraint(model, [s in S, t in T, o in O], pdis[s, t, o] <= Psdmax[s])
    
    # State of charge dynamics (assuming hourly time steps)
    @constraint(model, [s in S, t in T, o in [1]], soc[s, t, o] == Einit[s] * Emax[s]) 
    @constraint(model, [s in S, t in T, o in O[2:end]], 
        soc[s, t, o] == soc[s, t, o-1] + η_ch[s] * pch[s, t, o-1] - (1/η_dis[s]) * pdis[s, t, o-1])

    # Expansion constraints for storage (if candidate storage is included)
    ekmax = model[:ekmax]
    psckmax, psdkmax = model[:psckmax], model[:psdkmax]
    sock, pchk, pdisk = model[:sock], model[:pchk], model[:pdisk]

    # Cumulative expressions
    @expression(model, cum_ekmax[s in Sk, t in T], sum(ekmax[s, τ] for τ in T if τ <= t))
    @expression(model, cum_psckmax[s in Sk, t in T], sum(psckmax[s, τ] for τ in T if τ <= t))
    @expression(model, cum_psdkmax[s in Sk, t in T], sum(psdkmax[s, τ] for τ in T if τ <= t))    

    @constraint(model, [s in Sk, t in T], cum_ekmax[s, t] <= Ekmax[s])
    @constraint(model, [s in Sk, t in T], cum_psckmax[s, t] <= Psckmax[s])
    @constraint(model, [s in Sk, t in T], cum_psdkmax[s, t] <= Psdkmax[s])

    @constraint(model, [s in Sk, t in T, o in O], sock[s, t, o] <= cum_ekmax[s, t])
    @constraint(model, [s in Sk, t in T, o in O], pchk[s, t, o] <= cum_psckmax[s, t])
    @constraint(model, [s in Sk, t in T, o in O], pdisk[s, t, o] <= cum_psdkmax[s, t])

    @constraint(model, [s in Sk, t in T, o in [1]], sock[s, t, o] == 0.0) 
    @constraint(model, [s in Sk, t in T, o in O[2:end]], 
        sock[s, t, o] == sock[s, t, o-1] + η_chk[s] * pchk[s, t, o-1] - (1/η_disk[s]) * pdisk[s, t, o-1])
end

# ==============================================================================
# Add Emissions Constraints and Net-Zero Policy
function add_emissions_constraints!(model, cfg::TEPConfig, sets, params)
    T, O = sets[:T], sets[:O]
    G, K = sets[:G], sets[:K]
    pg, pk = model[:pg], model[:pk]
    em_e, em_k, em = model[:em_e], model[:em_k], model[:em]
    ρ = params[:ρ]
    Pgem, Pkem = params[:Pgem], params[:Pkem]
    Sb = params[:Sbase]
    caps_in = get(params, :NetZeroCap, Dict())
    caps = Dict(t => get(caps_in, t, Inf) for t in T)
    finite_cap_years = [t for t in T if isfinite(caps[t])]

    @constraint(model, [g in G, t in T, o in O], em_e[g, t, o] == Pgem[g] * Sb * pg[g, t, o])
    @constraint(model, [k in K, t in T, o in O], em_k[k, t, o] == Pkem[k] * Sb * pk[k, t, o])
    @constraint(model, [t in T, o in O], em[t, o] == 
        sum(em_e[g, t, o] for g in G) + sum(em_k[k, t, o] for k in K))

    # Annual weighted emissions must respect cap trajectory (defaults to final-year net-zero).
    if cfg.enforce_netzero && !isempty(finite_cap_years)
        @constraint(model, [t in finite_cap_years], sum(ρ[o] * em[t, o] for o in O) <= caps[t])
    end
end

# ==============================================================================
# Add Network Constraints - Multi-Node with DC Power Flow
function add_network_constraints!(model, config::TEPConfig, sets, params)
    B, D, E, L, T, O = sets[:B], sets[:D], sets[:E], sets[:L], sets[:T], sets[:O]
    G, K = sets[:G], sets[:K]
    Slack = sets[:Slack]
    Ωg, Ωk, Ωd, Ωs, Ωsk = sets[:Ωg], sets[:Ωk], sets[:Ωd], sets[:Ωs], sets[:Ωsk]
    fr, to, frn, ton = sets[:fr], sets[:to], sets[:frn], sets[:ton]

    Pdf, Pdg, Pd = params[:Pdf], params[:Pdg], params[:Pd]
    pg, pk, ls = model[:pg], model[:pk], model[:ls]
    θ, f, fl, β = model[:θ], model[:f], model[:fl], model[:β]
    pch, pdis = model[:pch], model[:pdis]
    pchk, pdisk = model[:pchk], model[:pdisk]
    xe, xl, Fmax, Fmaxl = params[:xe], params[:xl], params[:Fmax], params[:Fmaxl]
    Sb = params[:Sbase]
    M = config.bigM
    
    # Cumulative expression for line investment 
    @expression(model, cum_β[l in L, t in T], sum(β[l, τ] for τ in T if τ <= t))

    # Power balance at each bus
    @constraint(model, demand[b in B, t in T, o in O],
        sum(pg[g, t, o] for g in Ωg[b]) + sum(pk[k, t, o] for k in Ωk[b]) +
        sum(f[e, t, o] for e in E if to[e] == b)   - sum(f[e, t, o] for e in E if fr[e] == b) +
        sum(fl[l, t, o] for l in L if ton[l] == b) - sum(fl[l, t, o] for l in L if frn[l] == b) + 
        sum(pdis[s, t, o] for s in Ωs[b]) - sum(pch[s, t, o] for s in Ωs[b]) +
        sum(pdisk[s, t, o] for s in Ωsk[b]) - sum(pchk[s, t, o] for s in Ωsk[b])
        == sum(Pd[d]*Pdf[o]*Pdg[t] for d in Ωd[b]) - sum(ls[d, t, o] for d in Ωd[b])
    )

    # Load shedding cannot exceed demand
    @constraint(model, [d in D, t in T, o in O], ls[d, t, o] <= Pd[d] * Pdf[o] * Pdg[t])
    
    # DC power flow for existing lines
    @constraint(model, [e in E, t in T, o in O], f[e, t, o] == 
        (θ[fr[e], t, o] - θ[to[e], t, o]) / xe[e])
    @constraint(model, [e in E, t in T, o in O], -Fmax[e] <= f[e, t, o] <= Fmax[e])
    
    # DC power flow for candidate lines (with Big-M)
    @constraint(model, [l in L, t in T, o in O], 
        fl[l, t, o] - (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] <= M * (1 - cum_β[l, t]))
    @constraint(model, [l in L, t in T, o in O], 
        (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] - fl[l, t, o] <= M * (1 - cum_β[l, t]))
    
    # Candidate line capacity limits
    @constraint(model, [l in L, t in T, o in O], -Fmaxl[l] * cum_β[l, t] <= fl[l, t, o])
    @constraint(model, [l in L, t in T, o in O], fl[l, t, o] <= Fmaxl[l] * cum_β[l, t])
    
    # Reference bus
    @constraint(model, [t in T, o in O], θ[Slack[1], t, o] == 0.0)
    @constraint(model, [b in B, t in T, o in O], -2π <= θ[b, t, o] <= 2π)
end

# ==============================================================================
# Add Single Node Constraints - Copper Plate
function add_single_node_constraints!(model, sets, params)
    G, K, D, T, O = sets[:G], sets[:K], sets[:D], sets[:T], sets[:O]
    S, Sk = sets[:S], sets[:Sk]
    pg, pk, ls = model[:pg], model[:pk], model[:ls]
    pchk, pdisk = model[:pchk], model[:pdisk]
    pdis, pch = model[:pdis], model[:pch]
    Pdf, Pdg = params[:Pdf], params[:Pdg]
    Pd = params[:Pd]
    
    # Simple power balance: total generation = total load
    @constraint(model, demand[t in T, o in O],
        sum(pg[g, t, o] for g in G) + sum(pk[k, t, o] for k in K)  + 
        sum(pdis[s, t, o] for s in S) - sum(pch[s, t, o] for s in S) +
        sum(pchk[s, t, o] for s in Sk) - sum(pdisk[s, t, o] for s in Sk)
        == sum(Pd[d]*Pdf[o]*Pdg[t] for d in D) - sum(ls[d, t, o] for d in D) 
    )

    @constraint(model, [d in D, t in T, o in O], ls[d, t, o] <= Pd[d] * Pdf[o] * Pdg[t])
end