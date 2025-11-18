# Model comparinson for the GEP 

using Plots, StatsPlots, LaTeXStrings, Plots.PlotMeasures, Gurobi
# ==============================================================================
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/src/plot_defaults.jl")
set_plot_defaults()

scenario = "full"
println("Running EMH scenario: " * scenario)
ep = joinpath(pf, "GridOpt.jl/data/planning/EMH_" * scenario * ".xlsx")
solver = Gurobi.Optimizer

# Models
include("dyn_net.jl")
results = dyn_net(solver)

# Results output
Sbase = 100.0  # MVA base power
CSV.write("GridOpt.jl/results/emh/" * scenario * "/new_cap_" * scenario * ".csv", 
            DataFrame(Sbase*results[:pCmax].data, :auto)
)

years = [2025, 2030, 2035, 2040, 2045, 2050]
T = 1:length(years)
for t in T
    CSV.write("GridOpt.jl/results/emh/" * scenario * "/emissions_t$(years[t])_" * scenario * ".csv", 
    DataFrame(results[:em][:,:,t].data, :auto))
    CSV.write("GridOpt.jl/results/emh/" * scenario * "/new_gen_dispatch_t$(years[t])_" * scenario * ".csv", 
    DataFrame(Sbase*results[:pC][:,:,t].data, :auto))
    CSV.write("GridOpt.jl/results/emh/" * scenario * "/exist_gen_dispatch_t$(years[t])_" * scenario * ".csv", 
    DataFrame(Sbase*results[:pE][:,:,t].data, :auto))
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
    ylim=(150, 400),
    yticks=150:25:400,
    size=(600,400),
    markershape=:circle,
    markerstrokewidth=0.0,
)

savefig(po, "GridOpt.jl/results/emh/" * scenario * "/cum_cap_" * scenario * ".pdf")

# ==============================================================================
total_emissions = [sum(results[:em].data[:, o, t])*ρ[t][o] for o in 1:48, t in 1:6]
total_em = sum(total_emissions, dims=1)
po2 = plot(years, total_em'*Sbase/1e6, 
    xlabel="Time Periods", 
    ylabel="MtCO2eq", 
    legend=false,
    seriestype = :bar,
    lc = :match,
    ylim=(0,50),
    size=(600,400))

savefig(po2, "GridOpt.jl/results/emh/" * scenario * "/total_em_" * scenario * ".pdf")

# ==============================================================================
# Plot showing new capacity by technology type
tech_types = cand[:tech_type]
unique_techs = unique(tech_types)
tech_cap = Dict(tech => zeros(length(years)) for tech in unique_techs)  
for (c, tech) in enumerate(tech_types)
    for (t, year) in enumerate(years)
        tech_cap[tech][t] += results[:pCmax].data[c, t]
    end
end

# Construct matrix: rows = years, cols = technologies
cap_mat = hcat([tech_cap[tech] for tech in unique_techs]...) * Sbase ./ 1000
# units: GW

# Stacked bar plot
po3 = areaplot(
    years,
    cap_mat,
    xlabel = "Year",
    ylabel = "New Capacity (GW)",
    label = permutedims(unique_techs),
    legend = :outertop,
    seriestype = :bar,
    size = (700, 450),
    lw = 0.0,
    lc = :match,
    fillalpha = 0.85,
    legendcolumns = 2,
    ylim=(0,100),
    yticks=0:10:100
)

savefig(po3, "GridOpt.jl/results/emh/" * scenario * "/tech_cap_" * scenario * ".pdf")

# ==============================================================================
# Stacked area plot: dispatch by technology across op. points

pC = results[:pC].data  # (n_cand, n_op, n_years)
pE = results[:pE].data  # (n_exist, n_op, n_years)

nT = length(years)
nO = size(pC, 2)   # number of operating points

# Clean tech names
tech_types_cand  = collect(skipmissing(cand[:tech_type]))
tech_types_exist = collect(skipmissing(exist[:tech_type]))

# Unique technologies
unique_techs = unique(vcat(tech_types_cand, tech_types_exist))

# ----------------- Loop over years -----------------
for (t, year) in enumerate(years)

    # Dictionary: tech → vector of length nO
    # Each entry dis_tech[tech][o] = dispatch in MW at op point o
    dis_tech = Dict(tech => zeros(nO) for tech in unique_techs)

    # Candidate units
    for (c, tech) in enumerate(tech_types_cand)
        for o in 1:nO
            dis_tech[tech][o] += pC[c, o, t]
        end
    end

    # Existing units
    for (e, tech) in enumerate(tech_types_exist)
        for o in 1:nO
            dis_tech[tech][o] += pE[e, o, t]
        end
    end

    # Convert MW → GWh (multiply by Sbase/MW_to_GWh)
    # If you want weights ρ[t][o], multiply by ρ[t][o] inside the loop
    energy_mat = hcat([dis_tech[tech] for tech in unique_techs]...) .* Sbase ./ 1e3

    # Create stacked area plot
    po4 = areaplot(
        1:nO,
        energy_mat,
        xlabel = "Operating Conditions",
        ylabel = "Power dispatch (GWh)",
        label = permutedims(unique_techs),
        legend = :outertop,
        size = (1000, 600),
        lw = 0.0,
        fillalpha = 0.85,
        left_margin = 4mm,
        bottom_margin = 4mm,
        legendcolumns = 4,
        ylims=(0,200)
    )

    savefig(po4, "GridOpt.jl/results/emh/$scenario/energy_by_tech_$year.pdf")

end

# ==============================================================================
println("EMH scenario " * scenario * " completed.")