# src/concrete/vars.jl
function add_investment_vars!(m, cfg::TEPConfig, sets)
    T = sets[:T]
    K, Sk, L = sets[:K], sets[:Sk], sets[:L]

    # Generation expansion
    @variable(m, pkmax[k in K, t in T] >= 0)

    # Storage expansion (Energy capacity, charge/discharge capacity)
    @variable(m, ekmax[s in Sk, t in T] >= 0)
    @variable(m, psckmax[s in Sk, t in T] >= 0)
    @variable(m, psdkhmax[s in Sk, t in T] >= 0)

    # Network expansion
    if cfg.include_network
            @variable(m, β[l in L, t in T], Bin)
    end
    
    return m
end

function add_operational_vars!(m, cfg::TEPConfig, sets)
    T, O = sets[:T], sets[:O]
    G, K = sets[:G], sets[:K]
    S, Sk = sets[:S], sets[:Sk]

    # Generation dispatch (existing and candidate)
    @variable(m, pg[g in G, t in T, o in O] >= 0)
    @variable(m, pk[k in K, t in T, o in O] >= 0)

    # Storage operations (existing)
    @variable(m, soc[s in S, t in T, o in O] >= 0)
    @variable(m, pch[s in S, t in T, o in O] >= 0)
    @variable(m, pdis[s in S, t in T, o in O] >= 0)

    # Storage operations (candidate)
    @variable(m, sock[s in Sk, t in T, o in O] >= 0)
    @variable(m, pchk[s in Sk, t in T, o in O] >= 0)
    @variable(m, pdisk[s in Sk, t in T, o in O] >= 0)

    # Emissions
    @variable(m, em_e[g in G, t in T, o in O])
    @variable(m, em_k[k in K, t in T, o in O])
    @variable(m, em[t in T, o in O])
    
    return m
end

function add_slack_vars!(m, sets)
    D, T, O = sets[:D], sets[:T], sets[:O]
    
    # Load shedding / Loss of load
    @variable(m, ls[d in D, t in T, o in O] >= 0)
    
    return m
end

function add_network_vars!(m, cfg::TEPConfig, sets)
    T, O = sets[:T], sets[:O]
    B, E, L = sets[:B], sets[:E], sets[:L]
    
    if cfg.include_network
        @variable(m, θ[b in B, t in T, o in O])
        @variable(m, f[e in E, t in T, o in O])
        @variable(m, fl[l in L, t in T, o in O])
    end
    
    return m
end