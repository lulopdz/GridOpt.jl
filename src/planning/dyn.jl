# ==============================================================================
# Deterministic Dynamic Single-Node GEP

# The approach is deterministic, meaning it does not account 
# for uncertainties in the input data.
# It is dynamic, considering multiple time periods for planning.
# The model is single-node, not considering network constraints.

# ==============================================================================
# Packages
using JuMP, Gurobi, Ipopt

# ==============================================================================
# Include utility functions and test data for planning
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/data/planning/test.jl")

cand, exist, demands = dynamic_format(cand, exist, demands)

# ==============================================================================
# Maximum dimensions
nC = length(cand[:ID])
nG = length(exist[:ID]) 
nD = length(demands[:ID])
nT = length(demands[:Load][1])
nO = length(demands[:Load][1][1])
nQ = length(cand[:Prod_cap][1][1])

# Indices
C = 1:nC                                # Candidate generating units
G = 1:nG                                # Existing generating units
D = 1:nD                                # Demands
T = 1:nT                                # Time periods
O = 1:nO                                # Operating conditions
Q = 1:nQ                                # Generation capacity blockss

# ==============================================================================
# Parameters
PD = demands[:Load]                     # Load of demand d [MW]

C_C = cand[:Prod_cost]                  # Production cost of candidate generating unit c [$/MWh]
I_C_A = cand[:Inv_cost]                 # Annualized inv cost of candidate generating unit c [$/MW]
P_Opt = cand[:Prod_cap]                 # Production capacity of inv option q of gen unit c [MW]

C_E = exist[:Prod_cost]                 # Production cost of existing generating unit g [$/MWh]
PEmax = exist[:Max_cap]                 # Production capacity of existing generating unit g [MW]

# ==============================================================================
# Model
optimizer_mip = Gurobi.Optimizer
mip = Model(optimizer_mip)

# Variables
@variable(mip, pCmax[c in C, t in T])
@variable(mip, pE[g in G, o in O, t in T])
@variable(mip, pC[c in C, o in O, t in T])

@variable(mip, μEmax[g in G, o in O, t in T])
@variable(mip, μCmax[c in C, o in O, t in T])

@variable(mip, λ[o in O, t in T])

@variable(mip, uOpt[c in C, q in Q, t in T], Bin)

@variable(mip, zAux[c in C, q in Q, o in O, t in T])
@variable(mip, zMax[c in C, q in Q, o in O, t in T])

# Constraints
@constraint(mip, [c in C, t in T], sum(uOpt[c,q,t]*P_Opt[c][t][q] for q in Q) == 
            pCmax[c,t])
@constraint(mip, [c in C, t in T], sum(uOpt[c,q,t] for q in Q) == 1)

@constraint(mip, [o in O, t in T], sum(pE[g,o,t] for g in G) + 
            sum(pC[c,o,t] for c in C) == sum(PD[d][t][o] for d in D))

@constraint(mip, [g in G, o in O, t in T], 0 <= pE[g,o,t] <= PEmax[g])

@constraint(mip, [c in C, o in O, t in T], 0 <= pC[c,o,t])
@constraint(mip, [c in C, o in O, t in T], pC[c,o,t] <= 
            sum(pCmax[c,τ] for τ in 1:t))

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


# Objective
gen_cost = sum(sum(ρ[t][o]*(sum(C_E[g][t]*pE[g,o,t] for g in G) + 
                sum(C_C[c][t]*pC[c,o,t] for c in C)) for o in O) for t in T)

annual_inv = sum(a[t]*sum(I_C_A[c][t]*pCmax[c,t] for c in C) for t in T)

@objective(mip, Min, gen_cost + annual_inv)

optimize!(mip)

println(value.(pCmax))

# ==============================================================================
# Results
for t in T, o in O
    println("========================================")
    println("Time period: ", t, " | Operating condition: ", o)
    println("----------------------------------------")
    println("Production power (Candidate): ", sum(value.(pC)[:, o, t]))
    println("Production power (Existing): ", sum(value.(pE)[:, o, t]))
    println("Total Demand: ", sum(PD[d][t][o] for d in D))
    println(" ")
end

println("========================================")
println("Maximum Production Power (Candidate):")
for t in T
    println("----------------------------------------")
    println("Time period: ", t)
    for c in C
        capacity = value(pCmax[c, t])
        println("  Candidate: ", c, " | Capacity: ", capacity)
    end
end
println("Total Capacity: ", sum(value.(pCmax)))
println(" ")

println("========================================")
println("Generation Cost: ", value(gen_cost))
println("Annual Investment: ", value(annual_inv))
println("Objective Value: ", objective_value(mip))

# ==============================================================================
# Load shedding penalty (set high to discourage load shedding)
C_s = 10000  # Penalty cost for shedding load [$/MW]

# Post-Solution Evaluation with Network Constraints and Load Shedding
results = []

include(pf * "/GridOpt.jl/data/planning/test.jl")

# ==============================================================================
# Maximum dimensions
nL = length(lines[:ID])
nN = maximum([maximum(lines[:From]) maximum(lines[:To])])
nT = length(demands[:Load][1])
nO = length(demands[:Load][1][1])
ref = 1                                 # Slack node

# Sets
L = 1:nL                                # Transmission lines
N = 1:nN                                # Nodes
Nr = setdiff(N, ref)                    # Nodes without slack node
T = 1:nT                                # Time periods
O = 1:nO                                # Operating conditions

r = lines[:To]                          # Receiving-end node of transmission line
s = lines[:From]                        # Sending-end node of transmission line
ng = exist[:Node]                       # Node of existing generating unit g
nc = cand[:Node]                        # Node of candidate generating unit c

Ω_C = map_nodes(cand[:ID], cand[:Node], N)             # Candidate generating units located at node n
Ω_D = map_nodes(demands[:ID], demands[:Node], N)       # Demands located at node n
Ω_E = map_nodes(exist[:ID], exist[:Node], N)           # Existing generating units located at node n

# ==============================================================================
# Parameters
B = lines[:Susceptance]                 # Susceptance of transmission line [S]
F = lines[:Capacity]                    # Capacity of transmission line [MW]
PD = demands[:Load]                     # Load of demand d [MW]

for t in T, o in O
    market = Model(Gurobi.Optimizer)  # Use the appropriate solver

    # Variables
    @variable(market, 0 <= pE[g in G] <= PEmax[g])  
    @variable(market, 0 <= pC[c in C] <= sum(value(pCmax[c,τ]) for τ in 1:t))  # Candidate generation (fixed by plan)
    @variable(market, 0 <= sD[d in D])                        # Load shedding for demand points
    @variable(market, θ[n in N]) 
    @variable(market, -F[l] <= pL[l in L] <= F[l]) 

    # Market Clearing Constraint
    @constraint(market, [n in N],
        sum(pE[g] for g in Ω_E[n] if g != 0) + sum(pC[c] for c in Ω_C[n] if c != 0) -
        sum(pL[l] for l in L if s[l] == n) + sum(pL[l] for l in L if r[l] == n) + sum(sD[d] for d in Ω_D[n] if d != 0)
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
    result = Dict(
        "Time Period" => t,
        "Operating Condition" => o,
        "Generation Cost" => objective_value(market),
        "Total Existing Gen (MW)" => sum(value(pE[g]) for g in G),
        "Total Candidate Gen (MW)" => sum(value(pC[c]) for c in C),
        "Total Demand (MW)" => sum(PD[d][t][o] for d in D),
        "Total Load Shed (MW)" => sum(value(sD[d]) for d in D),
        "Load Shedding Cost (\$)" => sum(C_s * value(sD[d]) for d in D),
        "Congestion" => any(abs(value(pL[l])) >= F[l] for l in L) ? "Yes" : "No",
        "Status" => termination_status(market)
    )
    push!(results, result)
end