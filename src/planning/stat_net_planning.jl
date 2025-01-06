# ==============================================================================
# Deterministic Network-Constrained Static GEP
using JuMP, Gurobi, Ipopt, HiGHS

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
   :Prod_cost  => [25, 55],
   :Inv_cost   => [70000, 70000],

   :Prod_cap   => [
       [0 100 200 300 400],
       [0 100 200 300 400],
   ]
)

exist = Dict(
   :ID   => [1],
   :Node => [1],
   :Max_cap => [400],
   :Prod_cost => [35]
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
       [290, 550]
   ]
)

# Notation
C = length(cand[:ID])
D = length(demands[:ID])
G = length(exist[:ID]) 
L = length(lines[:ID])
N = maximum([maximum(lines[:From]) maximum(lines[:To])])
O = 2
Q = 5

# Indices
C = 1:C         # Candidate generating units
D = 1:D         # Demands
G = 1:G         # Existing generating units
L = 1:L         # Transmission lines
N = 1:N         # Nodes
ref = 1         # Slack node
Nr = N[2:end]   # Nodes
O = 1:O         # Operating conditions
Q = 1:Q         # Generation capacity blocks

# Sets 
r = lines[:To]                          # Receiving-end node of transmission line
s = lines[:From]                        # Sending-end node of transmission line
ng = exist[:Node]                      # Node of existing generating unit g
nc = cand[:Node]                       # Node of candidate generating unit c

Ω_C = map_nodes(cand[:ID], cand[:Node], N)             # Candidate generating units located at node n
Ω_D = map_nodes(demands[:ID], demands[:Node], N)       # Demands located at node n
Ω_E = map_nodes(exist[:ID], exist[:Node], N)           # Existing generating units located at node n

# Parameters
B = lines[:Susceptance]                 # Susceptance of transmission line [S]
F = lines[:Capacity]                    # Capacity of transmission line [MW]
PD = demands[:Load]                     # Load of demand d [MW]

# # Parameters
C_C = cand[:Prod_cost]          # Production cost of candidate generating unit c [$/MWh]
C_E = exist[:Prod_cost]                 # Production cost of existing generating unit g [$/MWh]
I_C_A = cand[:Inv_cost]     # Annualized inv cost of candidate generating unit c [$/MW]
P_Opt = cand[:Prod_cap]  # Production capacity of inv option q of gen unit c [MW]
PD = demands[:Load]  # Load of demand d [MW]
PEmax = exist[:Max_cap]       # Production capacity of existing generating unit g [MW]

# ϕ               # Probability of scenario ω [pu]
ρ = [6000, 2760]  # Weight of operating condition o [h]
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

annual_inv = sum(I_C_A[c]*pCmax[c] for c in C)
@objective(mip, Min, gen_cost + annual_inv)

optimize!(mip)

for o in O 
    println("Operating condition: ", o)
    println("Power new: ", sum(value.(pC)[:,o]))
    println("Power old: ", sum(value.(pE)[:,o]))
    println("Demand: ", sum(PD[d][o] for d in D))
end

println(value.(pCmax))
