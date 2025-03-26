
# Plot results

# Calculate total generation for each time period
total_generation = [sum(value(pg[g, t]) for g in G) for t in T]

# Plot total generation
plot(T, total_generation, xlabel="Time Period", 
    ylabel="Total Generation (p.u.)",
    legend=false
)

# Plot generation power for each generator individually
po_pg = plot()
for g in G
    generation_levels = [value(pg[g, t]) for t in T]
    plot!(po_pg, T, generation_levels*Sbase, xlabel="Time Period", 
        ylabel="Generation Power (p.u.)",
        label="Gen $g (\$$(c[g]))"
    )
end

savefig(po_pg, "GridOpt.jl/src/ev/generation_power.png")

# Plot energy storage levels for each energy storage unit individually
po = plot()
for e in E
    elevels = [value(eEV[e, t]) for t in [1; T]]
    plot!(po, [1; T], elevels*Sbase, xlabel="Time Period", 
        ylabel="Energy Storage Levels (p.u.)",
        legend=false
    )
end

savefig(po, "GridOpt.jl/src/ev/energy_storage_levels.png")

# Plot discharging power for each energy storage unit individually
po_dis = plot()
for e in E
    discharging_levels = [value(pEV_dis[e, t]) for t in T]
    plot!(po_dis, T, discharging_levels*Sbase, xlabel="Time Period", 
        ylabel="Discharging Power (p.u.)",
        label="Storage Unit $e"
    )
end

savefig(po_dis, "GridOpt.jl/src/ev/discharging_power.png")

# Plot charging power for each energy storage unit individually
po_ch = plot()
for e in E
    charging_levels = [value(pEV_ch[e, t]) for t in T]
    plot!(po_ch, T, charging_levels*Sbase, xlabel="Time Period", 
        ylabel="Charging Power (p.u.)",
        label="Storage Unit $e"
    )
end

savefig(po_ch, "GridOpt.jl/src/ev/charging_power.png")

# Calculate total demand for each time period
total_demand = [sum(PD[n] * PD_factor[t] for n in N) for t in T]

# Plot total generation vs total demand
plot(T, total_generation, label="Total Generation (p.u.)", xlabel="Time Period", ylabel="Power (p.u.)")
plot!(T, total_demand, label="Total Demand (p.u.)")

savefig("GridOpt.jl/src/ev/total_generation_vs_total_demand.png")

