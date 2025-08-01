# mpc = parse_mpc("GridOpt.jl/data/case5_strg.m")
# df = 1
# pCmax = [60.0, 0.0]
# costC = [15.0, 15.0]
# busC = [2, 4]
# pd_data = pd_profiles[1, :]
# ev_data = ev_profiles[1, :]

function market_model(mpc, df, pCmax, costC, busC, ev_data, pd_data, ω)
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
    ref = mpc["bus"][ref][1]

    C = collect(1:length(costC))                # number of candidates
    bC = busC
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
    Emin = [0.3, 0.2] .* Emax
    Eo   = [mpc["storage"][i][4] for i in E] ./ Sbase

    # Time-varying demand factor (example: sinusoidal variation)
    # PD_factor = Dict(t => 0.9 - 0.3*sin(1.7*pi*(t-1)/nT) for t in T)
    PD_factor = Dict(t => pd_data[t-1] for t in T)
    ev_factor = Dict(t => 1 - ev_data[t-1] for t in T)

    pCmax = pCmax / Sbase
    total_gen = sum(Pmax) + sum(pCmax)
    total_dem = sum(values(PD))
    maxD = maximum(total_dem * v for v in values(PD_factor))
    println("Subproblem data: ")
    println("  Total generation: ", total_gen)
    println("  Total demand: ", maxD)
    # if total_dem > total_gen
    #     return (0.0, 0.0, false)
    # end

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
    @constraint(m, lambda[n in N, t in T], PD[n]*PD_factor[t] ==
                    sum(pc[c, t] for c in C if bC[c] == n) +
                    sum(pg[g, t] for g in G if bG[g] == n) - 
                    sum(f[l, t] for l in L if bL[l][1] == n) + 
                    sum(f[l, t] for l in L if bL[l][2] == n) +
                    sum(pEV_dis[e, t] for e in E if bE[e] == n) -
                    sum(pEV_ch[e, t] for e in E if bE[e] == n)
    )

    # @constraint(m, lambda[n in N, t in T], PD[n] * PD_factor[t] == 
    #                 sum(pc[c, t] for c in C if bC[c] == n) +
    #                 sum(pg[g, t] for g in G if bG[g] == n) - 
    #                 sum(f[l, t] for l in L if bL[l][1] == n) + 
    #                 sum(f[l, t] for l in L if bL[l][2] == n)
    # )

    @constraint(m, [e in E, t in T], 0 <= pEV_ch[e, t] <= PEVch[e]*ev_factor[t])
    @constraint(m, [e in E, t in T], 0 <= pEV_dis[e, t] <= PEVdis[e]*ev_factor[t])
    @constraint(m, [e in E, t in T], Emin[e] <= eEV[e, t] <= Emax[e]*ev_factor[t])
    @constraint(m, [e in E, t in T], pEV_ch[e, t]*pEV_dis[e, t] == 0)
    @constraint(m, [e in E], eEV[e, 1] == Eo[e])
        @constraint(m, [e in E, t in T], eEV[e, t] == eEV[e, t-1] + 
                    eta_ch[e]*pEV_ch[e, t] - 
                    pEV_dis[e, t]/eta_dis[e]
    )

    @constraint(m, yup[c in C, t in T], 0 <= pc[c, t] <= pCmax[c])

    # ==========================================================================
    # Objective
    @objective(m, Min, sum(cost[g]*pg[g, t]*Sbase for g in G, t in T)+ 
                       sum(costC[c]*pc[c, t]*Sbase for c in C, t in T))

    # ==========================================================================
    # Optimize 
    optimize!(m)

    # ==========================================================================
    # Print results
    println("  Objective value: ", objective_value(m))
    println("  Status: ", termination_status(m))
    println("  Solving time = ", solve_time(m))

    maxD = maximum(total_dem * v for v in values(PD_factor)) * Sbase
    println("        Max demand: ", maxD)
    totalG = [sum(value(pg[g, t]) for g in G) + sum(value(pc[c, t]) for c in C) for t in T]
    maxG = maximum(totalG) * Sbase
    println("        Max total gen: ", maxG)

    market_plots(pg, pc, eEV, pEV_ch, pEV_dis, total_dem, PD_factor, lambda, G, C, E, T, N, Sbase, ω)

    return (objective_value(m), 
            [maximum(dual(yup[c, t]) for t in T) for c in C],
            termination_status(m) == LOCALLY_SOLVED,
            maxD)
            
end

function market_plots(pg, pc, eEV, pEV_ch, pEV_dis, total_dem, PD_factor, lambda, G, C, E, T, N, Sbase, ω)
    # Extract the values of pg and pc
    pg_data = [round(value(pg[g, t]), digits=3) for g in G, t in T]
    pc_data = [round(value(pc[c, t]), digits=3) for c in C, t in T]

    eEV_data = [round(value.(eEV[e,t]), digits = 3) for e in E, t in T]
    pEV_ch_data = [round(value(pEV_ch[e,t]), digits = 3) for e in E, t in T]
    pEV_dis_data = [round(value(pEV_dis[e,t]), digits = 3) for e in E, t in T]

    color = collect(cgrad(:GnBu, nG, rev = true))
    colorg = color[1:nG]
    color = collect(cgrad(:Greens, nC, rev = true))
    colorc = color[1:nC]

    l = @layout [a{0.4h}; b{0.6h}]

    p1 = areaplot(1:24, [pg_data' pc_data']*Sbase, 
            ylabel="Power (MW)", 
            xlims=(1, 24), 
            label="",
            color=[colorg; colorc]',
            lw = 0
    )

    demand_h = [total_dem*PD_factor[t] for t in T]*Sbase
    plot!(p1, 1:24, demand_h, 
        color="#a50f15", 
        lw = 3, 
        la = 0.6,
        ls = :solid,
        label="Demand",
        legend = :topleft,
        ylims = (0, 1400)
    )

    p2 = areaplot(1:24, [pg_data' pc_data']*Sbase, 
            xlabel="Time (h)", 
            ylabel="Power (MW)", 
            xlims=(1, 24), 
            label=[L"G_1" L"G_2" L"G_3" L"G_4" L"G_5" L"C_1" L"C_2"],
            color=[colorg; colorc]',
            lw = 0,
            # ylims=(0.95*minimum(demand_h), 1.05*maximum(demand_h)),
            ylims = (700, 1400),
            legendcolumns = 2,
            legend = :topleft,
    )

    demand_h = [total_dem*PD_factor[t] for t in T]*Sbase
    plot!(p2, 1:24, demand_h, 
        color="#a50f15", 
        lw = 2, 
        la = 0.6,
        ls = :solid,
        label="",
    )

    plot(p1, p2, layout=l)

    # Save the plot
    savefig("GridOpt.jl/src/ev/plots/stacked_gen_$ω.pdf")

    nE = length(E)
    color = collect(cgrad(:Purples_5, nE, rev = true))
    colore = color[1:nE]

    layout = @layout [a; b]

    pe = areaplot(1:24, eEV_data'*Sbase, 
        ylabel = "Energy (MWh)",
        color = colore',
        xlims=(1, 24),
        label=[L"a_3" L"a_2"], 
        ylims = (0, 200)
    )
    pp = areaplot(1:24, pEV_ch_data'*Sbase - pEV_dis_data'*Sbase,
        color = colore',
        xlims=(1, 24),
        xlabel = "Time (h)",
        ylabel = "Power (MW)",
        label=[L"a_3" L"a_2"], 
        ylims = (-20, 40)
    )
    plot(pe, pp, layout=layout)

    savefig("GridOpt.jl/src/ev/plots/stacked_sto_$ω.pdf")

    # Plot lambda
    lambda_data = [round(-value(lambda[n, t]), digits=3) for n in N, t in T]
    axisN = collect(1:length(N))
    axisT = collect(1:length(T))
    po = heatmap(lambda_data, levels = 5,
        xlabel="Time (h)", 
        ylabel="Bus", 
        yticks=(axisN, N),
        xticks=(1:2:24, 1:2:24),
        color=cgrad(:RdBu, rev = true), 
        # title=L"\lambda", 
        clims=(minimum(lambda_data), maximum(lambda_data)),
    )

    savefig(po, "GridOpt.jl/src/ev/plots/price_heatmap_$ω.pdf")

end

# market_model(mpc, df, pCmax, costC, busC)
