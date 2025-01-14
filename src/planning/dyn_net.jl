# ==============================================================================
# Deterministic Dynamic Network-Constrained GEP

# The approach is deterministic, meaning it does not account 
# for uncertainties in the input data.
# It is dynamic, considering multiple time periods for planning.
# The model is network-constrained, taking into account 
# the limitations and capacities of the electrical network.

# ==============================================================================
# Packages
using JuMP, Gurobi, Ipopt, HiGHS
using Plots, CSV 

# ==============================================================================
# Include utility functions and test data for planning
pf = pwd()
include(pf * "/GridOpt.jl/data/planning/test.jl")

# Main function to run the entire process
function dyn_net()
    dims = get_dimensions(cand, exist, lines, demands)
    sets, sets_n = define_sets(dims, cand, exist, lines, demands, ref)
    params = define_parameters(cand, exist, lines, demands)
    mip = build_model(sets, sets_n, params, ρ, a, M)
    results = solve_model(mip, params)

    return results
end

# ==============================================================================
# Maximum dimensions
function get_dimensions(cand, exist, lines, demands)
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

# ==============================================================================
# Sets
function define_sets(dimensions, cand, exist, lines, demands, ref)
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

# ==============================================================================
# Parameters
function define_parameters(cand, exist, lines, demands)
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

# ==============================================================================
# Model
function build_model(sets, sets_n, params, ρ, a, M, optimizer_mip = Gurobi.Optimizer)
    mip = Model(optimizer_mip)
    set_silent(mip)

    # ==============================================================================
    # Sets and indices
    C = sets[:C]
    G = sets[:G]
    D = sets[:D]
    L = sets[:L]
    N = sets[:N]
    Nr = sets[:Nr]
    T = sets[:T]
    O = sets[:O]
    Q = sets[:Q]

    r = sets[:r]
    s = sets[:s]
    ng = sets[:ng]
    nc = sets[:nc]
    Ω_C = sets_n[:Ω_C]
    Ω_D = sets_n[:Ω_D]
    Ω_E = sets_n[:Ω_E]

    B = params[:B]
    F = params[:F]
    PD = params[:PD]
    
    C_C = params[:C_C]
    I_C_A = params[:I_C_A]
    P_Opt = params[:P_Opt]
    C_E = params[:C_E]
    PEmax = params[:PEmax]

    # ==============================================================================
    # Variables
    @variable(mip, pCmax[c in C, t in T])
    @variable(mip, pE[g in G, o in O, t in T])
    @variable(mip, pC[c in C, o in O, t in T])
    @variable(mip, uOpt[c in C, q in Q, t in T], Bin)

    @variable(mip, μEmax[g in G, o in O, t in T])
    @variable(mip, μCmax[c in C, o in O, t in T])
    @variable(mip, λ[n in N, o in O, t in T])
    @variable(mip, zAux[c in C, q in Q, o in O, t in T])
    @variable(mip, zMax[c in C, q in Q, o in O, t in T])

    @variable(mip, pL[l in L, o in O, t in T])
    @variable(mip, θ[n in N, o in O, t in T])

    @variable(mip, μL[l in L, o in O, t in T])
    @variable(mip, μLMin[l in L, o in O, t in T])
    @variable(mip, μLMax[l in L, o in O, t in T])

    @variable(mip, μAmax[n in Nr, o in O, t in T])
    @variable(mip, μAmin[n in Nr, o in O, t in T])
    @variable(mip, μAref[n in ref, o in O, t in T])

    # ==============================================================================
    # Constraints
    @constraint(mip, [c in C, t in T], sum(uOpt[c,q,t]*P_Opt[c][t][q] for q in Q) == 
                pCmax[c,t]
    )
    @constraint(mip, [c in C, t in T], sum(uOpt[c,q,t] for q in Q) == 1)
    @constraint(mip, [n in N, o in O, t in T], 
                sum(pE[g,o,t] for g in Ω_E[n] if g!=0) + 
                sum(pC[c,o,t] for c in Ω_C[n] if c!=0) - 
                sum(pL[l,o,t] for l in L if s[l]==n) + 
                sum(pL[l,o,t] for l in L if r[l]==n)
                == sum(PD[d][t][o] for d in Ω_D[n] if d!=0)
    )
    @constraint(mip, [l in L, o in O, t in T], 
                pL[l,o,t] == B[l]*(θ[r[l],o,t] - θ[s[l],o,t])
    )
    @constraint(mip, [l in L, o in O, t in T], -F[l] <= pL[l,o,t] <= F[l])
    @constraint(mip, [g in G, o in O, t in T], 0 <= pE[g,o,t] <= PEmax[g])
    @constraint(mip, [c in C, o in O, t in T], 0 <= pC[c,o,t])
    @constraint(mip, [c in C, o in O, t in T], pC[c,o,t] <= 
                sum(pCmax[c,τ] for τ in 1:t)
    )
    @constraint(mip, [n in N, o in O, t in T], -pi <= θ[n,o,t] <= pi)
    @constraint(mip, [n in ref, o in O, t in T], θ[n,o,t] == 0)
    @constraint(mip, [g in G, o in O, t in T], C_E[g][t] - 
                λ[ng[g],o,t] + μEmax[g,o,t] >= 0
    )
    @constraint(mip, [c in C, o in O, t in T], C_C[c][t] - 
                λ[nc[c],o,t] + μCmax[c,o,t] >= 0
    )
    @constraint(mip, [l in L, o in O, t in T], λ[s[l],o,t] - λ[r[l],o,t] - 
                μL[l,o,t] + μLMax[l,o,t] - μLMin[l,o,t] == 0
    )
    @constraint(mip, [n in Nr, o in O, t in T], 
                sum(B[l]*μL[l,o,t] for l in L if s[l]==n) - 
                sum(B[l]*μL[l,o,t] for l in L if r[l]==n) + μAmax[n,o,t] - 
                μAmin[n,o,t] == 0
    )
    @constraint(mip, [n in ref, o in O, t in T], 
                sum(B[l]*μL[l,o,t] for l in L if s[l]==n) - 
                sum(B[l]*μL[l,o,t] for l in L if r[l]==n) +
                μAref[n,o,t] == 0
    )
    @constraint(mip, [g in G, o in O, t in T], μEmax[g,o,t] >= 0)
    @constraint(mip, [c in C, o in O, t in T], μCmax[c,o,t] >= 0)

    @constraint(mip, [l in L, o in O, t in T], μLMin[l,o,t] >= 0)
    @constraint(mip, [l in L, o in O, t in T], μLMax[l,o,t] >= 0)

    @constraint(mip, [n in Nr, o in O, t in T], μAmax[n,o,t] >= 0)
    @constraint(mip, [n in Nr, o in O, t in T], μAmin[n,o,t] >= 0)

    @constraint(mip, [o in O, t in T], sum(C_E[g][t]*pE[g,o,t] for g in G) + 
                sum(C_C[c][t]*pC[c,o,t] for c in C) == 
                sum(λ[n,o,t]*sum(PD[d][t][o] for d in Ω_D[n] if d!=0) for n in N) - 
                sum(μEmax[g,o,t]*PEmax[g] for g in G) - 
                sum(sum(zAux[c,q,o,t] for q in Q) for c in C) - 
                sum((μLMax[l,o,t] + μLMin[l,o,t])*F[l] for l in L) - 
                sum((μAmax[n,o,t] + μAmin[n,o,t])*pi for n in Nr)
    )

    @constraint(mip, [c in C, q in Q, o in O, t in T], zAux[c,q,o,t] == 
                μCmax[c,o,t]*P_Opt[c][t][q] - zMax[c,q,o,t]
    )

    @constraint(mip, [c in C, q in Q, o in O, t in T], 0 <= zAux[c,q,o,t])
    @constraint(mip, [c in C, q in Q, o in O, t in T], zAux[c,q,o,t] <= 
                uOpt[c,q,t]*M
    )
    @constraint(mip, [c in C, q in Q, o in O, t in T], 0 <= zMax[c,q,o,t])
    @constraint(mip, [c in C, q in Q, o in O, t in T], 
                zMax[c,q,o,t] <= (1 - uOpt[c,q,t])*M
    )

    # ==============================================================================
    # Objective
    gen_cost = sum(sum(ρ[t][o]*(sum(C_E[g][t]*pE[g,o,t] for g in G) + 
    sum(C_C[c][t]*pC[c,o,t] for c in C)) for o in O) for t in T)

    annual_inv = sum(a[t]*sum(I_C_A[c][t]*pCmax[c,t] for c in C) for t in T)
    @objective(mip, Min, gen_cost + annual_inv)

    return mip
end
