# Model comparinson for the GEP 

# ==============================================================================
include(pf * "/GridOpt.jl/src/planning/utils.jl")

# Models
include("dyn.jl")

results = dyn()

market_post(results, ref, ρ, "dyn")
