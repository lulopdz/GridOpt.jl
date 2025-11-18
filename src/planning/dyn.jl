# ==============================================================================
# Deterministic Dynamic Single-Node GEP

# The approach is deterministic, meaning it does not account 
# for uncertainties in the input data.
# It is dynamic, considering multiple time periods for planning.
# The model is single-node, not considering network constraints.

# ==============================================================================
# Packages
using JuMP, Gurobi

# ==============================================================================
# Include utility functions and test data for planning
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/data/planning/test.jl")

Sb = 1.0  # MVA base power

cand, exist, demands = dynamic_format(cand, exist, demands)

# Main function to run the entire process
function dyn(optimizer_mip = Gurobi.Optimizer)
    dims = get_dimensions(cand, exist, demands)
    sets = define_sets(dims)
    params = define_parameters(cand, exist, demands)
    mip = build_model_lp(sets, params, ρ, a, M, optimizer_mip)
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
        :nT => length(demands[:Load][1]),
        :nO => length(demands[:Load][1][1]),
        :nQ => length(cand[:Prod_cap][1][1]),
    )
end

# ==============================================================================
# Sets
function define_sets(dimensions)
    nC = dimensions[:nC]
    nG = dimensions[:nG]
    nD = dimensions[:nD]
    nT = dimensions[:nT]
    nO = dimensions[:nO]
    nQ = dimensions[:nQ]
    
    sets = Dict(
        :C => 1:nC,                                # Candidate generating units
        :G => 1:nG,                                # Existing generating units
        :D => 1:nD,                                # Demands
        :T => 1:nT,                                # Time periods
        :O => 1:nO,                                # Operating conditions
        :Q => 1:nQ,                                # Generation capacity blocks
    )
    
    return sets
end

# ==============================================================================
# Parameters
function define_parameters(cand, exist, demands)
    return Dict(
        :PD => demands[:Load],                     # Load of demand d [p.u.]
        :I_C_A => cand[:Inv_cost]/1e3,                 # Annualized inv cost of candidate generating unit c [k$/MW]
        :C_E => exist[:Prod_cost]/1e3,                 # Production cost of existing generating unit g [k$/MWh]
        :F_E => exist[:Fixed_cost]/1e3,                # Fixed O&M cost of existing generating unit g [k$/MW]
        :C_C => cand[:Prod_cost]/1e3,                  # Production cost of candidate generating unit c [k$/MWh]
        :F_C => cand[:Fixed_cost]/1e3,                 # Fixed O&M cost of candidate generating unit c [k$/MW]
        :P_Opt => cand[:Prod_cap],                 # Production capacity of inv option q of gen unit c [p.u.]
        :PEmax => exist[:Max_cap],                 # Production capacity of existing generating unit g [p.u.]
        :EM_C => cand[:Emissions],                 # [tonCO2 per MWh]
        :EM_E => exist[:Emissions],                # [tonCO2 per MWh]
        :HR_E => exist[:Heat_rate],                # [MBtu/MWh] optional
        :HR_C => cand[:Heat_rate],                 # [MBtu/MWh] optional
        :CF_E => exist[:CF],                       # Capacity factor of existing generating unit g
        :CF_C => cand[:CF],                        # Capacity factor of candidate generating unit c
        :Pmin_E => exist[:Pmin]                    # Minimum generation of existing generating unit g [p.u.]
    )
end

function build_model(sets, params, ρ, a, M, optimizer_mip = Gurobi.Optimizer)
    mip = Model(optimizer_mip)
    # set_silent(mip)

    # ==========================================================================
    # Sets and indices
    C = sets[:C]
    G = sets[:G]
    D = sets[:D]
    T = sets[:T]
    O = sets[:O]
    Q = sets[:Q]

    PD = params[:PD]
    
    C_C = params[:C_C]
    I_C_A = params[:I_C_A]
    P_Opt = params[:P_Opt]
    C_E = params[:C_E]
    PEmax = params[:PEmax]

    EM_C = params[:EM_C]
    EM_E = params[:EM_E]
    F_E = params[:F_E]
    F_C = params[:F_C]
    CF_E = params[:CF_E]
    CF_C = params[:CF_C]
    Pmin_E = params[:Pmin_E]

    # ==========================================================================
    # Variables
    @variable(mip, pCmax[c in C, t in T])
    @variable(mip, pE[g in G, o in O, t in T])
    @variable(mip, pC[c in C, o in O, t in T])

    @variable(mip, μEmax[g in G, o in O, t in T])
    @variable(mip, μCmax[c in C, o in O, t in T])

    @variable(mip, λ[o in O, t in T])

    # @variable(mip, uOpt[c in C, q in Q, t in T], Bin)
    @variable(mip, 0 <= uOpt[c in C, q in Q, t in T] <= 1)

    @variable(mip, zAux[c in C, q in Q, o in O, t in T])
    @variable(mip, zMax[c in C, q in Q, o in O, t in T])

    # Emissions 
    @variable(mip, em_c[c in C, o in O, t in T])
    @variable(mip, em_e[g in G, o in O, t in T])
    @variable(mip, em[o in O, t in T])

    # ==========================================================================
    # Constraints
    @constraint(mip, [c in C, t in T], sum(uOpt[c,q,t]*P_Opt[c][t][q] for q in Q) == 
                pCmax[c,t])
    @constraint(mip, [c in C, t in T], sum(pCmax[c,τ] for τ in 1:t) <= P_Opt[c][t][end])

    @constraint(mip, [c in C, t in T], sum(uOpt[c,q,t] for q in Q) == 1)

    @constraint(mip, [o in O, t in T], sum(pE[g,o,t] for g in G) + 
                sum(pC[c,o,t] for c in C) == sum(PD[d][t][o] for d in D))

    @constraint(mip, [g in G, o in O, t in T], Pmin_E[g]*PEmax[g] <= pE[g,o,t] <= CF_E[g][t][o]*PEmax[g])

    @constraint(mip, [c in C, o in O, t in T], 0 <= pC[c,o,t])
    @constraint(mip, [c in C, o in O, t in T], pC[c,o,t] <= 
                sum(pCmax[c,τ] for τ in 1:t)*CF_C[c][t][o])

    @constraint(mip, [g in G, o in O, t in T], 
                C_E[g][t] - λ[o,t] + μEmax[g,o,t] >= 0)
    @constraint(mip, [c in C, o in O, t in T], 
                C_C[c][t] - λ[o,t] + μCmax[c,o,t] >= 0)

    @constraint(mip, [g in G, o in O, t in T], μEmax[g,o,t] >= 0)
    @constraint(mip, [c in C, o in O, t in T], μCmax[c,o,t] >= 0)

    @constraint(mip, [o in O, t in T], sum(C_E[g][t]*pE[g,o,t] for g in G) + 
                sum(C_C[c][t]*pC[c,o,t] for c in C) == 
                λ[o,t]*sum(PD[d][t][o] for d in D) - 
                sum(μEmax[g,o,t]*PEmax[g] for g in G) - 
                sum(zAux[c,q,o,t] for q in Q, c in C))

    @constraint(mip, [c in C, q in Q, o in O, t in T], zAux[c,q,o,t] == 
                μCmax[c,o,t]*P_Opt[c][t][q] - zMax[c,q,o,t])

    @constraint(mip, [c in C, q in Q, o in O, t in T], 0 <= zAux[c,q,o,t])
    @constraint(mip, [c in C, q in Q, o in O, t in T], 
                zAux[c,q,o,t] <= uOpt[c,q,t]*M)
    @constraint(mip, [c in C, q in Q, o in O, t in T], 0 <= zMax[c,q,o,t])
    @constraint(mip, [c in C, q in Q, o in O, t in T], 
                zMax[c,q,o,t] <= (1 - uOpt[c,q,t])*M)

    # Emissions constraints
    @constraint(mip, [c in C, o in O, t in T], em_c[c,o,t] == Sb*EM_C[c]*pC[c,o,t]) # Emissions from candidate units (tCO2eq)
    @constraint(mip, [g in G, o in O, t in T], em_e[g,o,t] == Sb*EM_E[g]*pE[g,o,t]) # Emissions from existing units (tCO2eq)

    @constraint(mip, [o in O, t in T], em[o,t] == sum(em_e[g,o,t] for g in G) 
                + sum(em_c[c,o,t] for c in C))

    # @constraint(mip, [o in O], em[o, last(T)] <= 0)
    # ==========================================================================
    # Generation cost
    gen_cost = Sb*sum(
        ρ[t][o] * (
            sum(C_E[g][t] * pE[g,o,t] for g in G) +
            sum(C_C[c][t] * pC[c,o,t] for c in C)
        ) for o in O, t in T
    )

    # Investment cost
    annual_inv = Sb*sum(
        a[t] * sum(
            I_C_A[c][t] * sum(pCmax[c,τ] for τ in 1:t) 
            for c in C
        ) for t in T
    )
    # Fixed O&M
    fixed_cost = Sb*(
        sum(a[t] * sum(F_E[g] * PEmax[g] for g in G) for t in T) +
        sum(a[t] * sum(F_C[c] * sum(pCmax[c,τ] for τ in 1:t) for c in C) for t in T)
    )
    # Emissions (with Sbase inside em_c/em_e constraints)
    carbon_cost = sum(
        c_tax[t]/1e3 * ρ[t][o] * em[o,t] 
        for o in O, t in T
    )
    
    # Objective
    obj = gen_cost + annual_inv + carbon_cost + fixed_cost

    @objective(mip, Min, obj)

    return mip 
end

function build_model_lp(sets, params, ρ, a, M, optimizer_mip = Gurobi.Optimizer)
    mip = Model(optimizer_mip)

    # ==============================================================
    # Sets
    C = sets[:C]
    G = sets[:G]
    D = sets[:D]
    T = sets[:T]
    O = sets[:O]

    # ==============================================================
    # Parameters
    PD    = params[:PD]       # demand[d][t][o] in MW before normalization
    C_C   = params[:C_C]      # $/MWh
    C_E   = params[:C_E]      # $/MWh
    I_C_A = params[:I_C_A]    # $/MW-year
    F_E   = params[:F_E]      # $/MW-year
    F_C   = params[:F_C]      # $/MW-year
    
    P_Opt = params[:P_Opt]    # size option (not needed anymore unless useful)
    PEmax = params[:PEmax]    # p.u. maximum existing capacity
    Pmin_E = params[:Pmin_E]  # p.u. minimum existing capacity
    CF_E  = params[:CF_E]     # cap factor existing
    CF_C  = params[:CF_C]     # cap factor candidates
    EM_C  = params[:EM_C]     # tCO₂/MWh
    EM_E  = params[:EM_E]     # tCO₂/MWh

    # ==============================================================
    # Variables

    # investment decisions (p.u.)
    @variable(mip, pCmax[c in C, t in T] >= 0)

    # dispatch (p.u.)
    @variable(mip, pE[g in G, o in O, t in T] >= 0)
    @variable(mip, pC[c in C, o in O, t in T] >= 0)

    # emissions (tons)
    @variable(mip, em_c[c in C, o in O, t in T] >= 0)
    @variable(mip, em_e[g in G, o in O, t in T] >= 0)
    @variable(mip, em[o in O, t in T] >= 0)

    # ==============================================================
    # Constraints

    # Load balance (MW = p.u. * Sb)
    @constraint(mip, [o in O, t in T],
        sum(pE[g,o,t] for g in G) +
        sum(pC[c,o,t] for c in C)
        ==
        sum(PD[d][t][o] for d in D)
    )

    # Existing generator dispatch limits
    @constraint(mip, [g in G, o in O, t in T],
        Pmin_E[g]*PEmax[g] <= pE[g,o,t] <= PEmax[g] * CF_E[g][t][o]
    )

    @constraint(mip, [c in C, t in T], sum(pCmax[c,τ] for τ in 1:t) <= P_Opt[c][t][end])

    # Candidate generator dispatch limits
    @constraint(mip, [c in C, o in O, t in T],
        pC[c,o,t] <= sum(pCmax[c,τ] for τ in 1:t) * CF_C[c][t][o]
    )

    # Emissions (tons)
    @constraint(mip, [c in C, o in O, t in T],
        em_c[c,o,t] == EM_C[c] * Sb * pC[c,o,t]
    )
    @constraint(mip, [g in G, o in O, t in T],
        em_e[g,o,t] == EM_E[g] * Sb * pE[g,o,t]
    )

    @constraint(mip, [o in O, t in T],
        em[o,t] == sum(em_c[c,o,t] for c in C) + sum(em_e[g,o,t] for g in G)
    )

    @constraint(mip, [o in O], em[o, last(T)] <= 0)

    # ==============================================================
    # Objective Function (all CAD)

    # 1. Generation cost
    gen_cost =
        Sb * sum(
            ρ[t][o] * (
                sum(C_E[g][t] * pE[g,o,t] for g in G) +
                sum(C_C[c][t] * pC[c,o,t] for c in C)
            )
            for o in O, t in T
        )

    # 2. Annualized investment cost
    annual_inv =
        Sb * sum(
            a[t] * sum(I_C_A[c][t] * sum(pCmax[c,τ] for τ in 1:t) for c in C)
            for t in T
        )

    # 3. Fixed O&M
    fixed_cost =
        Sb * (
            sum(a[t] * sum(F_E[g] * PEmax[g] for g in G) for t in T) +
            sum(a[t] * sum(F_C[c] * sum(pCmax[c,τ] for τ in 1:t) for c in C) for t in T)
        )

    # 4. Carbon cost ($/tCO₂ * tons)
    carbon_cost =
        sum(c_tax[t]/1e3 * ρ[t][o] * em[o,t] for o in O, t in T)

    # carbon_cost = 0.0  # No carbon cost in LP version

    # Final objective
    @objective(mip, Min, gen_cost + annual_inv + fixed_cost + carbon_cost)

    return mip
end
