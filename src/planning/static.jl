# ==============================================================================
# Deterministic Single-Node Static GEP
using JuMP, Gurobi, Ipopt, HiGHS

# ==============================================================================
# Notation
C = 1 
D = 1 
G = 1 
L = 1 
N = 1
O = 2
T = 2 
Ω = 1
Q = 4

# Indices
C = 1:C         # Candidate generating units
D = 1:D         # Demands
G = 1:G         # Existing generating units
L = 1:L         # Transmission lines
N = 1:N         # Nodes
O = 1:O         # Operating conditions
T = 1:T         # Time periods
Ω = 1:Ω         # Scenarios
Q = 1:Q         # Generation capacity blocks

# # Sets 
# rl              # Receiving-end node of transmission line
# sleep           # Sending-end node of transmission line
# Ω_C_n           # Candidate generating units located at node n
# Ω_D_n           # Demands located at node n
# Ω_E_n           # Existing generating units located at node n

# # Parameters
# A               # Amortization rate [%]
# Bl              # Susceptance of transmission line [S]
C_C = 25          # Production cost of candidate generating unit c [$/MWh]
C_E = 35          # Production cost of existing generating unit g [$/MWh]
# C_LS            # Load-shedding cost of demand d [$/MWh]
# Fl              # Capacity of transmission line [MW]
# I_C             # Investment cost of candidate generating unit c [$/MW]
I_C_A = 70000     # Annualized inv cost of candidate generating unit c [$/MW]
PCmax = 500       # Maximum production capacity of generating unit c [MW]
P_Opt = [0, 100, 200, 300]' # Production capacity of inv option q of gen unit c [MW]
PD = [290, 550]'  # Load of demand d [MW]
PEmax = 400       # Production capacity of existing generating unit g [MW]
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
@variable(mip, λ[o in O])
@variable(mip, uOpt[c in C, q in Q], Bin)
@variable(mip, zAux[c in C, q in Q, o in O])
@variable(mip, zMax[c in C, q in Q, o in O])

# Constraints
@constraint(mip, [c in C], sum(uOpt[c,q]*P_Opt[c,q] for q in Q) == 
            pCmax[c])
@constraint(mip, [c in C], sum(uOpt[c,q] for q in Q) == 1)

@constraint(mip, [c in C], 0 <= pCmax[c] <= PCmax[c])
@constraint(mip, [o in O], sum(pE[g,o] for g in G) + 
            sum(pC[c,o] for c in C) == sum(PD[d,o] for d in D))
@constraint(mip, [g in G, o in O], 0 <= pE[g,o] <= PEmax[g])
@constraint(mip, [c in C, o in O], 0 <= pC[c,o])
@constraint(mip, [c in C, o in O], pC[c,o] <= pCmax[c])

@constraint(mip, [g in G, o in O], C_E[g] - λ[o] + μEmax[g,o] >= 0)
@constraint(mip, [c in C, o in O], C_C[c] - λ[o] + μCmax[c,o] >= 0)

@constraint(mip, [g in G, o in O], μEmax[g,o] >= 0)
@constraint(mip, [c in C, o in O], μCmax[c,o] >= 0)

@constraint(mip, [o in O], sum(C_E[g]*pE[g,o] for g in G) + 
            sum(C_C[c]*pC[c,o] for c in C) == 
            λ[o]*sum(PD[d,o] for d in D) - 
            sum(μEmax[g,o]*PEmax[g] for g in G) - 
            sum(zAux[c,q,o] for q in Q, c in C))

@constraint(mip, [c in C, q in Q, o in O], zAux[c,q,o] == 
            μCmax[c,o]*P_Opt[c,q] - zMax[c,q,o])

@constraint(mip, [c in C, q in Q, o in O], 0 <= zAux[c,q,o])
@constraint(mip, [c in C, q in Q, o in O], zAux[c,q,o] <= uOpt[c,q]*M)
@constraint(mip, [c in C, q in Q, o in O], 0 <= zMax[c,q,o])
@constraint(mip, [c in C, q in Q, o in O], zMax[c,q,o] <= (1 - uOpt[c,q])*M)


# Objective
gen_cost = sum(ρ[o]*(sum(C_E[g]*pE[g,o] for g in G) + 
                sum(C_C[c]*pC[c,o] for c in C)) for o in O)

annual_inv = sum(I_C_A*pCmax[c] for c in C)
@objective(mip, Min, gen_cost + annual_inv)

optimize!(mip)

println(value.(pCmax))
