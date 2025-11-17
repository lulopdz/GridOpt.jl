# Model comparinson for the GEP 

using Plots, StatsPlots, LaTeXStrings, Plots.PlotMeasures, Gurobi
# ==============================================================================
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/src/plot_defaults.jl")
set_plot_defaults()

ep = joinpath(pf, "GridOpt.jl/data/planning/EMH_full.xlsx")

solver = Gurobi.Optimizer

# Models
include("dyn_net.jl")
results = dyn_net(solver)

# Results output
Sbase = 100.0  # MVA base power
CSV.write("GridOpt.jl/results/emh/new_capacity.csv", DataFrame(Sbase*results[:pCmax].data, :auto))

years = [2025, 2030, 2035, 2040, 2045, 2050]
T = 1:length(years)
for t in T
    CSV.write("GridOpt.jl/results/emh/emissions_t$(years[t]).csv", DataFrame(results[:em][:,:,t].data, :auto))
    CSV.write("GridOpt.jl/results/emh/new_gen_dispatch_t$(years[t]).csv", DataFrame(Sbase*results[:pC][:,:,t].data, :auto))
    CSV.write("GridOpt.jl/results/emh/exist_gen_dispatch_t$(years[t]).csv", DataFrame(Sbase*results[:pE][:,:,t].data, :auto))
end

# ==============================================================================
total_cap = sum(results[:pCmax].data, dims=1)
total_exist = sum(exist[:Max_cap], dims=1)

cum_cap = cumsum(total_cap, dims=2) .+ total_exist'
cum_cap = cum_cap*100/1000  # Convert to GW

po = plot(years, cum_cap', 
    xlabel="Time Periods", 
    ylabel="Total Capacity (GW)", 
    legend=false,
    fillalpha=0.6,
    # ylim=(150,300),
    # yticks=150:25:300,
    size=(600,400))

savefig(po, "GridOpt.jl/results/emh/total_cap_full.pdf")

# ==============================================================================
total_emissions = [sum(results[:em].data[:, o, t])*ρ[t][o] for o in 1:48, t in 1:6]
total_em = sum(total_emissions, dims=1)
po2 = plot(years, total_em'*100/1e6, 
    xlabel="Time Periods", 
    ylabel="MtCO2eq", 
    legend=false,
    seriestype = :bar,
    lc = :match,
    ylim=(0,70),
    size=(600,400))

savefig(po2, "GridOpt.jl/results/emh/total_em_full.pdf")