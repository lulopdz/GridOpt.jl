# Deterministic Unit Commitment 
using JuMP, Ipopt, Gurobi


# ==============================================================================
# Sets 
J = 1:3 
T = 1:6

# ==============================================================================
# Parameters 
D = [240 250 200 170 230 190]
R = [10 10 10 10 10 10]
c = [5 15 30]
cU = [800 500 250]

# ==============================================================================
# Model definition
optimizer = Gurobi.Optimizer
model = Model(optimizer)

# ==============================================================================
# Variables
@variable(model, p[j in J, t in T])
@variable(model, pmax[j in J, t in T])
@variable(model, v[j in J, t in T], Bin)
@variable(model, y[j in J, t in T], Bin)
@variable(model, z[j in J, t in T], Bin)

# ==============================================================================
# Constraints
@constraint(model, [t in T], sum(p[j,t] for j in J) == D[t])
@constraint(model, [t in T], sum(pmax[j,t] for j in J) >= D[t] + R[t])
# @constraint(model, [t in T], v[j,t-1] - v[j,t] + y[j,t] - z[j,t] == 0)

# ==============================================================================
# Objective 
@objective(model, Min, sum(sum(c[j]*p[j,t] + cU[j]*y[j,t] for j in J) for t in T))

# ==============================================================================
# Solve 
optimize!(model)

println(value.(p))
