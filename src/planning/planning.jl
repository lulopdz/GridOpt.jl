# ==============================================================================
# Deterministic Single-Node Static GEP
using JuMP, Ipopt

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
M = 1e20          # Big number

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
optimizer = Ipopt.Optimizer
m = Model(optimizer)

# Variables
@variable(m, pCmax[c in C])
@variable(m, pE[g in G, o in O])
@variable(m, pC[c in C, o in O])
@variable(m, μEmax[g in G, o in O])
@variable(m, μCmax[c in C, o in O])

@variable(m, λ[o in O])


# Constraints
@constraint(m, [c in C], 0 <= pCmax[c] <= PCmax[c])
@constraint(m, [o in O], sum(pE[g,o] for g in G) + 
            sum(pC[c,o] for c in C) == sum(PD[d,o] for d in D))
@constraint(m, [g in G, o in O], 0 <= pE[g,o] <= PEmax[g])
@constraint(m, [c in C, o in O], 0 <= pC[c,o])
@constraint(m, [c in C, o in O], pC[c,o] <= pCmax[c])

@constraint(m, [g in G, o in O], C_E[g] - λ[o] + μEmax[g,o] >= 0)
@constraint(m, [c in C, o in O], C_C[c] - λ[o] + μCmax[c,o] >= 0)

@constraint(m, [g in G, o in O], μEmax[g,o] >= 0)
@constraint(m, [c in C, o in O], μCmax[c,o] >= 0)

@constraint(m, [o in O], sum(C_E[g]*pE[g,o] for g in G) + 
            sum(C_C[c]*pC[c,o] for c in C) == 
            λ[o]*sum(PD[d,o] for d in D) - 
            sum(μEmax[g,o]*PEmax[g] for g in G) - 
            sum(μCmax[c,o]*pCmax[c] for c in C))

# Objective
gen_cost = sum(ρ[o]*(sum(C_E[g]*pE[g,o] for g in G) + 
                sum(C_C[c]*pC[c,o] for c in C)) for o in O)

annual_inv = sum(I_C_A*pCmax[c] for c in C)
@objective(m, Min, gen_cost + annual_inv)

optimize!(m)
print(m)

println(value.(pCmax))

# ==============================================================================
# Clearing market

# market = Model(optimizer)

# @constraint(market, [g in G], 0 <= pE[g,o] <= PEmax[g])
# @constraint(market, [c in C], 0 <= pC[c,o] <= pCmax[c])
# @constraint(market, sum(pE[g,o] for g in G) + 
#             sum(pC[c,o] for c in C) == sum(PD[d,o] for d in D))

# gen_cost = sum(C_E[g]*pE[g,o] for g in G) + 
#            sum(C_C[c]*pC[c,o] for c in C)

# @objective(market, Min, gen_cost)
