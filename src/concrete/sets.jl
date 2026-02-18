
# ==============================================================================
# Process Data and Create Sets
function process_tgep_sets(data)
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
    Pdf = Dict(O .=> sce.demand_factor)

    Pdg = Dict(T .=> econ.demand_growth)
    α = Dict(T .=> econ.a)
    
    return (B=B, G=G, D=D, E=E, K=K, L=L, T=T, O=O, 
            Ωg=Ωg, Ωk=Ωk, Ωd=Ωd, 
            fr=fr, to=to, frn=frn, ton=ton, 
            ρ=ρ, Pdf=Pdf, Pdg=Pdg, α=α)
end
