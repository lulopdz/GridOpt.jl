# Model comparinson for the GEP 

using Plots, StatsPlots, LaTeXStrings, Plots.PlotMeasures, Gurobi
# ==============================================================================
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/src/plot_defaults.jl")
set_plot_defaults()

solver = Gurobi.Optimizer

# Models
include("dyn.jl")
results = dyn(solver)

CSV.write("GridOpt.jl/results/emh/new_capacity.csv", DataFrame(results[:pCmax].data, :auto))

for t in 1:6
    CSV.write("GridOpt.jl/results/emh/emissions_t$t.csv", DataFrame(results[:em][:,:,t].data, :auto))
    CSV.write("GridOpt.jl/results/emh/new_gen_dispatch_t$t.csv", DataFrame(results[:pC][:,:,t].data, :auto))
    CSV.write("GridOpt.jl/results/emh/exist_gen_dispatch_t$t.csv", DataFrame(results[:pE][:,:,t].data, :auto))
end

# ==============================================================================
total_cap = sum(results[:pCmax].data, dims=1)
total_exist = sum(exist[:Max_cap], dims=1)

cum_cap = cumsum(total_cap, dims=2) .+ total_exist'
cum_cap = cum_cap*100/1000  # Convert to GW

plot(cum_cap', xlabel="Time Periods", ylabel="Total Capacity (GW)", legend=false,
    title="Cumulative Installed Capacity Over Time",
    size=(600,400))