# ==============================================================================
# Set Objective Function
function set_tgep_objective!(model, config::TEPConfig, sets, params)
    G, D, L, T, O = sets[:G], sets[:D], sets[:L], sets[:T], sets[:O]
    K, Sk = sets[:K], sets[:Sk]

    pg, pk, ls = model[:pg], model[:pk], model[:ls]
    pkmax, ekmax = model[:pkmax], model[:ekmax]
    em = model[:em]

    Pgcost, Pkcost = params[:Pgcost], params[:Pkcost]
    Pkinv, Skinv, Flinv = params[:Pkinv], params[:Skinv], params[:Flinv]
    Pgfixed, Pkfixed = params[:Pgfixed], params[:Pkfixed]
    Pgmax = params[:Pgmax]
    VoLL = params[:VoLL]
    α, ρ = params[:α], params[:ρ]
    
    Ctax = params[:Ctax]
    Fmaxl = params[:Fmaxl]
    
    # Operating costs
    @expression(model, op_cost, sum(
        α[t] * sum(
            ρ[o] * (
                sum(Pgcost[g] * pg[g, t, o] for g in G) +
                sum(Pkcost[k] * pk[k, t, o] for k in K) + 
                sum(VoLL[d] * ls[d, t, o] for d in D)
            ) for o in O
        ) for t in T
    ))
    
    # Investment costs
    @expression(model, gen_stor_inv, sum(
        α[t] * (
            sum(Pkinv[k] * sum(pkmax[k, τ] for τ in T if τ <= t) for k in K) +
            sum(Skinv[s] * sum(ekmax[s, τ] for τ in T if τ <= t) for s in Sk)
        ) for t in T
    ))

    # Network investment
    if config.include_network
        β = model[:β] # Safe to extract here
        Fmaxl = params[:Fmaxl]
        @expression(model, net_inv, sum(
            α[t] * sum(Flinv[l] * Fmaxl[l] * sum(β[l, τ] for τ in T if τ <= t) for l in L)
            for t in T
        ))
        @expression(model, inv_cost, gen_stor_inv + net_inv)
    else
        @expression(model, inv_cost, gen_stor_inv)
    end    

    # Fixed annual costs
    @expression(model, fixed_cost, sum(
        α[t] * (
            sum(Pgfixed[g] * Pgmax[g] for g in G) +
            sum(Pkfixed[k] * sum(pkmax[k, τ] for τ in T if τ <= t) for k in K)
        ) for t in T
    ))

    # Carbon policy cost: $/tCO2 times annualized weighted emissions.
    if config.include_carbon_tax
        Ctax = params[:Ctax]
        @expression(model, carbon_cost, sum(
            α[t] * sum(ρ[o] * Ctax[t] * em[t, o] for o in O) 
            for t in T
        ))
    else
        @expression(model, carbon_cost, 0.0)
    end

    @objective(model, Min, op_cost + inv_cost + fixed_cost + carbon_cost)
end
