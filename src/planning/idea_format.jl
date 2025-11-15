using DataFrames, XLSX, CSV

# ==============================================================================
# Load CAND table (candidate generators)
# ==============================================================================
pf = pwd()
ep = joinpath(pf, "GridOpt.jl/data/planning/EMH_network.xlsx")
xf = XLSX.readxlsx(ep)

# Load candidates
m = xf["cand"][:]
cand = DataFrame(m[2:end, :], :auto)
rename!(cand, Symbol.(m[1, :]))

# Load existing generators
m2 = xf["exist"][:]
exist = DataFrame(m2[2:end, :], :auto)
rename!(exist, Symbol.(m2[1, :]))

# Load New generation capacity results
res_path = joinpath(pf, "GridOpt.jl/results/emh/")
new_cap = CSV.read(res_path * "new_capacity.csv", DataFrame)
Sbase = 100 # MVA base
new_cap .= new_cap .* Sbase  # Convert to MW
exist[:, :Max_cap] .= exist[:, :Max_cap] .* Sbase  # Convert to MW

# Time periods
years = [2025, 2030, 2035, 2040, 2045, 2050]

# ==============================================================================
# Technology mapping: IAMC variable names
# ==============================================================================

# For New generation capacity (candidates)
tech_map_new = Dict(
    # Renewables
    "wind_onshore"   => "New Generation Capacity|Electricity|Wind|Onshore",
    "solar_PV"       => "New Generation Capacity|Electricity|Solar|PV",
    # Gas
    "NG_SC"          => "New Generation Capacity|Electricity|Gas|SC",
    "NG_CC"          => "New Generation Capacity|Electricity|Gas|CC",
    "NG_CG"          => "New Generation Capacity|Electricity|Gas|CG",
    "NG_CCS"         => "New Generation Capacity|Electricity|Gas|CCS",
    # Other
    "nuclear"        => "New Generation Capacity|Electricity|Nuclear",
    "biomass"        => "New Generation Capacity|Electricity|Biomass",
    "Biomass"        => "New Generation Capacity|Electricity|Biomass",
    "biogas"         => "New Generation Capacity|Electricity|Biogas",
    "oil_CT"         => "New Generation Capacity|Electricity|Oil|CT",
    "diesel_CT"      => "New Generation Capacity|Electricity|Oil|CT",
    "oil_ST"         => "New Generation Capacity|Electricity|Oil|ST",
    "MSW"            => "New Generation Capacity|Electricity|Biomass",
    "gasoline_CT"    => "New Generation Capacity|Electricity|Gasoline|CT",
)

# For Total generation capacity (existing and new)
tech_map_total = Dict(
    # Renewables
    "wind_onshore"   => "Total Generation Capacity|Electricity|Wind|Onshore",
    "solar_PV"       => "Total Generation Capacity|Electricity|Solar|PV",
    # Gas
    "NG_SC"          => "Total Generation Capacity|Electricity|Gas|SC",
    "NG_CC"          => "Total Generation Capacity|Electricity|Gas|CC",
    "NG_CG"          => "Total Generation Capacity|Electricity|Gas|CG",
    "NG_CCS"         => "Total Generation Capacity|Electricity|Gas|CCS",
    # Coal
    "coal"           => "Total Generation Capacity|Electricity|Coal",
    "coal_CCS"       => "Total Generation Capacity|Electricity|Coal|CCS",
    # Hydro
    "hydro_daily"    => "Total Generation Capacity|Electricity|Hydro|Daily",
    "hydro_run"      => "Total Generation Capacity|Electricity|Hydro|Run",
    "hydro_monthly"  => "Total Generation Capacity|Electricity|Hydro|Monthly",
    # Other
    "nuclear"        => "Total Generation Capacity|Electricity|Nuclear",
    "biomass"        => "Total Generation Capacity|Electricity|Biomass",
    "Biomass"        => "Total Generation Capacity|Electricity|Biomass",
    "biogas"         => "Total Generation Capacity|Electricity|Biogas",
    "oil_CT"         => "Total Generation Capacity|Electricity|Oil|CT",
    "diesel_CT"      => "Total Generation Capacity|Electricity|Oil|CT",
    "oil_ST"         => "Total Generation Capacity|Electricity|Oil|ST",
    "MSW"            => "Total Generation Capacity|Electricity|Biomass",
    "gasoline_CT"    => "Total Generation Capacity|Electricity|Gasoline|CT",
)

# ==============================================================================
# New generation capacity (Aggregated)
# ==============================================================================
iamc_new = DataFrame(
    model=String[], scenario=String[], region=String[],
    variable=String[], unit=String[], time=Int[], value=Float64[]
)

for (i, row) in enumerate(eachrow(new_cap))
    tech = cand.gen_type[i]
    if !haskey(tech_map_new, tech)
        continue
    end
    region = string(cand.province[i])
    variable_name = tech_map_new[tech]

    for (col_idx, year) in enumerate(years)
        value = row[col_idx]
        push!(iamc_new, ("PaCES", "BAU", region, variable_name, "MW", year, value))
    end
end

# Aggregate New generation capacity by province × tech × year
groupcols = [:model, :scenario, :region, :variable, :unit, :time]
iamc_new_agg = combine(groupby(iamc_new, groupcols), :value => sum => :value)
# ==============================================================================
# Total generation capacity (Existing + New, cumulative over time)
# ==============================================================================

# --- 1) EXISTING capacity in IAMC format (constant over time) ---
iamc_exist = DataFrame(
    model=String[], scenario=String[], region=String[],
    variable=String[], unit=String[], time=Int[], value=Float64[]
)

for row in eachrow(exist)
    tech = row.gen_type
    if haskey(tech_map_total, tech)
        variable_name = tech_map_total[tech]
        region = string(row.province)
        for year in years
            push!(iamc_exist, ("PaCES", "BAU", region, variable_name, "MW", year, row.Max_cap))
        end
    end
end


# --- 2) New generation capacity (already aggregated) ---
# iamc_new_agg has:
# model, scenario, region, variable, unit, time, value (new MW added in that year)
newcap_total = deepcopy(iamc_new_agg)
rename!(newcap_total, :value => :new_value)


# --- 3) Compute cumulative New generation capacity per (region, variable) ---

sort!(newcap_total, [:region, :variable, :time])

newcap_total.cum_value = similar(newcap_total.new_value)

for gdf in groupby(newcap_total, [:region, :variable])
    gdf.cum_value .= cumsum(gdf.new_value)
end


# --- 4) Rename for consistency and format as IAMC ---
iamc_new_cumulative = DataFrame(
    model = newcap_total.model,
    scenario = newcap_total.scenario,
    region = newcap_total.region,
    variable = [replace(v, "New Generation Capacity" => "Total Generation Capacity") for v in newcap_total.variable],
    unit = newcap_total.unit,
    time = newcap_total.time,
    value = newcap_total.cum_value
)


# --- 5) Combine existing + cumulative New generation capacity ---
iamc_total = vcat(iamc_exist, iamc_new_cumulative)

# Aggregate so that if some technologies overlap (rare but possible), they sum correctly
iamc_total_agg = combine(groupby(iamc_total, groupcols), :value => sum => :value)

# ==============================================================================
# MERGE BOTH into ONE FILE
# ==============================================================================
iamc_all = vcat(iamc_new_agg, iamc_total_agg)

outpath = "GridOpt.jl/results/idea/PaCES_BAU.csv"
CSV.write(outpath, iamc_all)

println("Saved!")
