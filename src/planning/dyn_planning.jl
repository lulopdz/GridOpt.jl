# ==============================================================================
# Deterministic Single-Node Static GEP
using JuMP, Gurobi, Ipopt

# Functions
function map_nodes(gens::Vector{Int}, nodes::Vector{Int}, node_range::UnitRange{Int})
     node_gens = Dict{Int, Vector{Int}}(node => Int[] for node in node_range)
     # Populate the dictionary
     for (gen, node) in zip(gens, nodes)
         push!(node_gens[node], gen)
     end
 
     return node_gens
end

# ==============================================================================
# Notation
cand = Dict(
    :ID   => [1, 2],
    :Node => [2, 2],

    # For each candidate i, store a vector [cost_in_t_1, cost_in_t_2, ...]
    :Prod_cost  => [
        [25.0, 25.0],
        [25.0, 25.0],
    ],

    :Inv_cost   => [
        [700000, 700000],
        [700000, 700000],
    ],

    :Prod_cap   => [
        [[0 100 200 300 400], [0 100 200 300 400]],
        [[0 100 200 300 400], [0 100 200 300 400]],
    ]
)

exist = Dict(
    :ID   => [1],
    :Node => [1],
    :Max_cap => [400],

    # For each existing generator i, a vector [cost_in_t1, cost_in_t2] 
    :Prod_cost => [
        [35.0, 35.0],
    ],   
)

lines = Dict(
    :ID          => [1],              # List of line IDs
    :From        => [1],              # Sending (from) node
    :To          => [2],              # Receiving (to) node
    :Susceptance => [500.0],          # Susceptance of transmission line [S]
    :Capacity    => [200.0],          # Capacity of transmission line [MW]
)

demands = Dict(
    :ID   => [1],
    :Node => [2],

    :Load => [
        [
            [246.5 467.5],  # t=1 => o=1,2
            [290    550]    # t=2 => o=1,2
        ]
    ]
)
# ==============================================================================
# Notation
C = length(cand[:ID])
G = length(exist[:ID]) 
L = length(lines[:ID])
N = maximum([maximum(lines[:From]) maximum(lines[:To])])
D = length(demands[:ID])
O = 2
T = 2 
Q = 5

# Indices
C = 1:C         # Candidate generating units
G = 1:G         # Existing generating units
D = 1:D         # Demands
L = 1:L         # Transmission lines
N = 1:N         # Nodes
ref = 1         # Slack node
Nr = N[2:end]   # Nodes
O = 1:O         # Operating conditions
T = 1:T         # Time periods
Q = 1:Q         # Generation capacity blocks

# # Parameters
C_C = cand[:Prod_cost]                  # Production cost of candidate generating unit c [$/MWh]
I_C_A = cand[:Inv_cost]                 # Annualized inv cost of candidate generating unit c [$/MW]
P_Opt = cand[:Prod_cap]                 # Production capacity of inv option q of gen unit c [MW]

C_E = exist[:Prod_cost]                 # Production cost of existing generating unit g [$/MWh]
PEmax = exist[:Max_cap]                 # Production capacity of existing generating unit g [MW]

PD = demands[:Load]                     # Load of demand d [MW]

# Economic Parameters
a = [0.2, 0.1]                          # Amortization rate [%]
ρ = [
     [6000 2760], # T = 1, o = 1,2
     [6000 2760]  # T = 2, o = 1,2
]     

M = 1e10          # Big number

# # Variables 
# # Binary 
# u_cq            # Binary variable 

# # Continuous
# pC              # Power produced by candidate generating unit c [MW]
# pCmax           # Capacity of candidate generating unit c [MW]
# pE              # Power produced by existing generating unit g [MW]
# pL              # Power flow through transmission line [MW]
# θ               # Voltage angle at node n [rad]


# ==============================================================================
# Model
optimizer_mip = HiGHS.Optimizer
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


for t in T, o in O 
     println("Time period: ", t, " Operating condition: ", o)
     println("Production power: ", sum(value.(pC)[:,o,t]))
     println("Production power E: ", sum(value.(pE)[:,o,t]))
     println("Demand: ", sum(PD[d][t][o] for d in D))
end

println(value.(pCmax))