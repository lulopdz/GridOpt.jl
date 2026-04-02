# src/concrete/tgep_concrete.jl
include("utils.jl")
include("sets.jl")
include("params.jl")
include("vars.jl")
include("constraints.jl")
include("objective.jl")

# ==============================================================================
# Build Complete TGEP Model
function build_tgep_model(config::TEPConfig, data)
    # Process data
    sets = process_tgep_sets(data)
    params = process_tgep_params(data, config)
    
    # Initialize model
    model = Model(config.solver)
    
    # Add variables
    add_investment_vars!(model, config, sets)
    add_operational_vars!(model, config, sets)
    add_slack_vars!(model, sets)
    if config.include_network
        add_network_vars!(model, config, sets)
    end

    # Add constraints
    add_generation_constraints!(model, sets, params)
    add_investment_constraints!(model, sets)

    # Add storage constraints
    add_storage_constraints!(model, sets, params)
    
    if config.include_network
        add_network_constraints!(model, config, sets, params)
    else
        add_single_node_constraints!(model, sets, params)
    end

    add_emissions_constraints!(model, config, sets, params)
    
    # Set objective
    set_tgep_objective!(model, config, sets, params)
    
    return model, sets, params
end

# ==============================================================================
# Solve
function solve_tgep!(model, config::TEPConfig, sets, params)
    optimize!(model)
    status = termination_status(model)
    
    if status == MOI.OPTIMAL || status == MOI.TIME_LIMIT
        gap = relative_gap(model)
        println("✓ Solution found (Status: $status)")
        println("  Total cost: \$", round(objective_value(model), digits=2))
        println("  Optimality gap: ", round(gap * 100, digits=2), "%")
        println("  Solver time (s): ", round(solve_time(model), digits=2))
    else
        println("✗ No optimal solution found. Status: ", status)
    end
    
    return status
end