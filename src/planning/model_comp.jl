# Model comparinson for the GEP 

using Plots, StatsPlots, LaTeXStrings, Plots.PlotMeasures, Gurobi
# ==============================================================================
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/src/plot_defaults.jl")
set_plot_defaults()

solver = Gurobi.Optimizer

# Models
include("static.jl")
r_static = static(solver)

include("dyn.jl")
r_dyn = dyn(solver)

include("static_net.jl")
r_static_net = static_net(solver)

include("dyn_net.jl")
r_dyn_net = dyn_net(solver)

market_post(r_static, "static")
market_post(r_dyn, "dyn")
market_post(r_static_net, "static_net")
market_post(r_dyn_net, "dyn_net")

ssn = sum(r_static[:pCmax].data)
dsn = sum(r_dyn[:pCmax].data', dims = 2)
snc = sum(r_static_net[:pCmax].data)
dnc = sum(r_dyn_net[:pCmax].data', dims = 2)
T = size(dsn)[1]

bar_data = [
    ssn fill(NaN, T-1)...;
    dsn';
    snc fill(NaN, T-1)...;
    dnc'
]

blues_color = collect(palette(:Blues, T+5; rev = true))

p1 = Plots.areaplot(1:4, bar_data, 
    label=["\$t_{$(j)}\$" for i in 1:1, j in 1:T],
    xlabel="Time", 
    ylabel="Installed Capacity [MW]", 
    bar_width=0.7,
    lc=:match,
    st=bar,
    xticks=(1:4, ["S-SN", "D-SN", "S-NC", "D-NC"]),
    ylims=(0, 3000),
    color=blues_color',
    legend=:top,
    legendcolumns=5,
    size=(680, 350),
    leftmargin=5mm,
    bottommargin=5mm,
    topmargin=5mm,
)

save_plot(p1, "GridOpt.jl/results/plots/installed_models")

bar_data = [
    r_static[:pCmax].data[:];
    sum(r_dyn[:pCmax].data, dims = 2);
    r_static_net[:pCmax].data;
    sum(r_dyn_net[:pCmax].data, dims = 2)
]
group = repeat(["A1S-SN", "A2D-SN", "B1S-NC", "B2D-NC"], inner=length(r_static[:pCmax].data[:]))

p2 = groupedbar(bar_data,
    group=group,
    xlabel="Candidates", 
    ylabel="Installed Capacity [MW]", 
    label=["S-SN" "D-SN" "S-NC" "D-NC"],
    lc=:match,
    ylims = (0, 1000),
    legendcolumns=4,
    size=(680, 350),   
    margin=5mm,
    color=["#33a02c" "#b2df8a" "#6a3d9a" "#cab2d6"],
    xticks=(1:3:length(r_static[:pCmax].data[:]))
    # bar_width=0.3,
    # bar_position=:dodge,
)

save_plot(p2, "GridOpt.jl/results/plots/candidate_comparison")