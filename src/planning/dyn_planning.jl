# ==============================================================================
# Deterministic Single-Node Static GEP

using JuMP, Gurobi, Ipopt

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
a = [0.2, 0.1]    # Amortization rate [%]
# Bl              # Susceptance of transmission line [S]
C_C = [25 25]  # Production cost of candidate generating unit c [$/MWh]
C_E = [35 35]  # Production cost of existing generating unit g [$/MWh]
# C_LS            # Load-shedding cost of demand d [$/MWh]
# Fl              # Capacity of transmission line [MW]
# I_C             # Investment cost of candidate generating unit c [$/MW]
I_C_A = [700000 700000]    # Annualized inv cost of candidate generating unit c [$/MW]
PCmax = 500       # Maximum production capacity of generating unit c [MW]
P_Opt = [[[0 100 200 300], [0 100 200 300]]] 
# Production capacity of inv option q of gen unit c [MW]
PD = [[[246.5 290], [467.5 550]]]
# Load of demand d [MW]
PEmax = 400       # Production capacity of existing generating unit g [MW]
# ϕ               # Probability of scenario ω [pu]
ρ = [6000 6000;
     2760 2760]  # Weight of operating condition o [h]
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
            sum(pC[c,o,t] for c in C) == sum(PD[d][o][t] for d in D))

@constraint(mip, [g in G, o in O, t in T], 0 <= pE[g,o,t] <= PEmax[g])

@constraint(mip, [c in C, o in O, t in T], 0 <= pC[c,o,t])
@constraint(mip, [c in C, o in O, t in T], pC[c,o,t] <= 
            sum(pCmax[c,τ] for τ in 1:t))

@constraint(mip, [g in G, o in O, t in T], 
            C_E[g,t] - λ[o,t] + μEmax[g,o,t] >= 0)
@constraint(mip, [c in C, o in O, t in T], 
            C_C[c,t] - λ[o,t] + μCmax[c,o,t] >= 0)

@constraint(mip, [g in G, o in O, t in T], μEmax[g,o,t] >= 0)
@constraint(mip, [c in C, o in O, t in T], μCmax[c,o,t] >= 0)

@constraint(mip, [o in O, t in T], sum(C_E[g,t]*pE[g,o,t] for g in G) + 
            sum(C_C[c,t]*pC[c,o,t] for c in C) == 
            λ[o,t]*sum(PD[d][o][t] for d in D) - 
            sum(μEmax[g,o,t]*PEmax[g] for g in G) - 
            sum(μCmax[c,o,t]*pCmax[c,t] for c in C) - 
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
gen_cost = sum(sum(ρ[o]*(sum(C_E[g,t]*pE[g,o,t] for g in G) + 
                sum(C_C[c,t]*pC[c,o,t] for c in C)) for o in O) for t in T)

annual_inv = sum(a[t]*sum(I_C_A[c,t]*pCmax[c,t] for c in C) for t in T)

@objective(mip, Min, gen_cost + annual_inv)

optimize!(mip)

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
