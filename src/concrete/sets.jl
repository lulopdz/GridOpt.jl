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
    G = gen[!, :id]
    D = load[!, :id]
    E = line[!, :id]

    K = gcand[!, :id]
    L = tcand[!, :id]
    
    S = sto[!, :id]
    Sk = stocand[!, :id]

    T = econ[!, :t]
    O = sce[!, :hour]
    
    # Node mappings
    Bmap = Dict(nodes.node_code .=> nodes.id)
    ncode = Dict(nodes.id .=> nodes.node_code)

    # Slack set: bus where the largest installed generator is connected
    b_sl = nrow(gen) > 0 ? Bmap[gen.node_code[argmax(gen.capacity_mw)]] : first(B)
    Slack = [b_sl]
    
    # Items per bus
    items_b(df, b) = [df.id[i] for i in 1:nrow(df) if df.node_code[i] == ncode[b]]
    
    # Sets grouped by bus
    Ωg = Dict(b => items_b(gen, b) for b in B)
    Ωk = Dict(b => items_b(gcand, b) for b in B)
    Ωd = Dict(b => items_b(load, b) for b in B)
    Ωs = Dict(b => items_b(sto, b) for b in B)
    Ωsk = Dict(b => items_b(stocand, b) for b in B)

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
