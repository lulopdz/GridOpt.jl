# src/concrete/vars.jl
function add_tgep_vars!(m, cfg::TEPConfig, sets)
    G, K, D = sets[:G], sets[:K], sets[:D]
    E, L, B = sets[:E], sets[:L], sets[:B]
    T, O = sets[:T], sets[:O]
    S, Sk = sets[:S], sets[:Sk]
    
    # Dispatch variables
    @variable(m, pg[g in G, t in T, o in O] >= 0)
    @variable(m, pk[k in K, t in T, o in O] >= 0)
    @variable(m, ls[d in D, t in T, o in O] >= 0)

    # Storage variables (energy level in MWh, charge/discharge in MW)
    @variable(m, soc[s in S, t in T, o in O] >= 0)
    @variable(m, pch[s in S, t in T, o in O] >= 0)
    @variable(m, pdis[s in S, t in T, o in O] >= 0)

    @variable(m, sock[s in Sk, t in T, o in O] >= 0)
    @variable(m, pchk[s in Sk, t in T, o in O] >= 0)
    @variable(m, pdisk[s in Sk, t in T, o in O] >= 0)

    # Emissions accounting variables (tCO2/h representative block).
    @variable(m, em_e[g in G, t in T, o in O])
    @variable(m, em_k[k in K, t in T, o in O])
    @variable(m, em[t in T, o in O])
    
    # Investment variables
    @variable(m, pkmax[k in K, t in T] >= 0)
    @variable(m, β[l in L, t in T], Bin)

    # Expansion on storage
    @variable(m, ekmax[s in Sk, t in T] >= 0)
    @variable(m, psckmax[s in Sk, t in T] >= 0)
    @variable(m, psdkhmax[s in Sk, t in T] >= 0)

    # Network variables
    if cfg.include_network
        @variable(m, θ[b in B, t in T, o in O])
        @variable(m, f[e in E, t in T, o in O])
        @variable(m, fl[l in L, t in T, o in O])
    end
    
    return m
end

function add_gep_vars!(m, cfg::TEPConfig, sets)
    G, K, D = sets[:G], sets[:K], sets[:D]
    E, L, B = sets[:E], sets[:L], sets[:B] 
    T, O = sets[:T], sets[:O]

    # Dispatch variables
    @variable(m, pg[g in G, t in T, o in O] >= 0)
    @variable(m, pk[k in K, t in T, o in O] >= 0)
    @variable(m, ls[d in D, t in T, o in O] >= 0)
    
    # Investment variables
    @variable(m, pkmax[k in K, t in T] >= 0)

    if cfg.include_network
        @variable(m, β[l in L, t in T], Bin)
        @variable(m, θ[b in B, t in T, o in O])
        @variable(m, f[e in E, t in T, o in O])
    end
    
    return m
end