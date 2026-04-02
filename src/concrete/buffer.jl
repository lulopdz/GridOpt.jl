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