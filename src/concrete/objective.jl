# ==============================================================================
# Set Objective Function
function set_tgep_objective!(model, config::TEPConfig, sets, params)
    G, K, D, L, T, O = sets[:G], sets[:K], sets[:D], sets[:L], sets[:T], sets[:O]
    α, ρ = params[:α], params[:ρ]
    pg, pk, ls, pkmax, β, em = model[:pg], model[:pk], model[:ls], model[:pkmax], model[:β], model[:em]
    Pgcost, Pkcost, Pkinv, Flinv = params[:Pgcost], params[:Pkcost], params[:Pkinv], params[:Flinv]
    Pgfixed, Pkfixed = params[:Pgfixed], params[:Pkfixed]
    Ctax = params[:Ctax]
    Pgmax = params[:Pgmax]
    Fmaxl = params[:Fmaxl]
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
                sum(Pkinv[k] * sum(pkmax[k, τ] for τ in 1:t) for k in K) +
                sum(Flinv[l] * Fmaxl[l] * sum(β[l, τ] for τ in 1:t) for l in L)
            ) for t in T
        )
    else
        inv_cost = sum(
            α[t] * sum(Pkinv[k] * sum(pkmax[k, τ] for τ in 1:t) for k in K)
            for t in T
        )
    end

    # Fixed annual costs
    fixed_cost = sum(
        α[t] * (
            sum(Pgfixed[g] * Pgmax[g] for g in G) +
            sum(Pkfixed[k] * sum(pkmax[k, τ] for τ in 1:t) for k in K)
        ) for t in T
    )

    # Carbon policy cost: $/tCO2 times annualized weighted emissions.
    carbon_cost = sum(α[t] * sum(ρ[o] * Ctax[t] * em[t, o] for o in O) for t in T)
    carbon_cost = 0
    
    @objective(model, Min, op_cost + inv_cost + fixed_cost + carbon_cost)
end
