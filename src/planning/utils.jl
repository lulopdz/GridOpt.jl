# ==============================================================================
# This file contains utility functions for planning problems 
# in the GridOpt.jl package.

# ==============================================================================
# This function maps generators to their respective nodes.
function map_nodes(gens::Vector{Int}, nodes::Vector{Int}, node_range::UnitRange{Int})
    node_gens = Dict(node => Int[] for node in node_range)
    # Group generators by nodes
    for (gen, node) in zip(gens, nodes)
        push!(node_gens[node], gen)
    end

    return node_gens
end

# This function converts the format of the sets and indices for different models.
# ==============================================================================
function static_format(cand, exist, demands)
    # Transform candidate data
    new_cand = Dict(
        :ID => cand[:ID],
        :Prod_cost => [cost[end] for cost in cand[:Prod_cost]],
        :Inv_cost => [cost[end] for cost in cand[:Inv_cost]],
        :Prod_cap => [cap[end] for cap in cand[:Prod_cap]]
    )

    # Transform existing generators data
    new_exist = Dict(
        :ID => exist[:ID],
        :Max_cap => exist[:Max_cap],
        :Prod_cost => [cost[end] for cost in exist[:Prod_cost]]
    )

    # Transform demand data
    new_demands = Dict(
        :ID => demands[:ID],
        :Load => [load[end] for load in demands[:Load]]
    )

    return new_cand, new_exist, new_demands
end

function dynamic_format(cand, exist, demands)
    # Transform candidate data
    new_cand = Dict(
        :ID => cand[:ID],
        :Prod_cost => cand[:Prod_cost],
        :Inv_cost => cand[:Inv_cost],
        :Prod_cap => cand[:Prod_cap]
    )

    # Transform existing generators data
    new_exist = Dict(
        :ID => exist[:ID],
        :Max_cap => exist[:Max_cap],
        :Prod_cost => exist[:Prod_cost]
    )

    # Transform demand data
    new_demands = Dict(
        :ID => demands[:ID],
        :Load => demands[:Load]
    )

    return new_cand, new_exist, new_demands
end

function static_net_format(cand, exist, lines, demands)
    # Transform candidate data
    new_cand = Dict(
        :ID => cand[:ID],
        :Node => cand[:Node],
        :Prod_cost => [cost[end] for cost in cand[:Prod_cost]],
        :Inv_cost => [cost[end] for cost in cand[:Inv_cost]],
        :Prod_cap => [cap[end] for cap in cand[:Prod_cap]]
    )

    # Transform existing generators data
    new_exist = Dict(
        :ID => exist[:ID],
        :Node => exist[:Node],
        :Max_cap => exist[:Max_cap],
        :Prod_cost => [cost[end] for cost in exist[:Prod_cost]]
    )

    # Transform lines data (no change needed)
    new_lines = lines

    # Transform demand data
    new_demands = Dict(
        :ID => demands[:ID],
        :Node => demands[:Node],
        :Load => [load[end] for load in demands[:Load]]
    )

    return new_cand, new_exist, new_lines, new_demands
end

# ==============================================================================
# Market analysis post-optimization
function market_post(results, ref, ρ, model_horizon)
    include(pf * "/GridOpt.jl/data/planning/test.jl")

    # ==========================================================================
    # Maximum dimensions
    function market_dims()
        return Dict(
            :nC => length(cand[:ID]),
            :nG => length(exist[:ID]),
            :nD => length(demands[:ID]),
            :nL => length(lines[:ID]),
            :nN => maximum([maximum(lines[:From]) maximum(lines[:To])]),
            :nT => length(demands[:Load][1]),
            :nO => length(demands[:Load][1][1]),
            :nQ => length(cand[:Prod_cap][1][1])
        )
    end

    # ==========================================================================
    # Sets
    function market_sets(dimensions, cand, exist, lines, demands, ref)
        nC = dimensions[:nC]
        nG = dimensions[:nG]
        nD = dimensions[:nD]
        nL = dimensions[:nL]
        nN = dimensions[:nN]
        nT = dimensions[:nT]
        nO = dimensions[:nO]
        nQ = dimensions[:nQ]
        
        sets = Dict(
            :C => 1:nC,                                # Candidate generating units
            :G => 1:nG,                                # Existing generating units
            :D => 1:nD,                                # Demands
            :L => 1:nL,                                # Transmission lines
            :N => 1:nN,                                # Nodes
            :Nr => setdiff(1:nN, ref),                 # Nodes without slack node
            :T => 1:nT,                                # Time periods
            :O => 1:nO,                                # Operating conditions
            :Q => 1:nQ,                                # Generation capacity blocks
            :ref => ref                                # Slack node
        )
        
        sets[:r] = lines[:To]                          # Receiving-end node of transmission line
        sets[:s] = lines[:From]                        # Sending-end node of transmission line
        sets[:ng] = exist[:Node]                       # Node of existing generating unit g
        sets[:nc] = cand[:Node]                        # Node of candidate generating unit c

        sets_n = Dict()
        sets_n[:Ω_C] = map_nodes(cand[:ID], cand[:Node], sets[:N])             # Candidate generating units located at node n
        sets_n[:Ω_D] = map_nodes(demands[:ID], demands[:Node], sets[:N])       # Demands located at node n
        sets_n[:Ω_E] = map_nodes(exist[:ID], exist[:Node], sets[:N])           # Existing generating units located at node n

        return sets, sets_n
    end

    # ==========================================================================
    # Parameters
    function market_parameters(cand, exist, lines, demands)
        return Dict(
            :B => lines[:Susceptance],                 # Susceptance of transmission line [S]
            :F => lines[:Capacity],                    # Capacity of transmission line [MW]
            :PD => demands[:Load],                     # Load of demand d [MW]
            :C_C => cand[:Prod_cost],                  # Production cost of candidate generating unit c [$/MWh]
            :I_C_A => cand[:Inv_cost],                 # Annualized inv cost of candidate generating unit c [$/MW]
            :P_Opt => cand[:Prod_cap],                 # Production capacity of inv option q of gen unit c [MW]
            :C_E => exist[:Prod_cost],                 # Production cost of existing generating unit g [$/MWh]
            :PEmax => exist[:Max_cap]                  # Production capacity of existing generating unit g [MW]
        )
    end
    
    dims = market_dims()
    sets, sets_n = market_sets(dims, cand, exist, lines, demands, ref)
    params = market_parameters(cand, exist, lines, demands)

    # ==============================================================================
    # Sets and indices
    C = sets[:C]
    G = sets[:G]
    D = sets[:D]
    L = sets[:L]
    N = sets[:N]
    T = sets[:T]
    O = sets[:O]

    r = sets[:r]
    s = sets[:s]
    Ω_C = sets_n[:Ω_C]
    Ω_D = sets_n[:Ω_D]
    Ω_E = sets_n[:Ω_E]

    B = params[:B]
    F = params[:F]
    PD = params[:PD]

    C_C = params[:C_C]
    C_E = params[:C_E]
    PEmax = params[:PEmax]

    # Load shedding penalty (set high to discourage load shedding)
    C_s = 100                           # Penalty cost for shedding load [$/MW]
    pCmax = results[:pCmax]

    market_results= []
    for t in T, o in O
        market = Model(Gurobi.Optimizer)  # Use the appropriate solver
        set_silent(market)
        
        # Variables
        if model_horizon[1] == 's'
            @variable(market, 0 <= pC[c in C] <= value(pCmax[c]))                       # Candidate generation (fixed by plan)
        else 
            @variable(market, 0 <= pC[c in C] <= sum(value(pCmax[c,τ]) for τ in 1:t))    # Candidate generation (fixed by plan)
        end
        @variable(market, 0 <= pE[g in G] <= PEmax[g])
        @variable(market, 0 <= sD[d in D])                                          # Load shedding for demand points
        @variable(market, -pi <= θ[n in N] <= pi)
        @variable(market, -F[l] <= pL[l in L] <= F[l])

        # Market Clearing Constraint
        @constraint(market, [n in N],
            sum(pE[g] for g in Ω_E[n] if g != 0) + sum(pC[c] for c in Ω_C[n] if c != 0) -
            sum(pL[l] for l in L if s[l] == n) + sum(pL[l] for l in L if r[l] == n) + 
            sum(sD[d] for d in Ω_D[n] if d != 0)
            == sum(PD[d][t][o] for d in Ω_D[n] if d != 0)
        )

        # Transmission Line Flow Constraints
        @constraint(market, [l in L], pL[l] == B[l] * (θ[r[l]] - θ[s[l]]))
        @constraint(market, θ[ref] == 0)  # Reference node angle

        # Objective: Minimize Generation Cost + Load Shedding Cost
        gen_cost = sum(C_E[g][t] * pE[g] for g in G) + sum(C_C[c][t] * pC[c] for c in C)
        shed_cost = sum(C_s * sD[d] for d in D)
        @objective(market, Min, gen_cost + shed_cost)

        # Solve
        optimize!(market)

        # Store results for this scenario
        r_market = Dict(
            "Time Period" => t,
            "Operating Condition" => o,
            "Operation Cost (M\$)" => ρ[t][o]/1e6*value(gen_cost),
            "Load Shed Cost (M\$)" => ρ[t][o]/1e6*sum(C_s * value(sD[d]) for d in D),
            "Load Shed (MW)" => sum(value(sD[d]) for d in D),
            "Existing Gen (MW)" => sum(value(pE[g]) for g in G),
            "Candidate Gen (MW)" => sum(value(pC[c]) for c in C),
            "Demand (MW)" => sum(PD[d][t][o] for d in D),
            "Congestion" => any(abs(value(pL[l])) >= F[l] for l in L) ? "Yes" : "No",
            "Status" => termination_status(market)
        )
        println(r_market["Status"])

        push!(market_results, r_market)
    end

    # Save to CSV
    df_results = DataFrame(market_results)
    dfp = pf * "/GridOpt.jl/results/planning/"
    CSV.write(dfp * model_horizon * "_market.csv", df_results)

    println("Results saved for market clearance")
end

# ==============================================================================
# Solve model
function solve_model(mip, params)
    optimize!(mip)
    if termination_status(mip) == MOI.OPTIMAL
        println("Optimal solution found.")
        println("Objective value: ", objective_value(mip))
        println("Solution time: ", solve_time(mip))
    elseif termination_status(mip) == MOI.TIME_LIMIT
        println("Time limit reached.")
    else
        println("Solver terminated with status: ", termination_status(mip))
    end

    results = Dict(
        :pE => value.(mip[:pE]),
        :pC => value.(mip[:pC]),
        :pCmax => value.(mip[:pCmax]), 
        :PD => params[:PD]
    )
    
    return results
end