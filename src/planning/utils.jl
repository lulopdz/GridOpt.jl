# ==============================================================================
# This file contains utility functions for planning problems 
# in the GridOpt.jl package.

# ==============================================================================
# This function maps generators to their respective nodes.
# It takes a vector of generators, a vector of nodes, and a range of node 
# indices, # and returns a dictionary where each node index maps to a vector 
# of generators. 
# This is useful for converting the format of the data from the dictionary 
# to a format in the math model.
function map_nodes(gens::Vector{Int}, nodes::Vector{Int}, node_range::UnitRange{Int})
    node_gens = Dict{Int, Vector{Int}}(node => Int[] for node in node_range)
    # Group generators by nodes
    for (gen, node) in zip(gens, nodes)
        push!(node_gens[node], gen)
    end

    return node_gens
end

# ==============================================================================
function static_format(cand, exist, demands)
    # Transform candidate data
    new_cand = Dict(
        :ID => cand[:ID],
        :Prod_cost => [cost[end] for cost in cand[:Prod_cost]],
        :Inv_cost => [cost[end] for cost in cand[:Inv_cost]],
        :Prod_cap => [cap[end] for cap in cand[:Prod_cap]]
    )

    # Transform existing generators data
    new_exist = Dict(
        :ID => exist[:ID],
        :Max_cap => exist[:Max_cap],
        :Prod_cost => [cost[end] for cost in exist[:Prod_cost]]
    )

    # Transform demand data
    new_demands = Dict(
        :ID => demands[:ID],
        :Load => [load[end] for load in demands[:Load]]
    )

    return new_cand, new_exist, new_demands
end

function dynamic_format(cand, exist, demands)
    # Transform candidate data
    new_cand = Dict(
        :ID => cand[:ID],
        :Prod_cost => cand[:Prod_cost],
        :Inv_cost => cand[:Inv_cost],
        :Prod_cap => cand[:Prod_cap]
    )

    # Transform existing generators data
    new_exist = Dict(
        :ID => exist[:ID],
        :Max_cap => exist[:Max_cap],
        :Prod_cost => exist[:Prod_cost]
    )

    # Transform demand data
    new_demands = Dict(
        :ID => demands[:ID],
        :Load => demands[:Load]
    )

    return new_cand, new_exist, new_demands
end

function static_net_format(cand, exist, lines, demands)
    # Transform candidate data
    new_cand = Dict(
        :ID => cand[:ID],
        :Node => cand[:Node],
        :Prod_cost => [cost[end] for cost in cand[:Prod_cost]],
        :Inv_cost => [cost[end] for cost in cand[:Inv_cost]],
        :Prod_cap => [cap[end] for cap in cand[:Prod_cap]]
    )

    # Transform existing generators data
    new_exist = Dict(
        :ID => exist[:ID],
        :Node => exist[:Node],
        :Max_cap => exist[:Max_cap],
        :Prod_cost => [cost[end] for cost in exist[:Prod_cost]]
    )

    # Transform lines data (no change needed)
    new_lines = lines

    # Transform demand data
    new_demands = Dict(
        :ID => demands[:ID],
        :Node => demands[:Node],
        :Load => [load[end] for load in demands[:Load]]
    )

    return new_cand, new_exist, new_lines, new_demands
end