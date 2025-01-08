# ==============================================================================
# Grid data full dynamic network planning
using DataFrames, XLSX

pf = pwd()
ep = pf * "/GridOpt.jl/data/planning/test118.xlsx"
xf = XLSX.readxlsx(ep)

T = size(xf["economic"][:])[1] - 1
O = size(xf["economic"][:])[2] - 2

function load_cand(xf, T)
    m = xf["cand"][:]
    df = DataFrame(m[2:end, :], :auto)
    rename!(df, Symbol.(m[1, :]))
    prod_cost = [Vector{Float64}(df[:, Symbol("Prod_cost_t$i")]) for i in 1:T] 
    inv_cost = [Vector{Float64}(df[:, Symbol("Inv_cost_t$i")]) for i in 1:T]
    C = length(df.ID)
    return Dict(
        :ID         => Vector{Int64}(df.ID),
        :Node       => Vector{Int64}(df.Node),
        :Prod_cost  => [[prod_cost[t][c] for t in 1:T] for c in 1:C],
        :Inv_cost   => [[inv_cost[t][c] for t in 1:T] for c in 1:C],
        :Prod_cap   => [[vcat(0.0, range(0.0, step=cap/(q-1), length=q)[2:end]) for _ in 1:T] for (cap, q) in zip(df.Prod_cap, df.Q)]
    )
end

function load_exist(xf, T)
    m = xf["exist"][:]
    df = DataFrame(m[2:end, :], :auto)
    rename!(df, Symbol.(m[1, :]))
    prod_cost = [Vector{Float64}(df[:, Symbol("Prod_cost_t$i")]) for i in 1:T] 
    G = length(df.ID)
    return Dict(
        :ID        => Vector{Int64}(df.ID),
        :Node      => Vector{Int64}(df.Node),
        :Max_cap   => Vector{Float64}(df.Max_cap),
        :Prod_cost => [[prod_cost[t][g] for t in 1:T] for g in 1:G]
    )
end

function load_lines(xf)
    m = xf["lines"][:]
    df = DataFrame(m[2:end, :], :auto)
    rename!(df, Symbol.(m[1, :]))
    return Dict(
        :ID          => Vector{Int64}(df.ID),
        :From        => Vector{Int64}(df.From),
        :To          => Vector{Int64}(df.To),
        :Susceptance => Vector{Float64}(df.Susceptance),
        :Capacity    => Vector{Float64}(df.Capacity)
    )
end

function load_demands(xf, T, O)
    m = xf["demand"][:]
    df = DataFrame(m[2:end, :], :auto)
    rename!(df, Symbol.(m[1, :]))
    demands = [[Vector{Float64}(df[:, Symbol("Load_t$j"*"_o$i")]) for i in 1:O] for j in 1:T]
    D = length(df.ID)
    return Dict(
        :ID   => Vector{Int64}(df.ID),
        :Node => Vector{Int64}(df.Node),
        :Load => [[[demands[t][o][d] for o in 1:O] for t in 1:T] for d in 1:D]
    )
end

function load_economic(xf, T, O)
    m = xf["economic"][:]
    df = DataFrame(m[2:end, :], :auto)
    rename!(df, Symbol.(m[1, :]))
    rho = [Vector{Float64}(df[:, Symbol("rho_o$i")]) for i in 1:O]
    a = Vector{Float64}(df.a)
    ρ = [[rho[o][t] for o in 1:O] for t in 1:T]
    return a, ρ
end

cand = load_cand(xf, T)
exist = load_exist(xf, T)
lines = load_lines(xf)
demands = load_demands(xf, T, O)
a, ρ = load_economic(xf, T, O)

M = 1e10          # Big number
