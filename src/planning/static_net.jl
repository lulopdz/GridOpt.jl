# ==============================================================================
# Deterministic Static Network-Constrained GEP

# The approach is deterministic, meaning it does not account 
# for uncertainties in the input data.
# It is static, considering a single time period for planning.
# The model is network-constrained, taking into account 
# the limitations and capacities of the electrical network.

# ==============================================================================
# Packages
using JuMP, Gurobi, Ipopt

# ==============================================================================
# Include utility functions and test data for planning
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/data/planning/test.jl")

cand, exist, lines, demands = static_net_format(cand, exist, lines, demands)

# ==============================================================================
# Maximum dimensions
nC = length(cand[:ID])
nG = length(exist[:ID]) 
nD = length(demands[:ID])
nL = length(lines[:ID])
nN = maximum([maximum(lines[:From]) maximum(lines[:To])])
nO = length(demands[:Load][1])
nQ = length(cand[:Prod_cap][1])
ref = 1                                 # Slack node

# Sets
C = 1:nC                                # Candidate generating units
G = 1:nG                                # Existing generating units
D = 1:nD                                # Demands
L = 1:nL                                # Transmission lines
N = 1:nN                                # Nodes
Nr = setdiff(N, ref)                    # Nodes without slack node
O = 1:nO                                # Operating conditions
Q = 1:nQ                                # Generation capacity blocks

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

C_C = cand[:Prod_cost]                  # Production cost of candidate generating unit c [$/MWh]
I_C_A = cand[:Inv_cost]                 # Annualized inv cost of candidate generating unit c [$/MW]
P_Opt = cand[:Prod_cap]                 # Production capacity of inv option q of gen unit c [MW]

C_E = exist[:Prod_cost]                 # Production cost of existing generating unit g [$/MWh]
PEmax = exist[:Max_cap]                 # Production capacity of existing generating unit g [MW]

# Economic Parameters
a = a[1]/2                              # Annualization factor [1/h]
ρ = ρ[end]                              # Weight of operating condition o [h]

# ==============================================================================
# Model
optimizer_mip = Gurobi.Optimizer
mip = Model(optimizer_mip)

# Variables
@variable(mip, pCmax[c in C])
@variable(mip, pE[g in G, o in O])
@variable(mip, pC[c in C, o in O])
@variable(mip, μEmax[g in G, o in O])
@variable(mip, μCmax[c in C, o in O])
@variable(mip, λ[n in N, o in O])
@variable(mip, uOpt[c in C, q in Q], Bin)
@variable(mip, zAux[c in C, q in Q, o in O])
@variable(mip, zMax[c in C, q in Q, o in O])
@variable(mip, pL[l in L, o in O])
@variable(mip, θ[n in N, o in O])

@variable(mip, μL[l in L, o in O])
@variable(mip, μLMin[l in L, o in O])
@variable(mip, μLMax[l in L, o in O])

@variable(mip, μAmax[n in Nr, o in O])
@variable(mip, μAmin[n in Nr, o in O])
@variable(mip, μAref[n in ref, o in O])


# Constraints
@constraint(mip, [c in C], sum(uOpt[c,q]*P_Opt[c][q] for q in Q) == 
            pCmax[c]
)
@constraint(mip, [c in C], sum(uOpt[c,q] for q in Q) == 1)

@constraint(mip, [n in N, o in O], sum(pE[g,o] for g in Ω_E[n] if g!=0) + 
            sum(pC[c,o] for c in Ω_C[n] if c!=0) - sum(pL[l,o] for l in L if s[l]==n) + 
            sum(pL[l,o] for l in L if r[l]==n)
            == sum(PD[d][o] for d in Ω_D[n] if d!=0)
)

@constraint(mip, [l in L, o in O], pL[l,o] == B[l]*(θ[r[l],o] - θ[s[l],o]))
@constraint(mip, [l in L, o in O], -F[l] <= pL[l,o] <= F[l])

@constraint(mip, [g in G, o in O], 0 <= pE[g,o] <= PEmax[g])
@constraint(mip, [c in C, o in O], 0 <= pC[c,o])
@constraint(mip, [c in C, o in O], pC[c,o] <= pCmax[c])

@constraint(mip, [n in N, o in O], -pi <= θ[n,o] <= pi)
@constraint(mip, [n in ref, o in O], θ[n,o] == 0)

@constraint(mip, [g in G, o in O], C_E[g] - λ[ng[g],o] + μEmax[g,o] >= 0)
@constraint(mip, [c in C, o in O], C_C[c] - λ[nc[c],o] + μCmax[c,o] >= 0)

@constraint(mip, [l in L, o in O], λ[s[l],o] - λ[r[l],o] - μL[l,o] + 
            μLMax[l,o] - μLMin[l,o] == 0
)

@constraint(mip, [n in Nr, o in O], sum(B[l]*μL[l,o] for l in L if s[l]==n) - 
            sum(B[l]*μL[l,o] for l in L if r[l]==n) + μAmax[n,o] - 
            μAmin[n,o] == 0
)

@constraint(mip, [n in ref, o in O], sum(B[l]*μL[l,o] for l in L if s[l]==n) - 
            sum(B[l]*μL[l,o] for l in L if r[l]==n) +
            μAref[n,o] == 0
)

@constraint(mip, [g in G, o in O], μEmax[g,o] >= 0)
@constraint(mip, [c in C, o in O], μCmax[c,o] >= 0)

@constraint(mip, [l in L, o in O], μLMin[l,o] >= 0)
@constraint(mip, [l in L, o in O], μLMax[l,o] >= 0)

@constraint(mip, [n in Nr, o in O], μAmax[n,o] >= 0)
@constraint(mip, [n in Nr, o in O], μAmin[n,o] >= 0)

@constraint(mip, [o in O], sum(C_E[g]*pE[g,o] for g in G) + 
            sum(C_C[c]*pC[c,o] for c in C) == 
            sum(λ[n,o]*sum(PD[d][o] for d in Ω_D[n] if d!=0) for n in N) - 
            sum(μEmax[g,o]*PEmax[g] for g in G) - 
            sum(sum(zAux[c,q,o] for q in Q) for c in C) - 
            sum((μLMax[l,o] + μLMin[l,o])*F[l] for l in L) - 
            sum((μAmax[n,o] + μAmin[n,o])*pi for n in Nr)
)

@constraint(mip, [c in C, q in Q, o in O], zAux[c,q,o] == 
            μCmax[c,o]*P_Opt[c][q] - zMax[c,q,o]
)

@constraint(mip, [c in C, q in Q, o in O], 0 <= zAux[c,q,o])
@constraint(mip, [c in C, q in Q, o in O], zAux[c,q,o] <= uOpt[c,q]*M)
@constraint(mip, [c in C, q in Q, o in O], 0 <= zMax[c,q,o])
@constraint(mip, [c in C, q in Q, o in O], zMax[c,q,o] <= (1 - uOpt[c,q])*M)


# Objective
gen_cost = sum(ρ[o]*(sum(C_E[g]*pE[g,o] for g in G) + 
                sum(C_C[c]*pC[c,o] for c in C)) for o in O)

annual_inv = sum(a*I_C_A[c]*pCmax[c] for c in C)
@objective(mip, Min, gen_cost + annual_inv)

optimize!(mip)

for o in O 
    println("Operating condition: ", o)
    println("Power new: ", sum(value.(pC)[:,o]))
    println("Power old: ", sum(value.(pE)[:,o]))
    println("Demand: ", sum(PD[d][o] for d in D))
end

# ==============================================================================
# Results
for o in O
    println("========================================")
    println("Operating condition: ", o)
    println("----------------------------------------")
    println("Production power (Candidate): ", sum(value.(pC[:, o])))
    println("Production power (Existing): ", sum(value.(pE[:, o])))
    println("Total Demand: ", sum(PD[d][o] for d in D))
    println(" ")
end

println("========================================")
println("Maximum Production Power (Candidate):")
for c in C
    capacity = value(pCmax[c])
    println("  Candidate: ", c, " | Capacity: ", capacity)
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
nT = length(demands[:Load][1])
nO = length(demands[:Load][1][1])

# Sets
T = 1:nT                                # Time periods
O = 1:nO                                # Operating conditions

# ==============================================================================
# Parameters
PD = demands[:Load]                     # Load of demand d [MW]

for t in T, o in O
    market = Model(Gurobi.Optimizer)  # Use the appropriate solver

    # Variables
    @variable(market, 0 <= pE[g in G] <= PEmax[g])  
    @variable(market, 0 <= pC[c in C] <= value(pCmax[c]))  # Candidate generation (fixed by plan)
    @variable(market, 0 <= sD[d in D])                        # Load shedding for demand points
    @variable(market, θ[n in N]) 
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
    gen_cost = sum(C_E[g] * pE[g] for g in G) + sum(C_C[c] * pC[c] for c in C)
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