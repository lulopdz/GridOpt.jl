# ==============================================================================
# Set Objective Function
function set_tgep_objective!(model, config::TEPConfig, sets, params)
    G, K, D, L, T, O = sets[:G], sets[:K], sets[:D], sets[:L], sets[:T], sets[:O]
    α, ρ = params[:α], params[:ρ]
    pg, pk, ls, pkmax, β = model[:pg], model[:pk], model[:ls], model[:pkmax], model[:β]
    Pgcost, Pkcost, Pkinv, Flinv = params[:Pgcost], params[:Pkcost], params[:Pkinv], params[:Flinv]
    VoLL = params[:VoLL]
    
    # Operating costs
    op_cost = sum(
        α[t] * sum(
            ρ[o] * (
                sum(Pgcost[g] * pg[g, t, o] for g in G) +
                sum(Pkcost[k] * pk[k, t, o] for k in K) +
                sum(VoLL[d] * ls[d, t, o] for d in D)
            ) for o in O
        ) for t in T
    )
    
    # Investment costs
    if config.include_network
        inv_cost = sum(
            α[t] * (
                sum(Pkinv[k] * pkmax[k, t] for k in K) +
                sum(Flinv[l] * β[l, t] for l in L)
            ) for t in T
        )
    else
        inv_cost = sum(α[t] * sum(Pkinv[k] * pkmax[k, t] for k in K) for t in T)
    end
    
    @objective(model, Min, op_cost + inv_cost)
end
