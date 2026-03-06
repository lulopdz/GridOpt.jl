using JuMP
using GLPK

# Initialize the Model
model = Model(GLPK.Optimizer)

# ==========================================
# 1. PARAMETERS & DATA
# ==========================================
# Power Base: 100 MVA is standard, but we will use MW directly for clarity.
Load_N2 = 300.0 # MW

# --- Generation Data ---
# Cost Op [$/MWh], Capacity [MW], Inv Cost [$/MW]
Cost_G1_Op = 10.0;   Cap_G1 = 500.0
Cost_G2_Op = 100.0;  Cap_G2 = 500.0
Cost_G3_Op = 40.0;   Cap_G3_Max = 200.0; Cost_G3_Inv = 150000.0

# --- Transmission Data ---
# Existing Lines: Reactance X=0.1 implies Susceptance B = 1/0.1 = 10
B_val = 10.0
Limit_Existing = 100.0 # MW

# Candidate Line (Node 1 -> Node 2)
Limit_New = 200.0 # MW
Cost_Line_Inv = 10000000.0 # Fixed Investment cost
M = 10000.0 # Big-M for relaxing constraints when line is not built

# ==========================================
# Variables

# Generators (MW)
@variable(model, 0 <= P_g1 <= Cap_G1)      # Existing Node 1 (Cheap)
@variable(model, 0 <= P_g2 <= Cap_G2)      # Existing Node 3 (Expensive)
@variable(model, P_g3 >= 0)                # Candidate Node 2 (Gas)

# Investment Variables
@variable(model, 0 <= P_g3_cap <= Cap_G3_Max) # Built capacity for G3
@variable(model, chi_new, Bin)                # 1 if we build new line, 0 otherwise

# Network Variables
@variable(model, theta[1:3])               # Voltage angles (radians approx)
@variable(model, f_12)                     # Flow on Existing 1->2
@variable(model, f_13)                     # Flow on Existing 1->3
@variable(model, f_23)                     # Flow on Existing 2->3
@variable(model, f_new)                    # Flow on Candidate 1->2

# ==========================================
# 3. OBJECTIVE FUNCTION
# ==========================================
# Minimize: Operational Cost + Investment Cost
@objective(model, Min, 
    # Operational Cost
    (Cost_G1_Op * P_g1) + 
    (Cost_G2_Op * P_g2) + 
    (Cost_G3_Op * P_g3) +
    # Investment Cost
    (Cost_G3_Inv * P_g3_cap) + 
    (Cost_Line_Inv * chi_new)
)

# ==========================================
# 4. CONSTRAINTS
# ==========================================

# --- A. Generator Limits (Candidate) ---
# Output cannot exceed the capacity we chose to build
@constraint(model, P_g3 <= P_g3_cap)

# --- B. Nodal Power Balance (KCL) ---
# Logic: Generation - Load = Sum(Flows Leaving Node)

# Node 1: P_g1 is Gen. Flows 1->2, 1->3, and New 1->2 all LEAVE Node 1.
@constraint(model, P_g1 == f_12 + f_13 + f_new)

# Node 2: P_g3 is Gen, Load is 300. 
# Flows 1->2 and New 1->2 ENTER (-). Flow 2->3 LEAVES (+).
@constraint(model, P_g3 - Load_N2 == -f_12 - f_new + f_23) 

# Node 3: P_g2 is Gen. 
# Flows 1->3 and 2->3 both ENTER (-).
@constraint(model, P_g2 == -f_13 - f_23)

# --- C. DC Power Flow (Physics) ---
# Flow = B * (Theta_from - Theta_to)

# Existing Lines
@constraint(model, f_12 == B_val * (theta[1] - theta[2]))
@constraint(model, f_13 == B_val * (theta[1] - theta[3]))
@constraint(model, f_23 == B_val * (theta[2] - theta[3]))

# Candidate Line (Big-M formulation)
# If chi_new=1: Flow = B * (angle diff)
# If chi_new=0: Flow is decoupled from angles (but forced to 0 by thermal limits)
@constraint(model, f_new - B_val * (theta[1] - theta[2]) <= M * (1 - chi_new))
@constraint(model, f_new - B_val * (theta[1] - theta[2]) >= -M * (1 - chi_new))

# --- D. Thermal Limits ---
@constraint(model, -Limit_Existing <= f_12 <= Limit_Existing)
@constraint(model, -Limit_Existing <= f_13 <= Limit_Existing)
@constraint(model, -Limit_Existing <= f_23 <= Limit_Existing)

# Candidate Line Limit (Forced to 0 if chi_new=0)
@constraint(model, f_new <= Limit_New * chi_new)
@constraint(model, f_new >= -Limit_New * chi_new)

# --- E. Reference Angle ---
@constraint(model, theta[1] == 0)


# ==========================================
# 5. SOLVE
# ==========================================
optimize!(model)

# ==========================================
# 6. REPORTING
# ==========================================
println("---------------------------------------")
println("Optimization Status: ", termination_status(model))
println("Total Cost: \$", round(objective_value(model), digits=2))
println("---------------------------------------")

println("--- INVESTMENT DECISIONS ---")
if value(chi_new) > 0.5
    println("[X] Build New Line 1-2 (Cost: \$10M)")
else
    println("[ ] Do NOT Build New Line 1-2")
end

if value(P_g3_cap) > 0.001
    println("[X] Build Generator at Node 2: $(round(value(P_g3_cap), digits=2)) MW")
else
    println("[ ] Do NOT Build Generator at Node 2")
end

println("\n--- OPERATIONAL DISPATCH ---")
println("Gen 1 (Node 1, Cheap): $(round(value(P_g1), digits=2)) MW")
println("Gen 2 (Node 3, Exp.) : $(round(value(P_g2), digits=2)) MW")
println("Gen 3 (Node 2, Cand.): $(round(value(P_g3), digits=2)) MW")

println("\n--- NETWORK FLOWS ---")
println("Line 1->2 (Limit 100): $(round(value(f_12), digits=2)) MW")
println("Line 1->3 (Limit 100): $(round(value(f_13), digits=2)) MW")
println("Line 2->3 (Limit 100): $(round(value(f_23), digits=2)) MW")
println("New Line  (Limit 200): $(round(value(f_new), digits=2)) MW")