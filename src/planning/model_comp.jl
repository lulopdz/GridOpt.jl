# Model comparinson for the GEP 

using Plots, StatsPlots, LaTeXStrings, Plots.PlotMeasures
# ==============================================================================
pf = pwd()
include(pf * "/GridOpt.jl/src/planning/utils.jl")
include(pf * "/GridOpt.jl/src/plot_defaults.jl")
set_plot_defaults()

# Models
include("static.jl")
r_static = static()
market_post(r_static, "static")

include("dyn.jl")
r_dyn = dyn()
market_post(r_dyn, "dyn")

include("static_net.jl")
r_static_net = static_net()
market_post(r_static_net, "static_net")

include("dyn_net.jl")
r_dyn_net = dyn_net()
market_post(r_dyn_net, "dyn_net")


ssn = sum(r_static[:pCmax].data)
dsn = sum(r_dyn[:pCmax].data', dims = 2)
snc = sum(r_static_net[:pCmax].data)
dnc = sum(r_dyn_net[:pCmax].data', dims = 2)

bar_data = [
    ssn NaN;
    dsn[1] dsn[2];
    snc NaN;
    dnc[1] dnc[2]
]

p1 = Plots.areaplot(1:4, bar_data, 
    label=[L"$t_1$" L"$t_2$"], 
    xlabel="Model", 
    ylabel="Installed Capacity [MW]", 
    bar_width=0.7,
    lc=:match,
    st=bar,
    xticks=(1:4, ["S-SN", "D-SN", "S-NC", "D-NC"]),
    ylims=(0, 10000),
    color=["#2b8cbe" "#a6bddb"],
    legend=:topleft,
    legendcolumns=2,
    size=(680, 300),
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
    # xticks=(1:length(r_static[:pCmax].data[:]))
    # bar_width=0.3,
    # bar_position=:dodge,
)

save_plot(p2, "GridOpt.jl/results/plots/candidate_comparison")