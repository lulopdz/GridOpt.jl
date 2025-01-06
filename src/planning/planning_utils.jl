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