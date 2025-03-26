# Importing packages
using JuMP
using Ipopt, GLPK, Gurobi
using Plots

# Importing functions
include("utils.jl")
include("models.jl")

# Parse MATPOWER data from file
mpc = parse_mpc("GridOpt.jl/data/case5_strg.m")

SCENARIOS = [
    (demand = 1, weight = 3000.0),
    (demand = 1, weight = 2760.0),
    (demand = 1., weight = 3000.0),
]

# Existing generation and demand
nG = length(mpc["gen"])          
Pmax = [mpc["gen"][i][9] for i in 1:nG]
CAP_GEN = sum(Pmax)
PDtotal = sum(mpc["bus"][i][3] for i in 1:length(mpc["bus"]))

# Parameters new generation
costC = 10.0
CAP_MAX = 500.0
BLOCKSIZE = 10.0
cost_cap = 70000.0

# ---------------------------
# Master model
# 
#  min sum(weight[o]*θ[o]) + cost_cap*pC
#  s.t. 0 <= pC <= CAP_MAX
#       θ[o] >= 0
#   plus Benders cuts that tie θ[o] to subproblem cost
# ---------------------------
master = Model(GLPK.Optimizer)

# ===========================
# Integer 
@variable(master, 0 <= z <= CAP_MAX/BLOCKSIZE, Int)
@expression(master, pC, BLOCKSIZE * z)
@variable(master, θ[1:length(SCENARIOS)] >= 0)
@objective(master, Min, 
    sum(SCENARIOS[i].weight * θ[i] for i in eachindex(SCENARIOS)) + cost_cap * pC
)

max_iters = 10
for k in 1:max_iters
    println("\nBenders Iteration $k")
    optimize!(master)
    pC_val = value(pC)
    println("  Master pC = $pC_val")
    println("  Master Obj = ", objective_value(master))

    # For each scenario, solve subproblem
    for i in eachindex(SCENARIOS)
        sc = SCENARIOS[i]
        (subcost, muY, feasible) = market_model(mpc, sc.demand, pC_val, costC)

        if !feasible
            # Feasibility cut
            # We know demand <= x + y <= CAP_GEN + pCmax
            # => pCmax >= (demand - CAP_GEN)
            # So we add:
            println("    Subproblem infeasible => feasibility cut: pC >= ", sc.demand*1000 - CAP_GEN)
            @constraint(master, pC >= sc.demand*PDtotal - CAP_GEN)

        else
            # Optimality cut
            #
            # Weighted subproblem cost = sc.weight * subcost
            # The partial derivative w.r.t. pC is sc.weight * muY
            #
            # => θ[i] >= sc.weight*subcost + sc.weight*muY*(pC - pC_val)
            #
            println("    Subproblem feasible => cost=$subcost muY=$muY")
            @constraint(master, 
                θ[i] >= subcost + muY*(pC - pC_val)
            )
        end
    end

end

optimize!(master)
println("\nFinal solution:")
println("  pC = ", value(pC))
for i in eachindex(SCENARIOS)
    println("  θ[$i] = ", value(θ[i]))
end
println("  Obj = ", objective_value(master))
