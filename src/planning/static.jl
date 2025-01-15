# ==============================================================================
# Deterministic Static Single-Node  GEP

# The approach is deterministic, meaning it does not account 
# for uncertainties in the input data.
# It is static, considering a single time period for planning.
# The model is single-node, not considering network constraints.

# ==============================================================================
# Packages
using JuMP, Gurobi, Ipopt, HiGHS

# ==============================================================================
# Include utility functions and test data for planning
# Functions
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/data/planning/test.jl")

cand, exist, demands = static_format(cand, exist, demands)

# Main function to run the entire process
function static()
    dims = get_dimensions(cand, exist, demands)
    sets = define_sets(dims)
    params = define_parameters(cand, exist, demands)
    mip = build_model(sets, params, ρ[end], a[1]/2, M, Gurobi.Optimizer)
    results = solve_model(mip, params)

    return results
end

# ==============================================================================
# Maximum dimensions
function get_dimensions(cand, exist, demands)
    return Dict(
        :nC => length(cand[:ID]),
        :nG => length(exist[:ID]),
        :nD => length(demands[:ID]),
        :nO => length(demands[:Load][1]),
        :nQ => length(cand[:Prod_cap][1])
    )
end

# ==============================================================================
# Sets
function define_sets(dimensions)
    nC = dimensions[:nC]
    nG = dimensions[:nG]
    nD = dimensions[:nD]
    nO = dimensions[:nO]
    nQ = dimensions[:nQ]
    
    sets = Dict(
        :C => 1:nC,                                # Candidate generating units
        :G => 1:nG,                                # Existing generating units
        :D => 1:nD,                                # Demands
        :O => 1:nO,                                # Operating conditions
        :Q => 1:nQ,                                # Generation capacity blocks
    )
    
    return sets
end

# ==============================================================================
# Parameters
function define_parameters(cand, exist, demands)
    return Dict(
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
function build_model(sets, params, ρ, a, M, optimizer_mip = Gurobi.Optimizer)
    mip = Model(optimizer_mip)
    set_silent(mip)

    # ==========================================================================
    # Sets and indices
    C = sets[:C]
    G = sets[:G]
    D = sets[:D]
    O = sets[:O]
    Q = sets[:Q]

    PD = params[:PD]
    
    C_C = params[:C_C]
    I_C_A = params[:I_C_A]
    P_Opt = params[:P_Opt]
    C_E = params[:C_E]
    PEmax = params[:PEmax]

    # ==========================================================================
    # Variables
    @variable(mip, pCmax[c in C])
    @variable(mip, pE[g in G, o in O])
    @variable(mip, pC[c in C, o in O])
    @variable(mip, μEmax[g in G, o in O])
    @variable(mip, μCmax[c in C, o in O])
    @variable(mip, λ[o in O])
    @variable(mip, uOpt[c in C, q in Q], Bin)
    @variable(mip, zAux[c in C, q in Q, o in O])
    @variable(mip, zMax[c in C, q in Q, o in O])
    

    # ==========================================================================
    # Constraints
    @constraint(mip, [c in C], sum(uOpt[c,q]*P_Opt[c][q] for q in Q) == 
                pCmax[c])
    @constraint(mip, [c in C], sum(uOpt[c,q] for q in Q) == 1)

    # @constraint(mip, [c in C], 0 <= pCmax[c] <= PCmax[c])
    @constraint(mip, [o in O], sum(pE[g,o] for g in G) + 
                sum(pC[c,o] for c in C) == sum(PD[d][o] for d in D))
    @constraint(mip, [g in G, o in O], 0 <= pE[g,o] <= PEmax[g])
    @constraint(mip, [c in C, o in O], 0 <= pC[c,o])
    @constraint(mip, [c in C, o in O], pC[c,o] <= pCmax[c])

    @constraint(mip, [g in G, o in O], C_E[g] - λ[o] + μEmax[g,o] >= 0)
    @constraint(mip, [c in C, o in O], C_C[c] - λ[o] + μCmax[c,o] >= 0)

    @constraint(mip, [g in G, o in O], μEmax[g,o] >= 0)
    @constraint(mip, [c in C, o in O], μCmax[c,o] >= 0)

    @constraint(mip, [o in O], sum(C_E[g]*pE[g,o] for g in G) + 
                sum(C_C[c]*pC[c,o] for c in C) == 
                λ[o]*sum(PD[d][o] for d in D) - 
                sum(μEmax[g,o]*PEmax[g] for g in G) - 
                sum(zAux[c,q,o] for q in Q, c in C))

    @constraint(mip, [c in C, q in Q, o in O], zAux[c,q,o] == 
                μCmax[c,o]*P_Opt[c][q] - zMax[c,q,o])

    @constraint(mip, [c in C, q in Q, o in O], 0 <= zAux[c,q,o])
    @constraint(mip, [c in C, q in Q, o in O], zAux[c,q,o] <= uOpt[c,q]*M)
    @constraint(mip, [c in C, q in Q, o in O], 0 <= zMax[c,q,o])
    @constraint(mip, [c in C, q in Q, o in O], zMax[c,q,o] <= (1 - uOpt[c,q])*M)

    # ==========================================================================
    # Objective
    gen_cost = sum(ρ[o]*(sum(C_E[g]*pE[g,o] for g in G) + 
                    sum(C_C[c]*pC[c,o] for c in C)) for o in O)

    annual_inv = sum(a*I_C_A[c]*pCmax[c] for c in C)
    @objective(mip, Min, gen_cost + annual_inv)

    return mip
end
