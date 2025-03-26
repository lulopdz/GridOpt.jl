function market_model(mpc, df, pCmax, costC)
    # ==========================================================================
    # Sets and indices
    nT = 25                          # number of time periods
    nN = length(mpc["bus"])          # number of buses
    nL = length(mpc["branch"])       # number of branches
    nG = length(mpc["gen"])          # number of generators

    # Buses, branches, generators and time periods (as sets)    
    N  = [Int(mpc["bus"][i][1]) for i in 1:nN]
    L  = collect(1:nL)
    bL = [(Int(mpc["branch"][i][1]), Int(mpc["branch"][i][2])) for i in 1:nL]
    G  = collect(1:nG)
    bG = [Int(mpc["gen"][i][1]) for i in 1:nG]
    T  = collect(2:nT)
    # Find the slack bus (bus with value 3 in 2nd field)
    ref = findfirst(x -> x[2] == 3, mpc["bus"])

    C = [1]
    bC = 2
    # ==========================================================================
    # Parameters
    Sbase = 100

    # Generation limits and cost
    Pmin = [mpc["gen"][i][10] for i in G] ./ Sbase
    Pmax = [mpc["gen"][i][9] for i in G] ./ Sbase
    cost = [mpc["gencost"][i][6] for i in G]

    # Branch parameters
    B    = [1/mpc["branch"][i][4] for i in L]
    Fmax = [mpc["branch"][i][6] for i in L] ./ Sbase

    # Bus demand (base) 
    PD = Dict(N[i] => mpc["bus"][i][3]*df / Sbase for i in 1:nN)

    # Storage sets and parameters
    nE   = length(mpc["storage"])
    E    = collect(1:nE)
    bE   = [Int(mpc["storage"][i][1]) for i in 1:nE]
    PEVch   = [mpc["storage"][i][6] for i in E] ./ Sbase
    PEVdis  = [mpc["storage"][i][7] for i in E] ./ Sbase
    eta_ch  = [mpc["storage"][i][8] for i in E]
    eta_dis = [mpc["storage"][i][9] for i in E]
    Emax = [mpc["storage"][i][5] for i in E] ./ Sbase
    Emin = 0.2 .* Emax
    Eo   = [mpc["storage"][i][4] for i in E] ./ Sbase

    # Time-varying demand factor (example: sinusoidal variation)
    PD_factor = Dict(t => 0.9 - 0.3*sin(1.7*pi*(t-1)/nT) for t in T)

    pCmax = pCmax / Sbase
    total_gen = sum(Pmax) + pCmax
    total_dem = sum(values(PD))
    if total_dem > total_gen
        return (0.0, 0.0, false)
    end

    # ==========================================================================    
    # Model
    m = Model(Ipopt.Optimizer)
    set_silent(m)

    # ==========================================================================
    # Variables 
    @variable(m, pg[G, T])
    @variable(m, theta[N, T])
    @variable(m, f[L, T])

    @variable(m, pEV_ch[E, T])
    @variable(m, pEV_dis[E, T])
    @variable(m, eEV[E, [1; T]])

    @variable(m, pc[C, T])
    # Constraints
    @constraint(m, [g in G, t in T], Pmin[g] <= pg[g, t] <= Pmax[g])
    @constraint(m, [l in L, t in T], -Fmax[l] <= f[l, t] <= Fmax[l])
    @constraint(m, [l in L, t in T], 
                f[l, t] == B[l] * (theta[bL[l][1], t] - theta[bL[l][2], t])
    )
    @constraint(m, [t in T], theta[ref, t] == 0)
    @constraint(m, [n in N, t in T], -pi <= theta[n, t] <= pi)
    # @constraint(m, lambda[n in N, t in T], PD[n]*PD_factor[t] ==
    #                 sum(pc[c, t] for c in C if bC[c] == n) +
    #                 sum(pg[g, t] for g in G if bG[g] == n) - 
    #                 sum(f[l, t] for l in L if bL[l][1] == n) + 
    #                 sum(f[l, t] for l in L if bL[l][2] == n) +
    #                 sum(pEV_dis[e, t] for e in E if bE[e] == n) -
    #                 sum(pEV_ch[e, t] for e in E if bE[e] == n)
    # )

    @constraint(m, lambda[n in N, t in T], PD[n] * PD_factor[t] == 
                    sum(pc[c, t] for c in C if bC[c] == n) +
                    sum(pg[g, t] for g in G if bG[g] == n) - 
                    sum(f[l, t] for l in L if bL[l][1] == n) + 
                    sum(f[l, t] for l in L if bL[l][2] == n)
    )

    @constraint(m, [e in E, t in T], 0 <= pEV_ch[e, t] <= PEVch[e])
    @constraint(m, [e in E, t in T], 0 <= pEV_dis[e, t] <= PEVdis[e])
    @constraint(m, [e in E, t in T], Emin[e] <= eEV[e, t] <= Emax[e])
    @constraint(m, [e in E, t in T], pEV_ch[e, t]*pEV_dis[e, t] == 0)
    @constraint(m, [e in E], eEV[e, 1] == Eo[e])

    @constraint(m, [e in E, t in T], eEV[e, t] == eEV[e, t-1] + 
                    eta_ch[e]*pEV_ch[e, t] - 
                    pEV_dis[e, t]/eta_dis[e]
    )

    @constraint(m, yup[c in C, t in T], 0 <= pc[c, t] <= pCmax)

    # ==========================================================================
    # Objective
    @objective(m, Min, sum(cost[g]*pg[g, t]*Sbase for g in G, t in T)+ 
                       sum(costC[c]*pc[c, t]*Sbase for c in C, t in T))

    # ==========================================================================
    # Optimize 
    optimize!(m)

    # ==========================================================================
    # Print results
    println("Objective value: ", objective_value(m))
    println("Status: ", termination_status(m))

    return (objective_value(m), 
            maximum([dual(yup[c, t]) for c in C, t in T]), 
            termination_status(m) == LOCALLY_SOLVED)
end
