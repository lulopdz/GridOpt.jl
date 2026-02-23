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
include("../src/concrete/tgep_report.jl")

# ==============================================================================
# Default configurations
DEFAULT_CONFIG = TEPConfig(
    true,               # network
    false,              # integers
    true,              # per_unit
    10e5,               # bigM
    Gurobi.Optimizer    # solver
)
SINGLE_NODE_CONFIG = TEPConfig(
    false,              # network
    false,              # integers
    false,               # per_unit
    10e5,               # bigM
    Gurobi.Optimizer    # solver
)

# ==============================================================================
# Main Execution
config = DEFAULT_CONFIG

pkg = "GridOpt.jl"
data_path = joinpath(pwd(), pkg, "data", "planning")
proj = "PaCES"

# Load data
data = load_tgep_data(data_path, proj)

# Build and solve model
model, sets, params = build_tgep_model(config, data)
solve_tgep!(model, config, sets, params)

# report_solution(model, config, sets, params)
save_path = joinpath(pwd(), pkg, "results", proj)
summarize_results(model, config, sets, params; save_to=save_path)