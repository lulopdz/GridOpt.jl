using JuMP, Gurobi, HiGHS
using LinearAlgebra
using Printf

# --- SCENARIO DATA ---
# Region A: Cheap Wind, expensive Gas (Exporting region, e.g., BC/MB)
Gen_A_Wind = (cost=10, cap=500)
Gen_A_Gas  = (cost=80, cap=200)
Load_A = 300

# Region B: Expensive Coal, needs power (Importing region, e.g., AB/ON)
Gen_B_Coal = (cost=50, cap=400)
Gen_B_Nuke = (cost=90, cap=200)
Load_B = 500

# Intertie (Line A-B)
Limit_AB = 200 # Max flow Capacity
Rho = 1.0      # ADMM Penalty Parameter (Tuning knob)

# --- ADMM STATE VARIABLES ---
# x_AB_A: What Region A *wants* to send to B (Positive = Export)
# x_AB_B: What Region B *wants* to receive from A (Negative = Import)
# Ideally: x_AB_A + x_AB_B = 0
global x_AB_A = 0.0
global x_AB_B = 0.0
global lambda = 0.0 # The "Shadow Price" of the interconnection

# --- REGION A SOLVER (Function) ---
function solve_region_A(price_signal, penalty_target)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    
    # Variables
    @variable(model, p_wind >= 0)
    @variable(model, p_gas >= 0)
    @variable(model, export_to_B) # Border Flow variable

    # Objective: Min Cost + Lagrangian Terms (The "Price" of Export)
    # Term 1: Local Cost
    # Term 2: Price * Flow (Revenue/Cost from trade)
    # Term 3: Penalty * (Flow - Target)^2 (Augmented Lagrangian for stability)
    
    @objective(model, Min, 
        Gen_A_Wind.cost * p_wind + 
        Gen_A_Gas.cost * p_gas +
        price_signal * export_to_B  # Market signal
        + (Rho/2) * (export_to_B - penalty_target)^2 # Quadratic penalty
    )

    # Constraints
    @constraint(model, p_wind <= Gen_A_Wind.cap)
    @constraint(model, p_gas <= Gen_A_Gas.cap)
    @constraint(model, -Limit_AB <= export_to_B <= Limit_AB)
    @constraint(model, p_wind + p_gas - export_to_B == Load_A) # Energy Balance

    optimize!(model)
    return value(export_to_B)
end

# --- REGION B SOLVER (Function) ---
function solve_region_B(price_signal, penalty_target)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    
    @variable(model, p_coal >= 0)
    @variable(model, p_nuke >= 0)
    @variable(model, import_from_A) # Border Flow (Positive = Import)
    
    @objective(model, Min, 
        Gen_B_Coal.cost * p_coal + 
        Gen_B_Nuke.cost * p_nuke -
        price_signal * import_from_A # Market signal (cost to import)
        + (Rho/2) * (import_from_A - penalty_target)^2 # Quadratic penalty
    )

    @constraint(model, p_coal <= Gen_B_Coal.cap)
    @constraint(model, p_nuke <= Gen_B_Nuke.cap)
    @constraint(model, -Limit_AB <= import_from_A <= Limit_AB)
    @constraint(model, p_coal + p_nuke + import_from_A == Load_B)

    optimize!(model)
    return value(import_from_A)
end

# --- MAIN ADMM LOOP ---
println("Ite | A:export | B:import | Mismatch | Price")
for k in 1:20
    global x_AB_A, x_AB_B, lambda

    # 1. Solve Regions Independently
    val_A = solve_region_A(lambda, -x_AB_B)
    val_B = solve_region_B(lambda, -x_AB_A)
    
    # 2. Calculate Mismatch
    mismatch = val_A - val_B

    # 3. Update Price (Dual Update)
    # If A exports MORE than B imports (oversupply), Price drops.
    alpha = 0.5 # Step size
    lambda = lambda + alpha * mismatch
    
    println(@sprintf("%3d | %8.1f | %8.1f | %8.1f | %7.1f", k, val_A, val_B, mismatch, lambda))
    
    # Update globals for next step (in full ADMM these are used in the quadratic term)
    x_AB_A = val_A
    x_AB_B = val_B

    if abs(mismatch) < 1e-3
        println("Converged!")
        break
    end
end