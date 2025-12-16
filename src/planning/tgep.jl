# Transmission and Generation Expansion Planning (TGEP) Model
# Luis Lopez 
# luislopezdiaz@cmail.carleton.ca

# Packages
using CSV, DataFrames
using JuMP
using HiGHS, Gurobi

# Include utilities
include("../utils/tgep_concrete.jl")
include("../utils/tgep_report.jl")

# ==============================================================================
# Default configurations
DEFAULT_CONFIG = TEPConfig(true, false, 10e3, HiGHS.Optimizer)
SINGLE_NODE_CONFIG = TEPConfig(false, false, 10e3, HiGHS.Optimizer)

# ==============================================================================
# Main Execution
config = DEFAULT_CONFIG

pkg = "GridOpt.jl"
data_path = joinpath(pwd(), pkg, "data", "planning")
proj = "10nodeCan"

# Load data
data = load_tep_data(data_path, proj)

# Build and solve model
model, sets, params = build_tep_model(config, data)
solve_tep!(model, config, sets, params)

# report_tep_solution(model, config, sets, params)