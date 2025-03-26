using JuMP
using Gurobi  # or GLPK / Ipopt etc. (Gurobi is faster for MIPs)
import MathOptInterface
const MOI = MathOptInterface

# Suppose you have these scenarios:
const SCENARIOS = [
    (demand_factor = 1.0, weight = 3000.0),
    (demand_factor = 1.2, weight = 2760.0),
    (demand_factor = 0.7, weight = 3000.0),
]

# Each scenario will do a multi‐period DC OPF with EVs, for T=25
const T = 1:25

# We assume you have a big dictionary or arrays with your bus data, line data, generator data, etc.
# e.g. from your "mpc" object:
#   nN, nL, nG, nE, etc. 
# plus the cost coefficients, line susceptances, etc.

# Master model
master = Model(Gurobi.Optimizer)
set_optimizer_attribute(master, "OutputFlag", 0)  # silent

# Integer blocks
@variable(master, 0 <= z <= 50, Int)
@expression(master, pC, 10.0 * z)  # capacity in MW

# One variable per scenario for second‐stage cost
@variable(master, θ[1:length(SCENARIOS)] >= 0)

# Cost of capacity
cost_cap = 70000.0

@objective(master, Min, sum(SCENARIOS[o].weight * θ[o] for o in eachindex(SCENARIOS)) + cost_cap * pC)


