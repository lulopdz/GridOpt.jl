# src/concrete/sets.jl
# ==============================================================================
# Process Data and Create Sets
function process_tgep_sets(data)
    nodes, gen, load, line = data[:nodes], data[:gen], data[:load], data[:line]
    gcand, tcand = data[:gcand], data[:tcand]
    sto, stocand = data[:sto], data[:stocand]
    econ, sce = data[:econ], data[:sce]
    
    # Sets and Indices
    B = nodes[!, :id]
    D = load[!, :id]
    E = line[!, :id]
    
    G = gen[!, :id]
    K = gcand[!, :id]
    S = sto[!, :id]
    Sk = stocand[!, :id]
    L = tcand[!, :id]
    
    T = econ[!, :t]
    O = unique(sce[!, :hour])
    
    # Node mappings
    Bmap = Dict(nodes.node_code .=> nodes.id)
    ncode = Dict(nodes.id .=> nodes.node_code)

    # Slack set: bus where the largest installed generator is connected
    b_sl = nrow(gen) > 0 ? Bmap[gen.node_code[argmax(gen.capacity_mw)]] : first(B)
    Slack = [b_sl]
    
    # ==========================================================================
    # Grouping
    function group_by_bus(df, bus_keys)
        # Initialize an empty array of the correct ID type for every bus
        id_type = eltype(df[!, :id])
        grouped = Dict(b => id_type[] for b in bus_keys)
        
        for r in eachrow(df)
            bus_id = get(Bmap, r.node_code, nothing)
            if bus_id !== nothing
                push!(grouped[bus_id], r.id)
            else
                @warn "Node code $(r.node_code) in $(r.id) not found in nodes data."
            end
        end
        return grouped
    end
    
    # Sets grouped by bus (Fast execution)
    Ωg = group_by_bus(gen, B)
    Ωk = group_by_bus(gcand, B)
    Ωd = group_by_bus(load, B)
    Ωs = group_by_bus(sto, B)
    Ωsk = group_by_bus(stocand, B)

    # Line topology
    fr  = Dict(r.id => Bmap[r.node_code_st] for r in eachrow(line))
    to  = Dict(r.id => Bmap[r.node_code_en] for r in eachrow(line))
    frn = Dict(r.id => Bmap[r.node_code_st] for r in eachrow(tcand))
    ton = Dict(r.id => Bmap[r.node_code_en] for r in eachrow(tcand))
    
    return Dict{Symbol, Any}(
        :B => B,
        :G => G,
        :D => D,
        :E => E,
        :K => K,
        :L => L,
        :S => S,
        :Sk => Sk,
        :T => T,
        :O => O,
        :Slack => Slack,
        :Ωg => Ωg,
        :Ωk => Ωk,
        :Ωd => Ωd,
        :Ωs => Ωs,
        :Ωsk => Ωsk,
        :fr => fr,
        :to => to,
        :frn => frn,
        :ton => ton,
    )
end