using PowerModels

include(pwd() * "/GridOpt.jl/data/case14.jl")

fp = "GridOpt.jl/data/"
fn = "case14.m"
fp = fp * fn

net = parse_file(fp)
