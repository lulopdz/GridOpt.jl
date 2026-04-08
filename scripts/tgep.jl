# ==============================================================================
# Transmission and Generation Expansion Planning (TGEP) Model
# Luis Lopez 
# luislopezdiaz@cmail.carleton.ca
# ==============================================================================

# Packages
using CSV, DataFrames
using JuMP
using HiGHS, Gurobi

# Include utilities
include("../src/concrete/tgep_concrete.jl")
include("../src/reporting/tgep_report.jl")

# ==============================================================================
# Default configurations
DEFAULT_CONFIG = TEPConfig(
    false,              # include_network
    false,              # integers
    false,              # enforce_netzero
    false,               # include_carbon_tax
    :system,            # cf_resolution (:system, :regional, :nodal)
    true,               # per_unit
    1e25,               # bigM
    Gurobi.Optimizer    # solver
)

# ==============================================================================
# Main Execution
config = DEFAULT_CONFIG

pkg = "GridOpt.jl"
data_path = joinpath(pwd(), pkg, "data", "planning")
proj = "CODERS"

# Load data
data =  load_tgep_data(data_path, proj)

# Build and solve model
model, sets, params = build_tgep_model(config, data)
solve_tgep!(model, config, sets, params)

# Report_solution(model, config, sets, params)
save_path = joinpath(pwd(), pkg, "results", proj)

summarize_results(model, config, sets, params; save_to=save_path)
save_plots(model, config, sets, params, save_path)

println("\n" * "="^50)
println("TGEP RUN COMPLETED")
println("="^50)
println("Project: $proj")
println("Network included: $(config.include_network)")
println("Carbon tax applied: $(config.include_carbon_tax)")
println("Capacity factor resolution: $(config.cf_resolution)")
println("Per unit system: $(config.per_unit)")
println("Results saved in: $save_path")
