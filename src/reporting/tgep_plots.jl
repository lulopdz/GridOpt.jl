# ==============================================================================
# TEPG Plots
function plot_new_cap_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    K, Sk, T = sets[:K], sets[:Sk], sets[:T]
    Sb = params[:Sbase]
    yrs = collect(T)

    ptype = get(params, :Pktype, Dict())
    ktyp(k) = lowercase(strip(string(get(ptype, k, "other"))))
    
    typs = sort(unique(ktyp.(K)))
    isempty(typs) && (typs = ["none"])

    col_legend = 1 + (length(typs) >= 4) + (length(typs) >= 8)

    pkmax_vals = value.(model[:pkmax])
    ekmax_vals = value.(model[:ekmax])

    # Generator Matrix (GW)
    cap_mat = [sum((pkmax_vals[k, t] for k in K if ktyp(k) == typ); init=0.0) * Sb / 1000.0 
               for t in yrs, typ in typs]

    # Storage Discharge Matrix (GW) - Assumes 4h duration
    sto_mat = [sum((ekmax_vals[s, t] / 4.0 for s in Sk); init=0.0) * Sb / 1000.0 for t in yrs]

    full_mat = hcat(cap_mat, sto_mat)
    
    stack_labels = [t == "none" ? "N/A" : titlecase(t) for t in typs]
    push!(stack_labels, "Storage")
    lbls = permutedims(stack_labels)

    y_max = isempty(full_mat) ? 1.0 : maximum(sum(full_mat, dims=2); init=0.0) * 1.2

    p = areaplot(
        yrs, full_mat,
        seriestype=:bar, label=lbls, lw=0, yformatter=:plain,
        legend=:outerright, legendcolumns=col_legend,
        xlabel="Year", ylabel="New Capacity Added (GW)", 
        ylims=(0, max(y_max, 0.5)) 
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end

function plot_total_cap_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    # Brought in D (Demand) and O (Hours) to calculate peak demand
    G, K, S, Sk, D, T, O = sets[:G], sets[:K], sets[:S], sets[:Sk], sets[:D], sets[:T], sets[:O]
    Sb = params[:Sbase]
    yrs = collect(T)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])
    col_legend = 1 + (length(typs) >= 4) + (length(typs) >= 8)

    pkmax_vals = value.(model[:pkmax])
    ekmax_vals = value.(model[:ekmax]) 

    # Base Generator Matrices (GW)
    ex_cap = [sum((params[:Pgmax][g] for g in G if gtyp(g) == typ); init=0.0) * Sb / 1000.0 for typ in typs]
    new_cap = [sum((pkmax_vals[k, t] for k in K if ktyp(k) == typ); init=0.0) * Sb / 1000.0 for t in yrs, typ in typs]
    gen_mat = permutedims(ex_cap) .+ cumsum(new_cap, dims=1)

    # Storage Power Estimation (GW)
    ex_sto_cap = sum((params[:Emax][s] / 4.0 for s in S); init=0.0) * Sb / 1000.0
    new_sto_cap = [sum((ekmax_vals[s, t] / 4.0 for s in Sk); init=0.0) * Sb / 1000.0 for t in yrs]
    sto_mat = ex_sto_cap .+ cumsum(new_sto_cap)

    full_mat = hcat(gen_mat, sto_mat)
    
    stack_labels = [t == "none" ? "N/A" : titlecase(t) for t in typs]
    push!(stack_labels, "Storage")
    lbls = permutedims(stack_labels)

    # Calculate Peak Demand (GW) to match the bar chart units
    peak_dem = [
        maximum(sum(params[:Pd][d] * params[:Pdf][(d, o)] * params[:Pdg][t] for d in D; init=0.0) * Sb / 1000.0 for o in O) 
        for t in yrs
    ]

    # Safe y-axis scaling limit (checks both supply capacity and peak demand)
    cap_max = isempty(full_mat) ? 1.0 : maximum(sum(full_mat, dims=2); init=0.0)
    dem_max = maximum(peak_dem; init=0.0)
    y_max = max(cap_max, dem_max) * 1.2

    # 1. Plot the stacked capacity bars
    p = areaplot(
        yrs, full_mat,
        seriestype=:bar, label=lbls, lw=0, yformatter=:plain,
        legend=:outerright, legendcolumns=col_legend,
        xlabel="Year", ylabel="Total Capacity (GW)",
        ylims=(0, max(y_max, 0.5))
    )

    # 2. Overlay the Peak Demand line
    scatter!(
        p, yrs, peak_dem,
        marker=:diamond, markersize=3, color=:black, label="Demand"
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end

function plot_hourly_dispatch(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    G, K, D, S, Sk, T, O = sets[:G], sets[:K], sets[:D], sets[:S], sets[:Sk], sets[:T], sets[:O]
    Sb = params[:Sbase]
    hrs = collect(O)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])
    pdf, pdg = params[:Pdf], params[:Pdg]
    
    # 1. Split labels into Positive and Negative to fix the stacking issue
    # (Also fixed the mismatch between the label order and matrix order)
    pos_labels = [typ == "none" ? "N/A" : titlecase(typ) for typ in typs]
    push!(pos_labels, "Sto Dis", "Load Shed") 
    pos_lbls = permutedims(pos_labels)

    neg_labels = ["Sto Ch"]
    neg_lbls = permutedims(neg_labels)

    # Dynamic legend columns (+1 accounts for the Demand line)
    dynamic_cols = cld(length(pos_labels) + length(neg_labels) + 1, 4)

    g_by_typ = Dict(typ => [g for g in G if gtyp(g) == typ] for typ in typs)
    k_by_typ = Dict(typ => [k for k in K if ktyp(k) == typ] for typ in typs)

    demand_base = [sum(params[:Pd][d] * pdf[(d, o)] for d in D; init=0.0) * Sb for o in hrs]

    plots = Dict{Any, Any}()
    demand_max = maximum(demand_base; init=0.0) * maximum(values(pdg); init=1.0)

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
    end

    # Grouped variable extraction
    pg_val, pk_val = value.(model[:pg]), value.(model[:pk])
    pdis_val, pdisk_val = value.(model[:pdis]), value.(model[:pdisk])
    pch_val, pchk_val = value.(model[:pch]), value.(model[:pchk])
    ls_val = value.(model[:ls])

    for t in T
        disp_core = [
            (sum((pg_val[g, t, o] for g in g_by_typ[typ]); init=0.0) +
             sum((pk_val[k, t, o] for k in k_by_typ[typ]); init=0.0)) * Sb
            for o in hrs, typ in typs
        ]

        dem = [demand_base[i] * pdg[t] for i in eachindex(hrs)]
        
        dis_sto = [
            (sum((pdis_val[s, t, o] for s in S); init=0.0) +
             sum((pdisk_val[s, t, o] for s in Sk); init=0.0)) * Sb
            for o in hrs
        ]
        
        ch_sto = [
            (sum((pch_val[s, t, o] for s in S); init=0.0) +
              sum((pchk_val[s, t, o] for s in Sk); init=0.0)) * Sb
            for o in hrs
        ]
        
        shed = [sum(ls_val[d, t, o] for d in D; init=0.0) * Sb for o in hrs]
        
        # 2. Split the matrix into positive and negative stacks
        pos_mat = hcat(disp_core, dis_sto, shed)
        neg_mat = hcat(-ch_sto)

        # 3. Cleaned up min/max calculation using the split matrices
        pos_stack = [sum(pos_mat[i, :]) for i in eachindex(hrs)]
        neg_stack = [sum(neg_mat[i, :]) for i in eachindex(hrs)]
        
        y_max = max(maximum(pos_stack; init=0.0), maximum(dem; init=0.0), demand_max) * 1.2
        y_min = min(minimum(neg_stack; init=0.0) * 1.2, 0.0)

        # 4. Plot positives first (Building UP from 0)
        p = areaplot(
            st=:steppre, 
            hrs, pos_mat,
            label=pos_lbls,
            legend=:outertop, lw=0,
            legendcolumns=dynamic_cols,    
            xlabel="Hour", ylabel="Dispatch (MW)", 
            yformatter=:plain,
            ylims=(y_min, y_max)
        )

        # 5. Plot negatives second (Building DOWN from 0)
        areaplot!(
            st=:steppre,
            p, hrs, neg_mat,
            label=neg_lbls,
            lw=0
        )

        # 6. Overlay the Demand
        plot!(
            st=:steppre,
            p, hrs, dem,
            lw=2, color=:black, label="Demand"
        )

        if !isnothing(pdf_path)
            base, ext = splitext(pdf_path)
            out_path = isempty(ext) ? "$(pdf_path)_t$(t).pdf" : "$(base)_t$(t)$(ext)"
            savefig(p, out_path)
            println("✓ Saved: $out_path")
        end

        plots[t] = p
    end
end

function plot_emissions_type(model, cfg::TEPConfig, sets, params; pdf_path::Union{String,Nothing}=nothing)
    haskey(model, :em_e) || return nothing
    
    G, K, T, O = sets[:G], sets[:K], sets[:T], sets[:O]
    ρ = params[:ρ]
    yrs = collect(T)

    pgtype = get(params, :Pgtype, Dict())
    pktype = get(params, :Pktype, Dict())
    
    gtyp(g) = lowercase(strip(string(get(pgtype, g, "other"))))
    ktyp(k) = lowercase(strip(string(get(pktype, k, "other"))))
    
    typs = sort(unique(vcat(gtyp.(G), ktyp.(K))))
    isempty(typs) && (typs = ["none"])
    
    # 1. Cleaned up labels and dynamic legend columns
    lbls = permutedims([typ == "none" ? "N/A" : titlecase(typ) for typ in typs])
    dynamic_cols = cld(length(typs), 4)

    # 2. Group generators once by type to avoid slow filtering inside loops
    g_by_typ = Dict(typ => [g for g in G if gtyp(g) == typ] for typ in typs)
    k_by_typ = Dict(typ => [k for k in K if ktyp(k) == typ] for typ in typs)

    # 3. Performance Optimization: Extract solver values once
    em_e_val = value.(model[:em_e])
    em_k_val = value.(model[:em_k])

    # Yearly emissions by type: sum across hours weighted by representative hour weight ρ
    em_mat = [
        sum((ρ[o] * em_e_val[g, t, o] for g in g_by_typ[typ] for o in O); init=0.0) +
        sum((ρ[o] * em_k_val[k, t, o] for k in k_by_typ[typ] for o in O); init=0.0)
        for t in yrs, typ in typs
    ]

    # Safe upper bound calculation
    y_max = isempty(em_mat) ? 1.0 : maximum(sum(em_mat, dims=2); init=0.0) / 1e6 * 1.2

    p = areaplot(
        yrs, em_mat / 1e6,  # Convert to MtCO2
        seriestype=:bar,
        label=lbls,
        lw=0, yformatter=:plain,
        legend=:outertop,
        legendcolumns=dynamic_cols,
        xlabel="Year", 
        ylabel="Emissions (MtCO2)",
        ylims=(0, max(y_max, 0.5))
    )

    if !isnothing(pdf_path)
        mkpath(dirname(pdf_path))
        savefig(p, pdf_path)
        println("✓ Saved: $pdf_path")
    end
end