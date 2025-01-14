# Model comparinson for the GEP 

using Plots, StatsPlots
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

areaplot(1:4, bar_data, 
    label=["t1" "t2"], 
    xlabel="Model", 
    ylabel="Value", 
    bar_width=0.7,
    lc=:match,
    st=bar,
    xticks=(1:4, ["S-SN", "D-SN", "S-NC", "D-NC"]),
)


bar_data = [
    r_static[:pCmax].data[:];
    sum(r_dyn[:pCmax].data, dims = 2);
    r_static_net[:pCmax].data;
    sum(r_dyn_net[:pCmax].data, dims = 2)
]
group = repeat(["AS-SN", "AD-SN", "BS-NC", "BD-NC"], inner=length(r_static[:pCmax].data[:]))

groupedbar(bar_data,
    group=group,
    xlabel="Candidates", 
    ylabel="Installed2", 
    label=["S-SN" "D-SN" "S-NC" "D-NC"],
    lc=:match, 
    # bar_width=0.3,
    # bar_position=:dodge,
)
