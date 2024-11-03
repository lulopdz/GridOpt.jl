# ==============================================================================
# Deterministic Network-Constrained Static GEP
using JuMP, Gurobi, Ipopt

# ==============================================================================
# Notation
C = 1 
D = 1 
G = 1 
L = 1 
N = 2
O = 2
T = 2 
Ω = 1
Q = 5

# Indices
C = 1:C         # Candidate generating units
G = 1:G         # Existing generating units
D = 1:D         # Demands
L = 1:L         # Transmission lines
N = 1:N         # Nodes
O = 1:O         # Operating conditions
T = 1:T         # Time periods
Ω = 1:Ω         # Scenarios
Q = 1:Q         # Generation capacity blocks

# Sets 
r = [2]         # Receiving-end node of transmission line
s = [1]         # Sending-end node of transmission line
Ω_C = [0 1]     # Candidate generating units located at node n
Ω_D = [0 1]     # Demands located at node n
Ω_E = [1 0]     # Existing generating units located at node n
ng = Dict(1 => 1)
nc = Dict(1 => 2)
Nr = [2]

# Parameters
a = [0.2, 0.1]    # Amortization rate [%]
B = 500           # Susceptance of transmission line [S]
C_C = [25 25]     # Production cost of candidate generating unit c [$/MWh]
C_E = [35 35]     # Production cost of existing generating unit g [$/MWh]
F = 200           # Capacity of transmission line [MW]
# C_LS            # Load-shedding cost of demand d [$/MWh]
# I_C             # Investment cost of candidate generating unit c [$/MW]
I_C_A = [700000 700000]    # Annualized inv cost of candidate generating unit c [$/MW]
PCmax = 500       # Maximum production capacity of generating unit c [MW]
P_Opt = [[[0 100 200 300 400], [0 100 200 300 400]]] 
# Production capacity of inv option q of gen unit c [MW]
PD = [[[246.5 290], [467.5 550]]]
# Load of demand d [MW]
PEmax = 400       # Production capacity of existing generating unit g [MW]
# ϕ               # Probability of scenario ω [pu]
ρ = [
     6000 6000;
     2760 2760
]  # Weight of operating condition o [h]

M = 1e10          # Big number
ref = 1           # Slack node

# # Variables 
# # Binary 
# u_cq            # Binary variable 

# Continuous
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
            == sum(PD[d][o][t] for d in Ω_D[n] if d!=0)
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
@constraint(mip, [g in G, o in O, t in T], C_E[g,t] - 
            λ[ng[g],o,t] + μEmax[g,o,t] >= 0
)
@constraint(mip, [c in C, o in O, t in T], C_C[c,t] - 
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

@constraint(mip, [o in O, t in T], sum(C_E[g,t]*pE[g,o,t] for g in G) + 
            sum(C_C[c,t]*pC[c,o,t] for c in C) == 
            sum(λ[n,o,t]*sum(PD[d][o][t] for d in Ω_D[n] if d!=0) for n in N) - 
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


# Objective
gen_cost = sum(sum(ρ[o]*(sum(C_E[g,t]*pE[g,o,t] for g in G) + 
                sum(C_C[c,t]*pC[c,o,t] for c in C)) for o in O) for t in T)

annual_inv = sum(a[t]*sum(I_C_A[c,t]*pCmax[c,t] for c in C) for t in T)

@objective(mip, Min, gen_cost + annual_inv)

optimize!(mip)

println(value.(pCmax))
