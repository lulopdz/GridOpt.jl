using JuMP
using GLPK

const SCENARIOS = [
    (demand = 290.0, weight = 3000.0),
    (demand = 550.0, weight = 2760.0),
    (demand = 400.0, weight = 3000.0),
]
costE = 35.0
costC = 25.0
const CAP_GEN = 400.0
const CAP_MAX = 500.0
const BLOCKSIZE = 10.0
const cost_cap = 70000.0

# ==============================================================================
# Subproblem definition
# 
# Given pCmax (the capacity), return:
#   - The subproblem cost
#   - The dual for "y <= pCmax"
#   - Feasibility status
# 
# We solve:
#      min  costE*x + costC*y
#      s.t. x + y = demand
#           0 <= x <= CAP_GEN
#           0 <= y <= pCmax
# 
# ==============================================================================
function solve_subproblem(demand, pCmax; 
                          costE=costE, costC=costC,
                          solver=GLPK.Optimizer)

    # Quick check for infeasibility:
    if demand > CAP_GEN + pCmax
        return (0.0, 0.0, false)
    end

    model = Model(solver)
    @variable(model, 0 <= x <= CAP_GEN)
    @variable(model, 0 <= y)
    @constraint(model, yup, y <= pCmax)
    @constraint(model, x + y == demand)
    @objective(model, Min, costE*x + costC*y)

    optimize!(model)

    if termination_status(model) != MOI.OPTIMAL
        return (0.0, 0.0, false)
    end

    subcost = objective_value(model)
    # Dual for y <= pCmax:
    muY = dual(yup)  
    return (subcost, muY, true)
end

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
# continuous pC in [0, CAP_MAX]
# @variable(master, 0 <= pC <= CAP_MAX)
# @variable(master, θ[1:length(SCENARIOS)] >= 0)

# @objective(master, Min, 
#     sum(SCENARIOS[i].weight * θ[i] for i in eachindex(SCENARIOS)) + cost_cap * pC
# )

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
        (subcost, muY, feasible) = solve_subproblem(sc.demand, pC_val)

        if !feasible
            # Feasibility cut
            # We know demand <= x + y <= CAP_GEN + pCmax
            # => pCmax >= (demand - CAP_GEN)
            # So we add:
            println("    Subproblem infeasible => feasibility cut: pC >= ", sc.demand - CAP_GEN)
            @constraint(master, pC >= sc.demand - CAP_GEN)

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
                # θ[i] >= sc.weight*subcost + sc.weight*muY*(pC - pC_val)
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
