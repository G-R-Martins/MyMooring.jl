
module Analysis

using Statistics
using StatsBase
using SQLite
using Dates
using DataFrames

using ..AuxFunc
using ..Database
using ..LogOptions

struct LoadFactor
    mean::Float64
    dyn::Float64
end
const load_factors = Dict{String, LoadFactor}()

function set_load_factors(cc::Int = 1)
    # ! TROCADOS ?
    load_factors["ULS"] = cc == 1 ? LoadFactor(1.3, 1.75) : LoadFactor(1.5, 2.2)
    load_factors["ALS"] = cc == 1 ? LoadFactor(1.0, 1.1) : LoadFactor(1.0, 1.25)
end


function do_verifications(
    db::SQLite.DB,
    limit_states::Vector{String},
    to_analyze::Dict{Symbol, Dict{String, Dict{String, DataFrame}}},
)
    t0 = now()
    LogOptions.add_message(
        "Checking mooring system",
        new_status = LogOptions.task_inprogress,
        log_type = :calc,
        level = 1,
    )

    for ls in limit_states

        # LogOptions.add_message("$ls", log_type = :loading, level = 1)

        # Initialize SQLite table
        create_result_tables(db, ls)

        # load and extract statistics of simulations
        eval_simulations_stats(ls, to_analyze)

        # evaluate dynamic tensions for lines and offset/motion for platforms
        eval_limit_state(db, ls, to_analyze)


        Database.add_summary_to_tables(ls)
    end

    LogOptions.add_message(
        "Elapsed time to check the mooring system: \n$(canonicalize(now()-t0))",
        new_status = LogOptions.task_done,
    )
end


function create_result_tables(db::SQLite.DB, ls::AbstractString)
    # Intermediate results -> dynamic tension statistics 
    AuxFunc.createtable!(
        db,
        "$(ls)_Line_Statistics",
        Tables.Schema(
            [
                "LC_ID",
                "Sim_ID",
                "Line_ID",
                "Element",
                "Max",
                "Mean",
                "Min",
                "Std",
                "CV_percent",
                "Skewness",
                "Kurtosis",
                "Max_Dyn_Amplification_Factor",
            ],
            vcat(repeat([Integer], 3), [AbstractString], repeat([Float64], 8)),
        ),
        temp = false,
        ifnotexists = true,
    )

    # Intermediate results -> offsets and rotations
    AuxFunc.createtable!(
        db,
        "$(ls)_Motion_Statistics",
        Tables.Schema(
            [
                "LC_ID",
                "Sim_ID",
                "Component",
                "ID",
                "Quantity",
                "Mean",
                "Max",
                "Min",
                "Std",
                "CV_percent",
                "Skewness",
                "Kurtosis",
            ],
            [
                Integer,
                Integer,
                AbstractString,
                Integer,
                AbstractString,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
            ],
        ),
        temp = false,
        ifnotexists = true,
    )

    return nothing
end


function eval_simulations_stats(
    ls::String,
    to_analyze::Dict{Symbol, Dict{String, Dict{String, DataFrame}}},
)
    LogOptions.add_message("Calculating statistics of simulations.", log_type = :calc, level = 2)

    if !isempty(to_analyze[:lines][ls])
        calc_stats_line_tension(ls, to_analyze[:lines][ls])
    end
    if !isempty(to_analyze[:platforms][ls])
        calc_platform_motion_stats(ls, to_analyze[:platforms][ls])
    end
    Database.set_stats_table(ls)

    return nothing
end


function eval_limit_state(
    db::SQLite.DB,
    ls::String,
    to_analyze::Dict{Symbol, Dict{String, Dict{String, DataFrame}}},
)
    LogOptions.add_message("Evaluating $(ls)", log_type = :calc, level = 1)

    if ls[1] === 'U' || ls[1] === 'A'
        if !isempty(to_analyze[:lines][ls])
            check_design_tension(db, ls, to_analyze[:lines][ls])
        end
        if !isempty(to_analyze[:platforms][ls])
            check_platform_motion(db, ls, to_analyze[:platforms][ls])
        end
    else
        # TODO: check_FLS();
    end

    return nothing
end


function calc_stats_line_tension(ls::String, to_analyze::Dict{String, DataFrame})
    rows = Vector{String}()

    time_series_table = "$(ls)_Line_Tensions"

    for (lc, lc_df) in to_analyze
        lc_id = Database.get_lc_id_from_name(ls, lc; from_db = true)
        for ((sim,), sim_df) in pairs(groupby(lc_df, [:Sim_ID]))
            cols = AuxFunc.join_with_comma(get_line_cols_to_analyze(sim_df))
            data = Database.get_simulation_results(cols, time_series_table, ls, lc_id, sim)
            push!(rows, calc_simulation_tension_stats(data, sim_df, lc_id))
        end
    end  # for 'load cases'

    Database.insert_values("$(ls)_Line_Statistics", AuxFunc.join_with_comma(rows))

    return nothing
end

get_line_cols_to_analyze(df::AbstractDataFrame) = "Line" .* string.(df.Line) .* "_" .* df.Element


function calc_simulation_tension_stats(df_data::DataFrame, df_sim::SubDataFrame, lc_id::Int)
    return map(eachrow(df_sim)) do r
        col_data = df_data[!, "Line$(r.Line)_$(r.Element)"]

        mean_tension = mean(col_data)
        max_tension = maximum(col_data)
        """
        (
            $lc_id, $(r.Sim_ID), $(r.Line), '$(r.Element)',
            $max_tension, $mean_tension,
            $(minimum(col_data)),
            $(round(std(col_data), digits=3)),
            $(round(variation(col_data), digits=4)*100.0),
            $(round(skewness(col_data), digits=3)),
            $(round(kurtosis(col_data), digits=3)),
            $(max_tension/mean_tension)
        )
        """
    end |> AuxFunc.join_with_comma
end

function get_LCs_to_analyze(loaded::DataFrame, to_analyze::Dict{String, DataFrame})
    lc_names = unique!(to_analyze |> keys |> collect)
    return subset(loaded, :LC_Name => ByRow(lc -> lc in lc_names))
end


function check_design_tension(db::SQLite.DB, ls::String, to_analyze::Dict{String, DataFrame})
    # Collect line elements with result verified
    all_elements_verified = Database.get_summary_of_line_tension(ls)

    # Resistances
    S_mbs = get_resistances(db)
    # Load factors
    γ = load_factors[ls]

    ls_stats = Database.loaded[:stats]["$(ls)_Line_Statistics"]

    for ((lc_id,), lc_data) in pairs(groupby(Database.get_line_statistics(ls), :LC_ID))
        lc = Database.get_lc_name_from_id(lc_id)

        # Ignore LC already fully analyzed 
        !haskey(to_analyze, lc) && continue

        verified = all_elements_verified[all_elements_verified.LC .== lc_id, :]

        lc_stats = ls_stats[ls_stats.LC_ID .== lc_id, [:Line_ID, :Element, :Max, :Mean]]

        for ((line, elem), data) in pairs(groupby(lc_data, [:Line_ID, :Element]))
            df = to_analyze[lc]
            # Skip line element if not in list to analyze
            isempty(df[df.Line .== 1 .&& df.Element .== elem, :]) && continue

            # Get statistics of the line element  
            line_stats =
                lc_stats[lc_stats.Line_ID .== line .&& lc_stats.Element .== elem, [:Max, :Mean]]

            # Check if is a new result or something to be updated ...
            if !isempty(verified[verified.Line .== line .&& verified.Element .== elem, :])
                push!(
                    Database.query_str_values["Design_Tension_Summary"][:update],
                    get_str_to_update_Td(line, elem, lc_id, line_stats, S_mbs[line][elem], γ),
                )
            else # ... or if is a new row to be inserted
                push!(
                    Database.query_str_values["Design_Tension_Summary"][:insert],
                    get_str_to_insert_Td(line, elem, lc_id, ls, line_stats, S_mbs[line][elem], γ),
                )
            end
        end
    end

    return nothing
end

function get_Td_with_components(tension_stats, γ)
    # Mean_Tension = load factor × mean of Mean_Tensions (which ~ideally~ are all the same)
    mean_sim_tension = mean(tension_stats.Mean)  # before load factor
    mean_tension = γ.mean * mean_sim_tension

    # Dynamic tension
    max_tensions = tension_stats.Max .- mean_sim_tension
    dyn_tension = γ.dyn * (mean(max_tensions) - 0.45std(max_tensions))

    return mean_tension + dyn_tension, mean_tension, dyn_tension
end

function get_str_to_insert_Td(
    line::Int,
    elem::String,
    lc::Int,
    ls::String,
    tension_stats::DataFrame,
    S_mbs::Float64,
    load_factors,
)
    Td, mean_tension, dyn_tension = get_Td_with_components(tension_stats, load_factors)
    return "(
        $lc, \'$ls\', $line, \'$elem\',
        $mean_tension, $dyn_tension,
        $S_mbs, $Td, 
        $(Td/S_mbs), $(S_mbs/Td),
        \'$(S_mbs > Td ? "ok" : "failed")\'
    )"
end

function get_str_to_update_Td(
    line::Int,
    elem::String,
    lc::Int,
    tension_stats::DataFrame,
    S_mbs::Float64,
    γ,
)
    Td, mean_tension, dyn_tension = get_Td_with_components(tension_stats, γ)
    return "(
        $lc, $line, \'$elem\',
        $mean_tension, $dyn_tension,
        $S_mbs, $Td, 
        $(Td/S_mbs), $(S_mbs/Td), 
        \'$(S_mbs > Td ? "ok" : "failed")\'
    )"
end


function get_str_to_update_motion(
    platf::Int,
    dof::String,
    lc::Int,
    ls::String,
    motion_stats::DataFrame,
    allowed::Float64,
)
    return """(
        $lc, '$ls', 'platform', $platf, $dof,
        $(motion_stats[!,:Max] |> maximum), $(allowed)
    )"""
end


function get_str_to_insert_motion(
    platf::Int,
    dof::String,
    lc::Int,
    ls::String,
    motion_stats::DataFrame,
    allowed::Float64,
)

    max_motion = motion_stats[!, :Max] |> maximum
    min_motion = motion_stats[!, :Min] |> minimum

    return """(
        $lc, '$ls', 'platform', $platf, '$dof',
        $max_motion, $min_motion, $allowed,
        '$((abs(max_motion) < allowed && abs(min_motion) < allowed
            ) ? "ok" : "failed")'
    )"""
end



get_platf_cols_to_analyze(df::AbstractDataFrame) =
    map(eachrow(df)) do row
        # Common predicate
        pred = "Platform$(row.Platform)_"

        row.Quantity == "Offset" ? "$(pred)Surge,$(pred)Sway" : "$(pred)$(row.Quantity)"
    end |>
    unique! |>
    AuxFunc.join_with_comma


function check_platform_motion(db::SQLite.DB, ls::String, to_analyze::Dict{String, DataFrame})
    # Collect platform with results verified
    all_dofs_verified = Database.get_summary_of_motion(ls)

    # Allowed motion
    allowed_motion = get_motion_limit(db)


    ls_stats = Database.loaded[:stats]["$(ls)_Motion_Statistics"]

    for ((lc_id,), lc_data) in pairs(groupby(Database.get_motion_statistics(ls), :LC_ID))
        lc = Database.get_lc_name_from_id(lc_id)

        # Ignore LC already fully analyzed  
        !haskey(to_analyze, lc) && continue

        verified = all_dofs_verified[all_dofs_verified.LC .== lc_id, :]

        lc_stats = ls_stats[ls_stats.LC_ID .== lc_id, [:ID, :Quantity, :Max, :Min, :Mean]]

        for ((platf, dof), data) in pairs(groupby(lc_data, [:ID, :Quantity]))
            df = to_analyze[lc]
            # Skip line element if not in list to analyze
            isempty(df[df.Platform .== platf .&& df.Quantity .== dof, :]) && continue

            # Get statistics of the line element  
            motion_stats =
                lc_stats[lc_stats.ID .== platf .&& lc_stats.Quantity .== dof, [:Max, :Mean, :Min]]
            # allowed_motion.ID .== platf .&& allowed_motion.Quantity .== "Offset", 
            allowed = allowed_motion[
                allowed_motion.ID .== platf .&& allowed_motion.Quantity .== dof,
                :Value,
            ]

            # Check wheter is something to be updated ...
            if !isempty(verified[verified.ID .== platf .&& verified.Quantity .== dof, :])
                push!(
                    Database.query_str_values["Motion_Summary"][:update],
                    get_str_to_insert_motion(platf, dof, lc_id, ls, motion_stats, allowed[1]),
                )
            else # ... or a new row to be inserted
                push!(
                    Database.query_str_values["Motion_Summary"][:insert],
                    get_str_to_insert_motion(platf, dof, lc_id, ls, motion_stats, allowed[1]),
                )
            end
        end
    end

    return nothing
end


function calc_platform_motion_stats(ls::AbstractString, to_analyze::Dict{String, DataFrame})
    rows = Vector{String}()

    # Join strings to insert all data once for a load case
    for (lc, lc_df) in to_analyze
        lc_id = Database.get_lc_id_from_name(ls, lc; from_db = true)
        # Iterate over the simulations ...
        for ((sim,), sim_df) in pairs(groupby(lc_df, [:Sim_ID]))
            cols = get_platf_cols_to_analyze(sim_df)
            data = Database.get_simulation_results(cols, "$(ls)_Platform_Motion", ls, lc_id, sim)
            push!(rows, calc_motion_stats(data, sim_df, lc_id))
        end
    end
    Database.insert_values("$(ls)_Motion_Statistics", AuxFunc.join_with_comma(rows))
    return nothing
end

function calc_motion_stats(df_data::DataFrame, df_sim::SubDataFrame, lc_id::Int)
    return map(eachrow(df_sim)) do r
        # Common predicate 
        pred = "Platform$(r.Platform)_"
        # Variable to evaluate
        var_ = r.Quantity

        data =
            var_ == "Offset" ? calc_offset(df_data[!, ["$(pred)Surge", "$(pred)Sway"]]) :
            df_data[!, "$(pred)$var_"]

        """
        (
            $lc_id, 
            $(r.Sim_ID), 
            'platform', 
            $(r.Platform), 
            '$(var_)', 
            $(mean(data)), 
            $(maximum(data)),
            $(minimum(data)),
            $(round(std(data), digits=3)),
            $(round(variation(data), digits=4)*100.0),
            $(round(skewness(data), digits=3)),
            $(round(kurtosis(data), digits=3))
        )
        """
    end |> AuxFunc.join_with_comma

end

calc_offset(df::AbstractDataFrame) = @. sqrt(df[!, 1]^2 + df[!, 2]^2)

function get_resistances(db::SQLite.DB)::Dict{Int, Dict{String, Real}}
    mbs = Dict()
    data = groupby(
        DBInterface.execute(
            db,
            "SELECT ID, Element, Value FROM Resistances WHERE Object = 'Line';",
        ) |> DataFrame,
        "ID",
    )

    for line_data in data
        mbs[line_data[1, 1]] = Dict(zip(line_data.Element, line_data.Value))
    end

    return mbs
end




function get_motion_limit(db::SQLite.DB; type = "Platform")

    return DBInterface.execute(
        db,
        """
        SELECT ID, Quantity, Value 
        FROM Movement_Limitation 
        WHERE Object = '$(type)';
        """,
    ) |> DataFrame

end


end # module
