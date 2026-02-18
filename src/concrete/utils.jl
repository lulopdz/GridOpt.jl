
# ==============================================================================
# Data Loading
function load_tgep_data(data_path::String, project::String)
    dfpath(name) = joinpath(data_path, project, string(name, ".csv"))
    
    return (
        # Existing infrastructure
        nodes = CSV.read(dfpath("nodes"), DataFrame),
        gen = CSV.read(dfpath("gen"), DataFrame),
        load = CSV.read(dfpath("load"), DataFrame),
        line = CSV.read(dfpath("line"), DataFrame),
        # Candidate infrastructure
        gcand = CSV.read(dfpath("gcand"), DataFrame),
        tcand = CSV.read(dfpath("tcand"), DataFrame),
        # Economic and scenario data
        econ = CSV.read(dfpath("economic"), DataFrame),
        sce = CSV.read(dfpath("scenario"), DataFrame)
    )
end
