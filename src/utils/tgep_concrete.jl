# Configuration Structure
struct TEPConfig
    include_network::Bool      # true = multi-node network, false = single node
    use_integer::Bool          # true = binary investments, false = continuous relaxation
    bigM::Float64             # Big-M for candidate line constraints
    solver                    # Optimizer (e.g., GLPK.Optimizer)
end

# ==============================================================================
# Data Loading
function load_tep_data(data_path::String, project::String)
    dfpath(name) = joinpath(data_path, project, string(name, ".csv"))
    
    return (
        # Existing infrastructure
        nodes = CSV.read(dfpath("nodes"), DataFrame),
        gen = CSV.read(dfpath("gen"), DataFrame),
        load = CSV.read(dfpath("load"), DataFrame),
        line = CSV.read(dfpath("line"), DataFrame),
        # Candidate infrastructure
        gcand = CSV.read(dfpath("gcand"), DataFrame),
        tcand = CSV.read(dfpath("tcand"), DataFrame),
        # Economic and scenario data
        econ = CSV.read(dfpath("economic"), DataFrame),
        sce = CSV.read(dfpath("scenario"), DataFrame)
    )
end

# ==============================================================================
# Process Data and Create Sets
function process_tep_sets(data)
    nodes, gen, load, line = data.nodes, data.gen, data.load, data.line
    gcand, tcand = data.gcand, data.tcand
    econ, sce = data.econ, data.sce
    
    # Sets and Indices
    B = nodes[!, :id]
    G = gen[!, :id]
    D = load[!, :id]
    E = line[!, :id]

    K = gcand[!, :id]
    L = tcand[!, :id]
    
    T = econ[!, :t]
    O = sce[!, :hour]
    
    # Node mappings
    Bmap = Dict(nodes.node_code .=> nodes.id)
    ncode = Dict(nodes.id .=> nodes.node_code)
    
    # Items per bus
    items_b(df, b) = [df.id[i] for i in 1:nrow(df) if df.node_code[i] == ncode[b]]
    
    # Sets grouped by bus
    Ωg = Dict(b => items_b(gen, b) for b in B)
    Ωk = Dict(b => items_b(gcand, b) for b in B)
    Ωd = Dict(b => items_b(load, b) for b in B)
    
    # Line topology
    fr  = Dict(e => Bmap[line.node_code_st[e]] for e in E)
    to  = Dict(e => Bmap[line.node_code_en[e]] for e in E)
    frn = Dict(l => Bmap[tcand.node_code_st[l]] for l in L)
    ton = Dict(l => Bmap[tcand.node_code_en[l]] for l in L)
    
    # Scenario and time weights
    ρ = Dict(O .=> sce.weight)
    α = Dict(T .=> econ.a)
    
    return (B=B, G=G, D=D, E=E, K=K, L=L, T=T, O=O, 
            Ωg=Ωg, Ωk=Ωk, Ωd=Ωd, fr=fr, to=to, frn=frn, ton=ton, ρ=ρ, α=α)
end


function process_tep_params(data)
    gen, load, line, gcand, tcand = data.gen, data.load, data.line, data.gcand, data.tcand
    
    return (
        # Existing infrastructure parameters
        Pgmax = Dict(gen.id .=> gen.capacity_mw),
        Pgmin = Dict(gen.id .=> gen.Pmin),
        Pgcost = Dict(gen.id .=> gen.om_cost),
        Pd = Dict(load.id .=> load.demand_mw),
        xe = Dict(line.id .=> line.reactance),
        Fmax = Dict(line.id .=> line.ttc_mw),
        # Candidate infrastructure parameters
        Pkmax = Dict(gcand.id .=> gcand.capacity_mw),
        Pkmin = Dict(gcand.id .=> gcand.Pmin),
        Pkcost = Dict(gcand.id .=> gcand.om_cost),
        Pkinv = Dict(gcand.id .=> gcand.inv_cost),
        Flinv = Dict(tcand.id .=> tcand.inv_cost),
        xl = Dict(tcand.id .=> tcand.reactance),
        Fmaxl = Dict(tcand.id .=> tcand.ttc_mw),
    )
end


# ==============================================================================
# Add Variables
function add_tep_variables!(model, config::TEPConfig, sets)
    G, K, E, L, B, T, O = sets.G, sets.K, sets.E, sets.L, sets.B, sets.T, sets.O
    
    # Dispatch variables
    @variable(model, pg[g in G, t in T, o in O] >= 0)
    @variable(model, pk[k in K, t in T, o in O] >= 0)
    
    # Investment variables
    @variable(model, pkmax[k in K, t in T] >= 0)
    @variable(model, β[l in L, t in T], Bin)
    
    # Network variables (only if multi-node)
    if config.include_network
        @variable(model, θ[b in B, t in T, o in O])
        @variable(model, f[e in E, t in T, o in O])
        @variable(model, fl[l in L, t in T, o in O])
    end
    
    return model
end

# ==============================================================================
# Add Generation Constraints
function add_generation_constraints!(model, sets, params)
    G, K, T, O = sets.G, sets.K, sets.T, sets.O
    pg, pk, pkmax = model[:pg], model[:pk], model[:pkmax]
    Pgmax, Pgmin, Pkmin, Pkmax = params.Pgmax, params.Pgmin, params.Pkmin, params.Pkmax
    
    # Existing generator limits
    @constraint(model, [g in G, t in T, o in O], Pgmin[g] <= pg[g, t, o])
    @constraint(model, [g in G, t in T, o in O], pg[g, t, o] <= Pgmax[g])
    
    # Candidate generator limits
    @constraint(model, [k in K, t in T, o in O], Pkmin[k] <= pk[k, t, o])
    @constraint(model, [k in K, t in T, o in O], pk[k, t, o] <= sum(pkmax[k, τ] for τ in 1:t))
    @constraint(model, [k in K, t in T], sum(pkmax[k, τ] for τ in 1:t) <= Pkmax[k])
end

# ==============================================================================
# Add Investment Constraints
function add_investment_constraints!(model, sets)
    L, T = sets.L, sets.T
    β = model[:β]
    
    # Line can be built at most once across all years
    @constraint(model, [l in L, t in T], sum(β[l, τ] for τ in 1:t) <= 1)
end

# ==============================================================================
# Add Network Constraints - Multi-Node with DC Power Flow
function add_network_constraints!(model, config::TEPConfig, sets, params)
    B, E, L, T, O = sets.B, sets.E, sets.L, sets.T, sets.O
    G, K = sets.G, sets.K
    Ωg, Ωk, Ωd = sets.Ωg, sets.Ωk, sets.Ωd
    fr, to, frn, ton = sets.fr, sets.to, sets.frn, sets.ton
    pg, pk = model[:pg], model[:pk]
    θ, f, fl, β = model[:θ], model[:f], model[:fl], model[:β]
    xe, xl, Fmax, Fmaxl, Pd = params.xe, params.xl, params.Fmax, params.Fmaxl, params.Pd
    M = config.bigM
    
    # Power balance at each bus
    @constraint(model, demand[b in B, t in T, o in O],
        sum(pg[g, t, o] for g in Ωg[b]) + sum(pk[k, t, o] for k in Ωk[b]) +
        sum(f[e, t, o] for e in E if to[e] == b)   - sum(f[e, t, o] for e in E if fr[e] == b) +
        sum(fl[l, t, o] for l in L if ton[l] == b) - sum(fl[l, t, o] for l in L if frn[l] == b)
        == sum(Pd[d] for d in Ωd[b])
    )
    
    # DC power flow for existing lines
    @constraint(model, [e in E, t in T, o in O], f[e, t, o] == (θ[fr[e], t, o] - θ[to[e], t, o]) / xe[e])
    @constraint(model, [e in E, t in T, o in O], -Fmax[e] <= f[e, t, o] <= Fmax[e])
    
    # DC power flow for candidate lines (with Big-M)
    @constraint(model, [l in L, t in T, o in O], 
        fl[l, t, o] - (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] <= M * (1 - sum(β[l, τ] for τ in 1:t)))
    @constraint(model, [l in L, t in T, o in O], 
        (θ[frn[l], t, o] - θ[ton[l], t, o]) / xl[l] - fl[l, t, o] <= M * (1 - sum(β[l, τ] for τ in 1:t)))
    
    # Candidate line capacity limits
    @constraint(model, [l in L, t in T, o in O], -Fmaxl[l] * sum(β[l, τ] for τ in 1:t) <= fl[l, t, o])
    @constraint(model, [l in L, t in T, o in O], fl[l, t, o] <= Fmaxl[l] * sum(β[l, τ] for τ in 1:t))
    
    # Reference bus
    @constraint(model, [t in T, o in O], θ[first(B), t, o] == 0.0)
end

# ==============================================================================
# Add Single Node Constraints - Copper Plate
function add_single_node_constraints!(model, sets, params)
    G, K, D, T, O = sets.G, sets.K, sets.D, sets.T, sets.O
    pg, pk = model[:pg], model[:pk]
    Pd = params.Pd
    
    # Simple power balance: total generation = total load
    @constraint(model, demand[t in T, o in O],
        sum(pg[g, t, o] for g in G) + sum(pk[k, t, o] for k in K) == sum(Pd[d] for d in D)
    )
end

# ==============================================================================
# Set Objective Function
function set_tep_objective!(model, config::TEPConfig, sets, params)
    G, K, L, T, O = sets.G, sets.K, sets.L, sets.T, sets.O
    α, ρ = sets.α, sets.ρ
    pg, pk, pkmax, β = model[:pg], model[:pk], model[:pkmax], model[:β]
    Pgcost, Pkcost, Pkinv, Flinv = params.Pgcost, params.Pkcost, params.Pkinv, params.Flinv
    
    # Operating costs
    op_cost = sum(
        α[t] * sum(
            ρ[o] * (
                sum(Pgcost[g] * pg[g, t, o] for g in G) +
                sum(Pkcost[k] * pk[k, t, o] for k in K)
            ) for o in O
        ) for t in T
    )
    
    # Investment costs
    if config.include_network
        inv_cost = sum(
            α[t] * (
                sum(Pkinv[k] * pkmax[k, t] for k in K) +
                sum(Flinv[l] * β[l, t] for l in L)
            ) for t in T
        )
    else
        inv_cost = sum(α[t] * sum(Pkinv[k] * pkmax[k, t] for k in K) for t in T)
    end
    
    @objective(model, Min, op_cost + inv_cost)
end

# ==============================================================================
# Build Complete TEP Model
function build_tep_model(config::TEPConfig, data)
    # Process data
    sets = process_tep_sets(data)
    params = process_tep_params(data)
    
    # Initialize model
    model = Model(config.solver)
    
    # Add variables
    add_tep_variables!(model, config, sets)
    
    # Add constraints
    add_generation_constraints!(model, sets, params)
    add_investment_constraints!(model, sets)
    
    if config.include_network
        add_network_constraints!(model, config, sets, params)
    else
        add_single_node_constraints!(model, sets, params)
    end
    
    # Set objective
    set_tep_objective!(model, config, sets, params)
    
    return model, sets, params
end


# ==============================================================================
# Solve
function solve_tep!(model, config::TEPConfig, sets, params)
    optimize!(model)
    status = termination_status(model)
    
    if status == MOI.OPTIMAL
        println("✓ Optimal solution found")
        println("  Total cost: \$", round(objective_value(model), digits=2))
        println("  Solver time (s): ", round(solve_time(model), digits=2))
    else
        println("✗ No optimal solution found. Status: ", status)
    end
    
    return status
end

function report_tep_solution(model, config::TEPConfig, sets, params)
    G, K, L, E, T, O = sets.G, sets.K, sets.L, sets.E, sets.T, sets.O
    pg, pk, pkmax, β = model[:pg], model[:pk], model[:pkmax], model[:β]
    
    tshow = last(T)
    oshow = first(O)
    
    println("")

    println("Generation dispatch (t=$tshow, o=$oshow):")
    for g in G
        println("  Gen $g: ", round(value(pg[g, tshow, oshow]), digits=2), " MW")
    end
    
    println("Candidate generation (t=$tshow):")
    for k in K
        cap = round(value(sum(pkmax[k, τ] for τ in 1:tshow)), digits=2)
        dispatch = round(value(pk[k, tshow, oshow]), digits=2)
        println("  Cand Gen $k: $dispatch MW (Capacity: $cap MW)")
    end
    
    if config.include_network
        f, fl = model[:f], model[:fl]
        
        println("Line investments (t=$tshow):")
        for l in L
            built = value(sum(β[l, τ] for τ in 1:tshow)) > 0.5
            println("  Line $l: ", built ? "Built" : "Not built")
        end
        
        println("Line flows (t=$tshow, o=$oshow):")
        for e in E
            println("  Existing Line $e: ", round(value(f[e, tshow, oshow]), digits=2), " MW")
        end
        for l in L
            println("  Candidate Line $l: ", round(value(fl[l, tshow, oshow]), digits=2), " MW")
        end
    end
end
