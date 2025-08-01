# This code is the benders decomposition for a generation expansion problem 
# including EV aggregator that has V2G capabilities. 

# Authors: Luis Lopez and Andrew Moffat 

# ==============================================================================
# Importing packages
using JuMP
using Ipopt, GLPK, Gurobi
using Plots, LaTeXStrings
using CSV, DataFrames

# Importing functions
include("utils.jl")
include("models.jl")

# ==============================================================================
# Parse MATPOWER data from file
mpc = parse_mpc("GridOpt.jl/data/case5_strg.m")

ev_data = CSV.read("GridOpt.jl/data/traffic_ev.csv", DataFrame)
w_data = round.((ev_data[!, :Weight]*8760))
ev_data_names = names(ev_data)[3:end-2]
ev_profiles = ev_data[!, ev_data_names]

pd_profiles = CSV.read("GridOpt.jl/data/pd_profiles.csv", DataFrame)

colorsce = collect(cgrad(:PuBuGn, length(ev_profiles[:,1]), rev = true))
colorsce = colorsce[1:length(ev_profiles[:,1])]

# Create a 5-row vertical layout for subplots
layout = @layout [a; b; c; d; e]

# Collect the first 5 EV profiles (each profile is assumed to have 24 hourly values)
p_plots = []
for i in 1:4
    p = plot(1:24, Vector(ev_profiles[i, :]),
        ylabel = "  ",
        xlabel = "",
        label = latexstring("\$\\omega_{$(i)}\$"),
        xticks = (2:2:24, ""),
        yticks = 0:0.04:0.08,
        color = colorsce[i],
    )
    push!(p_plots, p)
end
p = plot(1:24, Vector(ev_profiles[5, :]),
    ylabel = "  ",
    xlabel = "Time [h]",
    label = L"\omega_5",
    xticks = 2:2:24,
    yticks = 0:0.04:0.08,
    color = colorsce[5],
)

push!(p_plots, p)


# Combine the individual plots into a single subplot layout with overall figure size
plot(p_plots..., layout = layout,
     size = (480, 880),  # Overall figure size (width, height)
     xlims = (1, 24),
     ylims = (0, 0.09),
     lw = 5,
     legend=:topleft,
)

savefig("GridOpt.jl/src/ev/plots/ev_profiles.pdf")

# Collect the first 5 EV profiles (each profile is assumed to have 24 hourly values)
p_plots = []
for i in 1:4
    p = plot(1:24, Vector(pd_profiles[i, :]),
        ylabel = "  ",
        xlabel = "",
        label = latexstring("\$\\omega_{$(i)}\$"),
        xticks = (2:2:24, ""),
        yticks = 0.4:0.2:1,
        color = colorsce[i],
    )
    push!(p_plots, p)
end
p = plot(1:24, Vector(pd_profiles[5, :]),
    ylabel = "  ",
    xlabel = "Time [h]",
    label = L"\omega_5",
    xticks = 2:2:24,
    yticks = 0.4:0.2:1,
    color = colorsce[5],
)

push!(p_plots, p)


# Combine the individual plots into a single subplot layout with overall figure size
plot(p_plots..., layout = layout,
     size = (480, 880),  # Overall figure size (width, height)
    #  xlims = (1, 24),
     ylims = (0.5, 1.05),
     lw = 5,
     legend=:topleft
)

savefig("GridOpt.jl/src/ev/plots/pd_profiles.pdf")


# Scenerio-specific parameters
scenarios = [
    (df = 1.3, weight = w_data[1], ev = ev_profiles[1, :], pd = pd_profiles[1, :]),
    (df = 1.2, weight = w_data[2], ev = ev_profiles[2, :], pd = pd_profiles[2, :]),
    (df = 1.4, weight = w_data[3], ev = ev_profiles[3, :], pd = pd_profiles[3, :]),
    (df = 1.3, weight = w_data[4], ev = ev_profiles[4, :], pd = pd_profiles[4, :]),
    (df = 1.2, weight = w_data[5], ev = ev_profiles[5, :], pd = pd_profiles[5, :]),
]

# Sets and parameters
Ω = collect(1:length(scenarios))

# Existing generation and demand
nG = length(mpc["gen"]) 
Pgmax = [mpc["gen"][i][9] for i in 1:nG]
Pgmax_total = sum(Pgmax)
PDtotal = sum(mpc["bus"][i][3] for i in 1:length(mpc["bus"]))

# Parameters new generation (now for multiple candidates)
costC_op = [15.0, 15.0]
Pcmax = [500.0, 1000.0]
PcOpt = [20.0, 20.0]
costC_inv = [70000.0, 75000.0]
busC = [2, 4]

nC = length(costC_op)
C = collect(1:nC)

# ==============================================================================
# Master model
# 
#  min sum(weight[o]*θ[o]) + sum_i(cost_cap[i]*pC[i])
#  s.t. 0 <= pC[i] <= CAP_MAX[i]
#       θ[o] >= 0
#   plus Benders cuts that tie θ[o] to subproblem cost components

# ==============================================================================
master = Model(GLPK.Optimizer)
set_silent(master)

# Define integer decision for each candidate
@variable(master, z[c in C], Int)
@expression(master, pC[c in C], PcOpt[c]*z[c])
@constraint(master, [c in C], 0 <= pC[c] <= Pcmax[c])
@expression(master, total_pC, sum(pC[c] for c in C))

# Scenario-specific cost variables
@variable(master, θ[ω in Ω] >= 0)

# Master objective: scenario cost plus investment costs for the new candidate(s)
@objective(master, Min, 
    sum(scenarios[ω].weight * θ[ω] for ω in Ω) +
    sum(costC_inv[c] * pC[c] for c in C)
)

max_iters = 20

his = Dict(
    :pC => Vector{Vector{Float64}}(),
    :master_obj => Vector{Float64}(),
    :muY => Vector{Vector{Float64}}(),
    :subcost => Vector{Float64}()
)

tolerance = 1e-3
master_obj_k = Inf

for k in 1:max_iters
    global master_obj_k
    println("\nBenders Iteration $k")
    optimize!(master)
    
    # Retrieve current candidate capacities as a vector
    pC_val = [value(pC[c]) for c in C]
    master_obj = objective_value(master)
    println("  Master candidate capacities pC = ", pC_val)
    println("  Master Obj = ", master_obj)
    println("  Solving time = ", solve_time(master))
    push!(his[:pC], pC_val)
    push!(his[:master_obj], master_obj)

    
    # For each scenario, solve subproblem
    for ω in Ω
        sc = scenarios[ω]
        # Pass candidate capacities, candidate costs and bus info to the model
        (subcost, muY, feasible, maxD) = market_model(mpc, sc.df, pC_val, costC_op, busC, sc.ev, sc.pd, ω)
        
        push!(his[:muY], muY)
        push!(his[:subcost], subcost)
        
        if !feasible
            # Feasibility cut:
            # Here we add a cut on the total candidate capacity
            println("  Subproblem infeasible => feasibility cut: total_pC >= ", maxD - Pgmax_total)
            @constraint(master, total_pC >= maxD - Pgmax_total)
        else
            # Optimality cut
            # Each candidate contributes with its partial derivative (muY[j])
            #
            # => θ[i] >= subcost + sum(muY[j]*(pC[j] - pC_val[j]) for j in 1:n_candidates)
            println("  Subproblem feasible => cost=", subcost, " muY=", muY)
            @constraint(master, 
            θ[ω] >= subcost + sum(muY[c]*(pC[c] - pC_val[c]) for c in C)
            )
        end
    end
    # Check stopping criteria
    if abs(master_obj_k - master_obj) < tolerance
        println("Stopping criteria met: Change in master_obj = ", 
                abs(master_obj_k - master_obj))
        break
    end
    master_obj_k = master_obj    
end

optimize!(master)
println("\nFinal solution:")
println("  Candidate capacities (pC) = ", [value(pC[c]) for c in C])
for ω in Ω
    println("  θ[$ω] = ", value(θ[ω]))
end
println("  Obj = ", objective_value(master))

nΩ = length(Ω)
iters = length(his[:master_obj])

axispC = transpose(hcat(his[:pC]...))
colorsce = collect(cgrad(:Greens, nC, rev = true))
colorsce = colorsce[1:nC]

plot(axispC, 
    xlabel="Iteration", 
    ylabel="Candidate capacity [MW]", 
    label=[L"c_1" L"c_2"],
    lw=2,
    st=:bar,
    color=colorsce',
    linecolor = :match,
    bar_width = 0.9,
    legend=:topleft,
    ylims=(0,500),
)

plot!(twinx(), his[:master_obj]/1e6, 
    xlabel="Iteration", 
    xticks=(1:max_iters, 0:max_iters-1),
    ylabel="Objective value [\$]", 
    label="Master Obj",
    lw=4,
    marker = :circle,
    markersize = 8,
    markerstrokewidth = 0,
    legend=:topright,
    ylims=(0,5000),
)

savefig("GridOpt.jl/src/ev/plots/master.pdf")

axisb = [1 + i * (nΩ + 1) + (j - 1) for i in 0:(iters-1), j in 1:nΩ]
axisb = axisb'[:]
colorsce = collect(palette(:PuBuGn, nΩ+1, rev = true))
colorsce = colorsce[1:nΩ]
plot(axisb, his[:subcost]/1e6, 
    group = repeat([1, 2, 3, 4, 5], outer = iters),
    xlabel = "Iteration", 
    ylabel = "Subproblem cost [\$]", 
    label = [L"\omega_1" L"\omega_2" L"\omega_3" L"\omega_4" L"\omega_5"],
    linecolor = :match,
    bar_width = 0.9,
    ylims = (0, 1.2*maximum(his[:subcost])/1e6),
    legend=:top,
    legend_columns = nΩ,
    st = :bar,
    color = colorsce',
    xticks = (2:(nΩ+1):nΩ*(iters+2), 1:iters+2),
)

savefig("GridOpt.jl/src/ev/plots/scenarios.pdf")
