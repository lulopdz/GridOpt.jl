# ==============================================================================
# Generation Expansion Planning (GEP) Model
# GridOpt.jl
# ==============================================================================

using CSV, DataFrames, JuMP, Gurobi
include("../src/concrete/tgep_concrete.jl")
include("../src/concrete/tgep_report.jl")

# CONFIGURACIÓN GEP: 
# include_network = false -> Activa la lógica de "Single Node" [cite: 20, 39]
GEP_CONFIG = TEPConfig(
    false,           # include_network: false para GEP 
    false,           # use_integer
    true,            # per_unit
    10e3,            # bigM
    Gurobi.Optimizer # solver
)

# Configuración de rutas
pkg = "GridOpt.jl"
data_path = joinpath(pwd(), pkg, "data", "planning")
proj = "10nodeCan"

# Carga de datos
data = load_tep_data(data_path, proj)

# Construir y Resolver
# build_tep_model ya maneja la lógica de GEP internamente mediante el config 
model, sets, params = build_tep_model(GEP_CONFIG, data)
solve_tep!(model, GEP_CONFIG, sets, params)

# Guardar Resultados
save_path = joinpath(pwd(), pkg, "results", proj, "gep_only")
summarize_tep_results(model, GEP_CONFIG, sets, params; save_to=save_path)