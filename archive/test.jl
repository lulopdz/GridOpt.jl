using PowerModels, Gurobi, Ipopt

grid_data = parse_file("GridOpt.jl/data/operation/Texas7k_20210804.m")
grid_model = ACPPowerModel
OPF_model = build_opf
optimizer = Ipopt.Optimizer
pm = instantiate_model(grid_data, grid_model, OPF_model)
res = optimize_model!(pm, optimizer = optimizer)