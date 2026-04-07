using Printf
using Plots
using DataFrames, CSV

include("../utils/plot_defaults.jl")
include("../reporting/tgep_csv.jl")
include("../reporting/tgep_plots.jl")
set_theme()

# ==============================================================================
function summarize_results(model, cfg::TEPConfig, sets, params; save_to::Union{String,Nothing}=nothing)
    println("\n" * "="^50)
    println("             TEGP - RESULTS SUMMARY")
    println("="^50)

    # 1. Physics view: annual demand and supply split
    yearly = yearly_supply_demand(model, sets, params)
    fmt2(x) = Printf.@sprintf("%.2f", x)
    fmtc(x) = replace(fmt2(x), r"(?<=\d)(?=(\d{3})+\.)" => ",")
    fmtcol(x, w=12) = lpad(fmtc(x), w)

    println("\n⚡ DEMAND AND GENERATION BY YEAR")
    println("="^50)
    println("Y  | Demand (GWh) | Ex gen (GWh) | Ca gen (GWh) | Total (GWh)  | Gap (GWh)")
    for row in eachrow(yearly)
        println("$(row.year)  | $(fmtcol(row.demand_gwh)) | $(fmtcol(row.existing_gen_gwh)) | $(fmtcol(row.candidate_gen_gwh)) | $(fmtcol(row.total_supply_gwh)) | $(fmtcol(row.balance_gap_gwh))")
    end

    # 2. Re-activated Cost Breakdown (Using the new 3-column summary)
    costs = cost_breakdown(model, cfg, sets, params)
    println("\n📊 COST BREAKDOWN")
    println("="^50)
    
    current_category = ""
    for row in eachrow(costs.summary)
        # Print category headers if it changes
        if row.Category != current_category && row.Category != "System Total"
            println("\n[$(row.Category)]")
            current_category = row.Category
        end
        
        # Format the printout based on whether it's a subtotal, total, or line item
        if row.Subcategory == "SUBTOTAL"
            println("  $(rpad("--> Subtotal", 30)) \$$(fmtc(row.Cost))")
        elseif row.Subcategory == "GRAND TOTAL"
            println("-"^50)
            println("  $(rpad("GRAND TOTAL COST", 30)) \$$(fmtc(row.Cost))")
        else
            println("  $(rpad(row.Subcategory, 30)) \$$(fmtc(row.Cost))")
        end
    end

    # 3. Generation Investments
    cap = gen_inv_df(model, sets, params)
    built_cap = filter(row -> row.added_mw > 0.01, cap)
    if nrow(built_cap) > 0
        println("\n⚡ GENERATION CAPACITY INVESTMENTS")
        println("="^50)
        if nrow(built_cap) <= 10
            for row in eachrow(built_cap)
                println("  Year $(row.year), Gen $(row.gen_id): $(row.added_mw) MW (\$$(fmtc(row.inv_cost)))")
            end
        else
            println("  $(nrow(built_cap)) build decisions found. Showing yearly summary:")
            yearly_cap = combine(groupby(built_cap, :year),
                :gen_id => length => :units_built,
                :added_mw => sum => :added_mw,
                :inv_cost => sum => :inv_cost)
            sort!(yearly_cap, :year)
            for row in eachrow(yearly_cap)
                println("  Year $(row.year): $(row.units_built) builds, $(round(row.added_mw, digits=2)) MW added (\$$(fmtc(row.inv_cost)))")
            end
        end
    end

    # 4. Storage Investments
    storage = sto_inv_df(model, sets, params) # Assumes you renamed this based on your snippet
    built_storage = filter(row -> row.added_mwh > 0.01, storage)
    if nrow(built_storage) > 0
        println("\n🔋 STORAGE CAPACITY INVESTMENTS")
        println("="^50)
        if nrow(built_storage) <= 10
            for row in eachrow(built_storage)
                println("  Year $(row.year), Storage $(row.storage_id): $(row.added_mwh) MWh (\$$(fmtc(row.inv_cost)))")
            end
        else
            println("  $(nrow(built_storage)) build decisions found. Showing yearly summary:")
            yearly_sto = combine(groupby(built_storage, :year),
                :storage_id => length => :units_built,
                :added_mwh => sum => :added_mwh,
                :inv_cost => sum => :inv_cost)
            sort!(yearly_sto, :year)
            for row in eachrow(yearly_sto)
                println("  Year $(row.year): $(row.units_built) builds, $(round(row.added_mwh, digits=2)) MWh added (\$$(fmtc(row.inv_cost)))")
            end
        end
    end

    # 5. Network Investments
    if cfg.include_network
        line = line_inv_df(model, cfg, sets, params)
        built_lines = filter(row -> row.built, line)
        println("\n🔌 TRANSMISSION LINE INVESTMENTS")
        println("="^50)
        if nrow(built_lines) > 0
            for row in eachrow(built_lines)
                println("  Year $(row.year), Line $(row.line_id): Built (\$$(fmtc(row.inv_cost)))")
            end
        else
            println("  None")
        end
    end

    !isnothing(save_to) && save_results(model, cfg, sets, params, save_to)
end

function save_results(model, cfg::TEPConfig, sets, params, out_dir::String)
    mkpath(out_dir)
    mkpath(joinpath(out_dir, "csv"))

    CSV.write(joinpath(out_dir, "csv", "inv_gen.csv"), gen_inv_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "inv_sto.csv"), sto_inv_df(model, sets, params))
    
    if cfg.include_network
        CSV.write(joinpath(out_dir, "csv", "inv_line.csv"), line_inv_df(model, cfg, sets, params))
        CSV.write(joinpath(out_dir, "csv", "op_flow_line.csv"), line_flow_df(model, cfg, sets, params))
    end

    CSV.write(joinpath(out_dir, "csv", "op_gen.csv"), gen_dispatch_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "op_ls.csv"), load_shedding_df(model, sets, params))
    CSV.write(joinpath(out_dir, "csv", "op_sto.csv"), sto_operation_df(model, sets, params))
    
    costs = cost_breakdown(model, cfg, sets, params)
    CSV.write(joinpath(out_dir, "csv", "cost_summary.csv"), costs.summary)
    CSV.write(joinpath(out_dir, "csv", "costs_yearly.csv"), costs.yearly)

    println("\n✓ Results saved to: $out_dir")
end

# ==============================================================================
function save_plots(model, cfg::TEPConfig, sets, params, dir::String)
    println("\nSaving plots...")
    pdir = joinpath(dir, "plots")
    mkpath(pdir)
    
    plot_new_cap_type(model, cfg, sets, params; pdf_path=joinpath(pdir, "cap_inv_type.pdf"))
    plot_total_cap_type(model, cfg, sets, params; pdf_path=joinpath(pdir, "cap_total_type.pdf"))

    plot_emissions_type(model, cfg, sets, params; pdf_path=joinpath(pdir, "emissions_type.pdf"))
    plot_hourly_dispatch(model, cfg, sets, params; pdf_path=joinpath(pdir, "hourly_dispatch.pdf"))
end
