
module Database

using SQLite, DataFrames, CSV, MAT
using OrderedCollections
using StringEncodings

using ..AuxFunc
using ..LogOptions

abstract type LineElement end
abstract type StructuralComponent end

struct Fairlead <: LineElement
    resistance::Float64
end

struct Anchor <: LineElement
    resistance::Float64
    vertical_load_is_limited::Bool  #TODO: verification not implemented!

    Anchor(resistance::Float64) = new(resistance, false)
end

struct Transition <: LineElement
    resistance::Float64
    prev_seg::Int
    next_seg::Int

    Transition(resistance::Float64, seg_id::Int) = new(resistance, seg_id, seg_id + 1)
end
struct Intermediate <: LineElement
    resistance::Float64
    element_id::Int
end

struct Line <: StructuralComponent
    id::Int
    elements::Vector{LineElement}
    is_shared::Bool  # TODO: shared lines is not fully implemented!

    Line(line_id::Int) = new(line_id, LineElement[], false)
    Line(line_id::Int, elements::Vector{LineElement}) = new(line_id, elements, false)
    Line(line_id::Int, isshared::Bool) = new(line_id, LineElement[], isshared)
end

struct Platform <: StructuralComponent
    id::Int
    ref_pos::Vector{Float64}
    max_offset::Float64
    max_disp::Vector{Float64}
    max_rot::Vector{Float64}
    is_degree::Bool
    vars2eval::@NamedTuple{
        Offset::Bool,
        Surge::Bool,
        Sway::Bool,
        Heave::Bool,
        Roll::Bool,
        Pitch::Bool,
        Yaw::Bool,
    }


    Platform(plat_id::Int, offset::Float64) = new(
        plat_id,
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        maxoffset,
        [0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0],
        true,
        get_platform_vars_to_eval(maxoffset),
    )
    Platform(plat_id::Int, ref::Vector{Float64}, maxoffset::Float64) = new(
        plat_id,
        ref,
        maxoffset,
        [0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0],
        true,
        get_platform_vars_to_eval(maxoffset),
    )
    Platform(plat_id::Int, ref::Vector{Float64}, maxoffset::Float64, maxrots::Vector{Float64}) =
        new(
            plat_id,
            ref,
            maxoffset,
            maxrots,
            true,
            get_platform_vars_to_eval(maxoffset, maxdisp, maxrots),
        )
    Platform(
        plat_id::Int,
        ref::Vector{Float64},
        maxoffset::Float64,
        maxdisp::Vector{Float64},
        maxrots::Vector{Float64},
        isdegree::Bool,
    ) = new(
        plat_id,
        ref,
        maxoffset,
        maxdisp,
        maxrots,
        isdegree,
        get_platform_vars_to_eval(maxoffset, maxdisp, maxrots),
    )
    Platform(
        plat_id::Int,
        ref::Vector{Float64},
        maxoffset::Float64,
        maxrots::Vector{Float64},
        isdegree::Bool,
    ) = new(
        plat_id,
        ref,
        maxoffset,
        [0.0, 0.0, 0.0],
        maxrots,
        isdegree,
        get_platform_vars_to_eval(maxoffset, [0.0, 0.0, 0.0], maxrots),
    )
end

function Base.show(io::IO, components::Vector{StructuralComponent})
    print(
        io,
        isa(components[1], Line) ? """Vector{Line <: StructuralComponent}:\n$(
        join([
            "  id=$(line.id), Elements=[$(join([
                match(r"[^.]*$", string(typeof(elem))).match for elem in line.elements
            ], 
            ", "))], is_shared=$(line.is_shared)"
            for line in components
        ], 
        ";\n")).""" :
        """Vector{Platform <: StructuralComponent}:$(
    join([
        "id=$(p.id), ref_pos=$(p.ref_pos), max_offset=$(p.max_offset), max_rot=$(p.max_rot), is_degree=$(p.is_degree), vars2eval=$(p.vars2eval)" 
        for p in components
    ], 
    ";\n")).""",
    )
end


#######################

db = SQLite.DB()

const to_analyze = Dict(
    :lines => Dict(
        "ULS" => Dict{String, DataFrame}(),
        "ALS" => Dict{String, DataFrame}(),
        "FLS" => Dict{String, DataFrame}(),
    ),
    :platforms => Dict(
        "ULS" => Dict{String, DataFrame}(),
        "ALS" => Dict{String, DataFrame}(),
        "FLS" => Dict{String, DataFrame}(),
    ),
)

const loaded = Dict{Symbol, Union{Dict, DataFrame}}(
    :lines => Dict{String, DataFrame}(),
    :platforms => Dict{String, DataFrame}(),
    :summary => DataFrame(),
    :components => Dict(:all => DataFrame(), :lines => DataFrame(), :platforms => DataFrame()),
)

const query_str_values = Dict(
    "Simulations_Summary" => Dict(:insert_or_replace => Vector{String}()),
    "Design_Tension_Summary" => Dict(:insert => Vector{String}(), :update => Vector{String}()),
    "Motion_Summary" => Dict(:insert => Vector{String}(), :update => Vector{String}()),
    "Components" => Dict(:insert => Vector{String}()),
    "Line_Elements" => Dict(:insert => Vector{String}()),
    "Resistances" => Dict(:insert => Vector{String}(), :update => Vector{String}()),
    "Platforms" => Dict(:insert => Vector{String}()),
    "Movement_Limitation" => Dict(:insert => Vector{String}(), :update => Vector{String}()),
)

const ls_monitors = Dict(
    "ULS" => Dict{Symbol, Vector{StructuralComponent}}(),
    "ALS" => Dict{Symbol, Vector{StructuralComponent}}(),
    "FLS" => Dict{Symbol, Vector{StructuralComponent}}(),
)

const ramp = Dict{String, Float64}("ULS" => 0.0, "ALS" => 0.0, "FLS" => 0.0)

#######################

function set_database(
    name::AbstractString,
    reset_database::Bool = false,
    db_dir::String = "database/",
)
    global db
    name = db_dir * name

    # Create database folder if it not exist
    isdir(db_dir) || mkdir(db_dir)
    
    if reset_database && isfile(name)
        LogOptions.add_message(
            "Reseting database file \"$(name)\"",
            new_status = LogOptions.task_inprogress,
        )
        rm(name, force = true)
        db = SQLite.DB(name)
        LogOptions.add_message("Database reseted sucessfully!", new_status = LogOptions.task_done)

        # set_data_loaded()
        return nothing
    end

    if isfile(name)
        LogOptions.add_message(
            "Database file \"$(name)\" already exists! Loading it",
            new_status = LogOptions.task_inprogress,
        )
        db = SQLite.DB(name)
        LogOptions.add_message("Database file was loaded", new_status = LogOptions.task_done)
        # set_data_loaded()
    else
        LogOptions.add_message(
            "Creating database file \"$(name)\"",
            new_status = LogOptions.task_inprogress,
        )
        db = SQLite.DB(name)
        LogOptions.add_message("Database file created", new_status = LogOptions.task_done)
        set_loaded_data(empty_db = true)
    end


    return nothing
end


set_ramp(inp::Dict{String, Float64}) = (foreach(x -> ramp[x.first] = x.second, inp))



function set_loaded_data(; empty_db = false)
    empty_db && set_empty_loaded_data()

    df = DataFrame(DBInterface.execute(db, "SELECT * FROM Simulations_Summary;"))
    loaded[:summary] = df

    for ls in unique(df.LimitState)
        loaded[:lines][ls] =
            DBInterface.execute(
                db,
                """
                SELECT
                    LC_Name AS LC,
                    Sim_Name AS Sim,
                    Line_Id AS ID,
                    Element
                FROM
                    $(ls)_Line_Statistics
                INNER JOIN 
                    Simulations_Summary 
                ON 
                    Simulations_Summary.LC_Id = $(ls)_Line_Statistics.LC_Id AND
                    Simulations_Summary.Sim_Id = $(ls)_Line_Statistics.Sim_Id;
                """,
            ) |>
            DataFrame |>
            unique!

        loaded[:platforms][ls] =
            DBInterface.execute(
                db,
                """
                SELECT
                    LC_Name AS LC,
                    Sim_Name AS Sim,
                    ID,
                    Quantity
                FROM
                    $(ls)_Motion_Statistics
                INNER JOIN 
                    Simulations_Summary 
                ON 
                    Simulations_Summary.LC_Id = $(ls)_Motion_Statistics.LC_Id AND 
                    Simulations_Summary.Sim_Id = $(ls)_Motion_Statistics.Sim_Id;
                """,
            ) |>
            DataFrame |>
            unique!

        set_stats_table(ls::String)
    end

    loaded[:components][:all] =
        DataFrame(DBInterface.execute(db, "SELECT * FROM Components")) |> unique!
    loaded[:components][:lines] =
        DataFrame(DBInterface.execute(db, "SELECT * FROM Line_Elements")) |> unique!
    loaded[:components][:platforms] =
        DataFrame(DBInterface.execute(db, "SELECT * FROM Platforms")) |> unique!


    return nothing
end

function set_empty_loaded_data()
    loaded[:summary] = DataFrame(
        :Sim_ID => Int[],
        :Sim_Name => String[],
        :LC_ID => Int[],
        :LC_Name => String[],
        :LimitState => String[],
    )

    ls = "ULS"
    loaded[:lines][ls] =
        DataFrame(:LC => String[], :Sim => String[], :ID => Int[], :Element => String[])
    loaded[:platforms][ls] =
        DataFrame(:LC => String[], :Sim => String[], :ID => Int[], :Quantity => String[])

    loaded[:components][:all] =
        DataFrame(:LimitState => String[], :Object => String[], :ID => Int[])
    loaded[:components][:lines] =
        DataFrame(:Line_ID => Int[], :Element => String[], :LimitState => String[])
    loaded[:components][:platforms] =
        DataFrame(:Platform_ID => Int[], :Quantity => String[], :LimitState => String[])

end

function set_stats_table(ls::String)
    tables = filter!(x -> occursin(Regex("(?=.*$ls).(?=.*Statistics)"), x), get_table_names())
    !haskey(loaded, :stats) && (loaded[:stats] = Dict{String, DataFrame}())

    for tbl in tables
        loaded[:stats][tbl] = DataFrame(DBInterface.execute(db, "SELECT * FROM $tbl"))
    end

    return nothing
end

function set_obj_parameters(monitors::Dict, resistance::Dict, mov_lim)::Bool
    use_same_resistance = check_which_objs_use_same_resistance(resistance)

    for (ls, ls_data) in monitors
        for (object_type, data) in ls_data
            if object_type === "lines"
                ls_monitors[ls][:lines] = set_line_monitors(data, resistance, use_same_resistance)
            elseif object_type === "platforms"
                ls_monitors[ls][:platforms] = set_platform_monitors(data, mov_lim)
            else
                #TODO
            end
        end

    end  # for (limit states) 

    return true
end


function set_platform_monitors(data, mov_lim)::Vector{Platform}
    platforms = Vector{Platform}()

    if isa(data, AbstractArray)
        #TODO
    elseif isa(data, AbstractDict)
        ids = AuxFunc.get_vector_or_range(data["ids"]) |> Vector{Int}
        # LogOptions.add_message("Creating platform(s): \n$(mov_lim["platforms"][ids[1]])", 
        # new_status = LogOptions.task_inprogress)
        platforms = [
            Platform(
                id,
                tuple(
                    getindex.(
                        Ref(mov_lim["platforms"][id]),
                        [
                            "reference",
                            "max offset",
                            "max translations",
                            "max rotations",
                            "is degree",
                        ],
                    )...,
                )...,
            ) for id in ids
        ]
        # LogOptions.add_message("Platform(s) created", new_status = LogOptions.task_done)
    end

    return platforms
end

get_platform(id::Int, ls::String) =
    for platform in ls_monitors[ls][:platforms]
        Platform_ID === id && return platform
    end

function set_line_monitors(data, resistance::Dict, use_same_resistance::NamedTuple)::Vector{Line}
    lines = Vector{Line}()

    if isa(data, AbstractArray)
        #TODO
    elseif isa(data, AbstractDict)
        for line_id in AuxFunc.get_vector_or_range(data["ids"])
            elements = data["elements"]
            line_elements = Vector{LineElement}()

            # I'm supposing one fairlead and anchor per line, thus NO SHARED LINE 
            # TODO: handle shared lines           
            for name in ["fairleads", "anchors"]
                (!haskey(elements, name) || (haskey(elements, name) && !elements[name])) && continue

                # resistance
                ϕ =
                    isa(resistance[name], AbstractArray) ? convert(Vector, resistance[name]) :
                    convert(Dict, resistance[name])

                data_type = name[1:(end - 1)] |> AuxFunc.title_and_symbol |> eval
                if getproperty(use_same_resistance, Symbol(name))
                    push!(line_elements, data_type(get_resistance(ϕ["MBS"])))
                else
                    push!(line_elements, data_type(get_resistance(ϕ, line_id)))
                end

            end

            push!(lines, Line(line_id, line_elements))

        end  # for
    end

    return lines
end


function check_which_objs_use_same_resistance(resistance::Dict)::NamedTuple
    # Construct a NamedTuple => (fairleads = true, anchors = true, etc)
    nt_keys = resistance |> keys |> collect .|> Symbol
    nt_values = resistance |> values |> collect .|> !AuxFunc.is_abstract_array

    return (; zip(nt_keys, nt_values)...)
end


get_resistance(opt) =
    isa(opt, Real) ? 0.95opt : opt["mean"] * (1.0 - opt["cv"] * (3.0 - 6.0opt["cv"]))
get_resistance(opt, id) = get_resistance(v[findfirst(x -> x["id"] === id, opt)]["MBS"])

get_platform_vars_to_eval(maxoffset::Float64, disp::Vector{Float64}, rots::Vector{Float64}) = (
    Offset = !iszero(maxoffset),
    Surge = !iszero(disp[1]),
    Sway = !iszero(disp[2]),
    Heave = !iszero(disp[3]),
    Roll = !iszero(rots[1]),
    Pitch = !iszero(rots[2]),
    Yaw = !iszero(rots[3]),
)

get_platform_vars_to_eval(maxoffset::Float64) = (
    Offset = !iszero(maxoffset),
    Surge = false,
    Sway = false,
    Heave = false,
    Roll = false,
    Pitch = false,
    Yaw = false,
)


function get_platform_vars_to_eval(rots::Vector{Float64})
    return (
        Offset = false,
        Surge = false,
        Sway = false,
        Heave = false,
        Roll = !iszero(rots[1]),
        Pitch = !iszero(rots[2]),
        Yaw = !iszero(rots[3]),
    )
end

function load_data(
    simulation_files,
    file_reading_opt::Dict{
        String,
        NamedTuple{(:folder_with_ls, :one_folder_per_lc, :join_str), Tuple{String, Bool, String}},
    },
    default_cols::Dict{String, Dict{String, Vector{Int}}},
    reading_settings::Dict,
)
    create_description_tables()

    LogOptions.add_message("Loading data", new_status = LogOptions.task_inprogress)

    set_loaded_data()

    file_extension = lowercase(reading_settings["type"])
    load_columns = file_extension == "mat" ? load_columns_from_mat : load_columns_from_csv

    # probably is better to use grouped df to verify all loaded cases: 
    # https://stackoverflow.com/questions/68273485/find-a-row-in-a-julia-dataframe
    for (ls, ls_data) in simulation_files
        isempty(ls_data) && continue

        LogOptions.add_message("$ls", log_type = :loading, level = 1)

        reading_opt = file_reading_opt[ls]
        join_char = reading_opt.one_folder_per_lc ? "/" : reading_opt.join_str

        all_cols = get_all_cols_to_read(default_cols, ls)

        #TODO: set tables with :lines/platforms
        create_data_table(
            [uppercasefirst(k) for (k, v) in default_cols if !isempty(v)],
            all_cols,
            ls,
        )

        for (lc, filenames) in ls_data
            LogOptions.add_message("$lc", log_type = :loading, level = 2)

            lines_to_analyze =
                (Sim_ID = Vector{Int}(), Line = Vector{Int}(), Element = Vector{String}())
            platforms_to_analyze =
                (Sim_ID = Vector{Int}(), Platform = Vector{Int}(), Quantity = Vector{String}())

            for sim in filenames
                cols_to_ignore = Vector{String}()

                n_rows_before = get_rows_to_analyze(lines_to_analyze, platforms_to_analyze)

                set_lines_to_load(ls, lc, sim, lines_to_analyze, cols_to_ignore)
                set_platforms_to_load(ls, lc, sim, platforms_to_analyze, cols_to_ignore)

                to_read = all_cols[(!in(cols_to_ignore)).(all_cols.Name), :]

                # If there are no columns to read, all data for current simulation is repeated
                isempty(to_read) && continue

                reading_settings["cols"] = get_all_cols(to_read)
                cols_lines = get_cols_of_component(to_read, "Line")
                cols_platforms = get_cols_of_component(to_read, "Platform")

                lc_id, sim_id = get_or_update_ids_of_lc_and_sim(ls, lc, sim)

                n_rows_after = get_rows_to_analyze(lines_to_analyze, platforms_to_analyze)
                append_sim_id_to_rows_to_analyze(
                    sim_id,
                    n_rows_after,
                    n_rows_before,
                    lines_to_analyze,
                    platforms_to_analyze,
                )

                filename = joinpath(
                    reading_opt.folder_with_ls,
                    "$ls$join_char$lc$join_char$sim.$file_extension",
                )
                LogOptions.add_message("\"$filename\"", log_type = :loading, level = 3)
                df = load_columns(filename, reading_settings)
                insertcols!(df, "LC_ID" => lc_id, "Sim_ID" => sim_id)

                df[!, vcat(cols_lines.Name, ["LC_ID", "Sim_ID"])] |>
                SQLite.load!(db, "$(ls)_Line_Tensions")
                df[!, vcat(cols_platforms.Name, ["LC_ID", "Sim_ID"])] |>
                SQLite.load!(db, "$(ls)_Platform_Motion")

                push_str_simulation_to_summary_table(ls, lc, lc_id, sim, sim_id)
            end # for simulations

            if !isempty(lines_to_analyze.Sim_ID)
                to_analyze[:lines][ls][lc] = DataFrame(lines_to_analyze)
            end
            if !isempty(platforms_to_analyze.Sim_ID)
                to_analyze[:platforms][ls][lc] = DataFrame(platforms_to_analyze)
            end

        end # for load cases

    end # for limit state

    add_values_to_description_tables()

    return nothing
end

function get_rows_to_analyze(lines::NamedTuple, platforms::NamedTuple)
    return (lines = length(lines.Line), platforms = length(platforms.Platform))
end

function append_sim_id_to_rows_to_analyze(
    sim,
    n_rows_after::NamedTuple,
    n_rows_before::NamedTuple,
    lines::NamedTuple,
    platforms::NamedTuple,
)
    n_times_lines = n_rows_after.lines - n_rows_before.lines
    n_times_platforms = n_rows_after.platforms - n_rows_before.platforms

    !iszero(n_times_lines) && append!(lines.Sim_ID, repeat([sim], n_times_lines))
    !iszero(n_times_platforms) && append!(platforms.Sim_ID, repeat([sim], n_times_platforms))

    return nothing
end

function set_lines_to_load(
    ls::String,
    lc::String,
    sim::String,
    to_analyze::NamedTuple,
    cols_to_ignore::Vector{String},
)
    lines_loaded = get_loaded_res_for_sim(ls, lc, sim, :lines)

    for line in ls_monitors[ls][:lines]
        for elem in line.elements
            elem_str = get_line_element_str(elem)
            if get_if_var_exist_for_component(lines_loaded, line.id, elem_str, :Element)
                LogOptions.add_message(
                    AuxFunc.get_text_repeated_var_to_load(sim, "line", line.id, elem_str),
                    new_status = LogOptions.task_warning,
                    log_type = :loading,
                    level = 4,
                )
                push!(cols_to_ignore, "Line$(line.id)_$elem_str")
            else
                push!(to_analyze.Line, line.id)
                push!(to_analyze.Element, elem_str)
                push_str_line_element_to_tables(ls, line.id, elem_str, elem.resistance)
            end
        end # for elem

        push_str_component_if_not_loaded(ls, "line", line.id)
    end # for lines

    return nothing
end

function get_cols_of_component(to_read::DataFrame, component::String)
    vcat(to_read[to_read.Name .== "Time", :], get_labels_of_component(to_read, component))
end

function set_platforms_to_load(
    ls::String,
    lc::String,
    sim::String,
    to_analyze::NamedTuple,
    cols_to_ignore::Vector{String},
)
    platf_loaded = get_loaded_res_for_sim(ls, lc, sim, :platforms)
    for platf in ls_monitors[ls][:platforms]
        for (i, (var, opt)) in enumerate(pairs(platf.vars2eval))
            opt || continue # skip not monitored variable

            var_str = string(var)
            isOffset = var === :Offset
            if get_if_var_exist_for_component(platf_loaded, platf.id, var_str, :Quantity)

                pred = "Platform$(platf.id)_" # commom predicate
                isOffset ? append!(cols_to_ignore, ["$(pred)Surge", "$(pred)Sway"]) :
                push!(cols_to_ignore, "$(pred)$var_str")
            else
                if isOffset
                    limit, unit = platf.max_offset, "m"
                else
                    if i > 4
                        limit = platf.max_rot[i - 4]
                        unit = platf.is_degree ? "deg" : "rad"
                    else
                        limit = platf.max_disp[i - 1]
                        unit = "m"
                    end
                end

                push!(to_analyze.Platform, platf.id)
                push!(to_analyze.Quantity, var_str)

                push_str_platform_var_to_tables(ls, platf.id, var_str, limit, unit)
            end
        end # for vars2eval
        push_str_component_if_not_loaded(ls, "platform", platf.id)
    end # for platforms

    return nothing
end

get_all_cols(to_read::DataFrame) = (push!(to_read, (1, "Time")) |> sort!)


function create_description_tables()
    AuxFunc.createtable!(
        db,
        "Simulations_Summary",
        Tables.Schema(
            ["Sim_ID", "Sim_Name", "LC_ID", "LC_Name", "LimitState"],
            [Union{Missing, Integer}, AbstractString, Integer, AbstractString, AbstractString],
        ),
        temp = false,
        ifnotexists = true,
    )

    AuxFunc.createtable!(
        db,
        "Components",
        Tables.Schema(["LimitState", "Object", "ID"], [AbstractString, AbstractString, Integer]),
        temp = false,
        ifnotexists = true,
    )
    AuxFunc.createtable!(
        db,
        "Line_Elements",
        Tables.Schema(
            ["Line_ID", "Element", "LimitState"],
            [Integer, AbstractString, AbstractString],
        ),
        temp = false,
        ifnotexists = true,
    )
    AuxFunc.createtable!(
        db,
        "Resistances",
        Tables.Schema(
            ["Object", "ID", "Element", "Quantity", "Value"],
            [AbstractString, Integer, AbstractString, AbstractString, Float64],
        ),
        temp = false,
        ifnotexists = true,
    )
    AuxFunc.createtable!(
        db,
        "Platforms",
        Tables.Schema(
            ["Platform_ID", "Quantity", "LimitState"],
            [Integer, AbstractString, AbstractString],
        ),
        temp = false,
        ifnotexists = true,
    )
    AuxFunc.createtable!(
        db,
        "Movement_Limitation",
        Tables.Schema(
            ["Object", "ID", "Quantity", "Value", "Unit"],
            [AbstractString, Integer, AbstractString, Float64, AbstractString],
        ),
        temp = false,
        ifnotexists = true,
    )

    # Final results -> desig tensions and maximum offsets/rotations 
    AuxFunc.createtable!(
        db,
        "Design_Tension_Summary",
        Tables.Schema(
            [
                "LC_ID",
                "LimitState",
                "Line_ID",
                "Element",
                "Mean_Tension",
                "Dyn_Tension",
                "Resistance",
                "Design_Tension",
                "Utilization_Factor",
                "Safety_Factor",
                "Status",
            ],
            vcat(
                [Integer, AbstractString, Integer, AbstractString],
                [Float64 for _ in 1:6],
                [AbstractString],
            ),
        ),
        temp = false,
        ifnotexists = true,
    )
    AuxFunc.createtable!(
        db,
        "Motion_Summary",
        Tables.Schema(
            ["LC_ID", "LimitState", "Object", "ID", "Quantity", "Max", "Min", "Allowed", "Status"],
            [
                Integer,
                AbstractString,
                AbstractString,
                Integer,
                AbstractString,
                Float64,
                Float64,
                Float64,
                AbstractString,
            ],
        ),
        temp = false,
        ifnotexists = true,
    )
end


function add_values_to_description_tables()
    for (tbl, data) in query_str_values
        if haskey(data, :insert) && !isempty(data[:insert])
            insert_values(tbl, AuxFunc.join_with_comma(unique!(data[:insert])))
        end
        if haskey(data, :insert_or_replace) && !isempty(data[:insert_or_replace])
            query_str = AuxFunc.join_with_comma(unique!(data[:insert_or_replace]))
            insert_values(tbl, query_str, or_replace = true)
            # Unique to remove 
            unique!(loaded[:summary])
        end
    end

    return nothing
end


function add_summary_to_tables(ls::String)
    add_summary_of_line_results_to_tables(ls)
    add_summary_of_motion_results_to_tables(ls)

    return nothing
end

function add_summary_of_line_results_to_tables(ls::String)
    tbl = "Design_Tension_Summary"
    strings = query_str_values[tbl]

    !isempty(strings[:insert]) && insert_values(tbl, AuxFunc.join_with_comma(strings[:insert]))
    !isempty(strings[:update]) &&
        update_summary_of_line_results(ls, AuxFunc.join_with_comma(strings[:update]))

    return nothing
end


function add_summary_of_motion_results_to_tables(ls::String)
    tbl = "Motion_Summary"
    strings = query_str_values[tbl]

    !isempty(strings[:insert]) && insert_values(tbl, AuxFunc.join_with_comma(strings[:insert]))
    # TODO: UPDATE
    #==!isempty(strings[:update]) && update_summary_of_motion_results(
        ls, AuxFunc.join_with_comma(strings[:update]));
    ==#
    return nothing
end


function update_summary_of_motion_results(ls::String, values::String)

end


function update_summary_of_line_results(ls::String, values::String)
    set_where_pattern::String = "Td.Line_ID = Tmp.Line_ID AND Td.Element = Tmp.Element AND Td.LC_ID = Tmp.LC_ID"
    set_cols::Vector{String} = [
        "Mean_Tension",
        "Dyn_Tension",
        "Resistance",
        "Design_Tension",
        "Utilization_Factor",
        "Safety_Factor",
        "Status",
    ]

    where_pattern = """
        Td.LimitState = "$ls" AND 
        (Td.LC_ID, Td.Line_ID, Td.Element) IN (SELECT LC_ID, Line_ID, Element FROM Tmp)
    """

    update_values(
        "Design_Tension_Summary AS Td",
        join(map(col -> "$col=(SELECT $col FROM Tmp WHERE $set_where_pattern)", set_cols), ','),
        where_pattern;
        with_clause = """
            Tmp( LC_ID, Line_ID, Element, $(AuxFunc.join_with_comma(set_cols))) 
            AS ( VALUES $(values) )
        """,
    )

    return nothing
end

get_table_names() = (SQLite.tables(db) |> DataFrame).name

function push_str_simulation_to_summary_table(ls, lc, lc_id, sim, sim_id)
    push!(
        query_str_values["Simulations_Summary"][:insert_or_replace],
        "($sim_id, '$sim', $lc_id, '$lc', '$ls')",
    )

    push!(loaded[:summary], (sim_id, sim, lc_id, lc, ls))
    return nothing
end

function push_str_line_element_to_tables(ls::String, id::Int, elem::String, resistance::Float64)
    df = loaded[:components][:lines]
    if isempty(df[df.LimitState .== ls .&& df.Line_ID .== id .&& df.Element .== elem, :])
        push!(query_str_values["Line_Elements"][:insert], "($id, '$elem', '$ls')")
        push!(
            query_str_values["Resistances"][:insert],
            "('Line', $id, '$elem', 'Strength', $resistance)",
        )
        push!(df, (id, elem, ls))
    end
    return nothing
end

function push_str_platform_var_to_tables(
    ls::String,
    id::Int,
    var::String,
    limit::Float64,
    unit::String,
)
    df = loaded[:components][:platforms]
    if isempty(df[df.LimitState .== ls .&& df.Platform_ID .== id .&& df.Quantity .== var, :])
        push!(query_str_values["Platforms"][:insert], "($id, '$var', '$ls')")
        push!(
            query_str_values["Movement_Limitation"][:insert],
            "('Platform', $id, '$var', $limit, '$unit')",
        )
    end

    return nothing
end

function push_str_component_if_not_loaded(ls::String, component::String, id::Int)
    df = loaded[:components][:all]

    if isempty(df[==(ls).(df.LimitState) .& ==(component).(df.Object) .& ==(id).(df.ID), :])
        push!(query_str_values["Components"][:insert], "('$ls', '$component', $id)")
        push!(df, (ls, component, id))
    end

    return nothing
end


function get_line_element_str(elem::LineElement)::AbstractString
    return isa(elem, Fairlead) ? "A" :
           isa(elem, Anchor) ? "B" :
           isa(elem, Transition) ? "T$(elem.prev_seg)" : "$(elem.element_id)"
end


function create_data_table(tables::Vector{String}, all_cols::DataFrame, ls::String)
    for tbl in tables
        tbl_name = tbl === "Lines" ? "$(ls)_Line_Tensions" : "$(ls)_Platform_Motion"
        df_labels = get_labels_of_component(all_cols, tbl[1:(end - 1)]) # -1 exclude 's' from "Lines"
        AuxFunc.createtable!(
            db,
            tbl_name,
            Tables.Schema(
                vcat("Time", df_labels.Name, ["LC_ID", "Sim_ID"]),
                vcat(
                    Float64,
                    repeat([Union{Missing, Float64}], size(df_labels, 1)),
                    [Integer, Integer],
                ),
            ),
            temp = false,
            ifnotexists = true,
        )
    end

    return nothing
end

"""
    Get the column IDs, names and number of columns 
"""
get_labels_of_component(df::DataFrame, component::String) =
    subset(df, :Name => x -> occursin.(component, x))


function get_all_cols_to_read(default_cols::Dict, ls::String)::DataFrame

    # Construct ordered dict with (names_ => ids_) to map sorted column names  
    ids_, names_ = Vector{Int}(), Vector{String}()
    lines = get(ls_monitors[ls], :lines, nothing)
    short_to_long_str = Dict("A" => "fairleads")
    if !isnothing(lines)
        for (i, line) in enumerate(lines)
            for elem in line.elements
                elem_str = get_line_element_str(elem)
                push!(ids_, default_cols["lines"][short_to_long_str[elem_str]][i])
                push!(names_, "Line$(line.id)_$elem_str")
            end
        end
    end
    platforms = get(ls_monitors[ls], :platforms, nothing)
    if !isnothing(platforms)
        for platf in platforms
            for (var_, bool_) in pairs(platf.vars2eval)
                # .!bool_ && continue
                if !bool_ || (var_ == :Surge || var_ == :Sway) && platf.vars2eval.Offset
                    continue
                end
                append!(
                    names_,
                    var_ == :Offset ? ["Platform$(platf.id)_Surge", "Platform$(platf.id)_Sway"] :
                    ["Platform$(platf.id)_$(string(var_))"],
                )
            end
            append!(ids_, default_cols["platforms"]["dofs"])
        end
    end

    return sort!(DataFrame(:Num => ids_, :Name => names_))
end


function load_columns_from_mat(filename::String, settings::Dict)

    nested_keys = settings["nested keys"]
    cols = settings["cols"]
    df =
        settings["n nested keys"] === 0 ? DataFrame(matread(filename)[:, cols.Num], cols.Name) :
        settings["n nested keys"] === 1 ?
        DataFrame(matread(filename)[nested_keys[1]][:, cols.Num], cols.Name) :
        DataFrame(matread(filename)[nested_keys[1]][nested_keys[2]][:, cols.Num], cols.Name)

    solver = settings["solver"]
    return isnothing(solver) ? df :
           solver == "OpenFAST" ? calc_effective_tension_OpenFAST(df) :
           throw(
        DomainError(
            solver,
            "You must set 'solver' to 'OpenFAST' or leave it as 'nothing' to use datas as readed.",
        ),
    )

end

function load_columns_from_csv(filename::String, settings::Dict)
    col_names =
        sort!(OrderedDict{Int, String}(zip(settings["cols"].Num, settings["cols"].Name))) |>
        values |>
        collect

    return rename!(
        CSV.read(
            "$filename",
            DataFrame,
            # header = settings["cols"].Name,
            select = settings["cols"].Num,
            delim = ';',
            skipto = settings["first data row"],
            ntasks = settings["threads"],
        ),
        col_names,
    )
end


function calc_effective_tension_OpenFAST(df)
    ref_cols = 1:3:size(df, 2)
    tensions = DataFrame(zeros(size(df, 1), length(ref_cols)), :auto)

    for (col, ref_cols) in enumerate(ref_cols)
        ref_cols_end = ref_cols + 2
        tensions[!, col] =
            select(df, ref_cols:ref_cols_end => ByRow((x, y, z) -> √(x^2 + y^2 + z^2)))
    end

    return tensions
end


function get_or_update_ids_of_lc_and_sim(ls::String, lc::String, sim::String)
    df = loaded[:summary][loaded[:summary].LimitState .== ls, 1:4]
    df_ids = df[df.LC_Name .== lc .&& df.Sim_Name .== sim, [:LC_ID, :Sim_ID]]

    # Both IDs (load case and simulation) exists ...
    if !isempty(df_ids)
        return df_ids[1, 1], df_ids[1, 2]
        # ... or at least te simulation is new.
    else
        # If LC exist only the simulation ID must be updated ...
        df_lc = df[df.LC_Name .== lc, [:LC_ID, :Sim_ID]]
        if !isempty(df_lc)
            return df_lc[1, 1], length(unique(df_lc.Sim_ID)) + 1
            # ... otherwise, it is a new LC.
        else
            sim_ids = df[df.Sim_Name .== sim, :Sim_ID]
            sim_id =
                isempty(sim_ids) ? length(unique(df.Sim_ID)) + 1 : # new simulation
                sim_ids[1] # existing simulation
            return length(unique(df.LC_ID)) + 1, sim_id
        end
    end
end

get_limit_states() = unique(loaded[:summary].LimitState)

function get_all_sim_and_lc(ls::AbstractString; get_ids::Bool = true)
    df = loaded[:summary]
    cols = get_ids ? [:Sim_ID, :LC_ID] : [:Sim_Name, :LC_Name]
    return unique(df[df.LimitState .== ls, cols])
end

function get_load_cases_from_limit_state(ls::String; col::Symbol = :LC_Name)
    df = loaded[:summary]
    return unique(df[df.LimitState .== ls, col])
end

function get_simulations_from_load_case(lc::Int, ls::String; get_id::Bool = true)
    df = loaded[:summary]
    return unique(df[df.LimitState .== ls .&& df.LC_ID .== lc, get_id ? :Sim_ID : :Sim_Name])
end

function get_simulations_from_load_case(lc::String, ls::String; get_id::Bool = true)
    df = loaded[:summary]
    return unique(df[df.LimitState .== ls .&& df.LC_Name .== lc, get_id ? :Sim_ID : :Sim_Name])
end



function get_cols_names(tbl::AbstractString, cols_to_ignore::Vector{String} = [])::Vector{String}
    cols = SQLite.columns(db, tbl).name
    deleteat!(cols, findall(in(cols_to_ignore), cols))
    return cols
end


function get_component_ids(ls::AbstractString, component::String)
    df = loaded[:components]
    return unique(df[df.LimitState .== ls .&& df.Object .== "$component", :ID])
end

has_platforms_loaded() =
    haskey(loaded[:components], :platforms) && !isempty(loaded[:components][:platforms])


function get_line_element_strs_ids(line::Int, ls::AbstractString)::Vector{String}
    return (DBInterface.execute(
        db,
        """
        SELECT  DISTINCT Element 
        FROM    Line_Elements 
        WHERE   Line_ID = $(line) AND LimitState = "$ls";
        """,
    ) |> DataFrame)[
        !,
        1,
    ]
end

function collect_elements_monitored(ls::String, lc::String, sim::String) end

function get_line_tension(ls::String, lc::Int, sim::Int, line_id::Int)

    if element === "fairlead"
        return DBInterface.execute(
            db,
            """
            SELECT  Line$(line_id)_A
            FROM    $(ls)_Line_Tensions
            WHERE   LC_ID = $lc AND Sim_ID = $sim AND Time > $(ramp[ls]);
            """,
        ) |> DataFrame
    else
        # TODO:
    end

end


function get_line_tension(line_id::Int, sim::Int, lc::Int, ls::String)

    for element in get_line_element_strs_ids(line_id, ls)
        if element === "A"
            return DBInterface.execute(
                db,
                """
                SELECT Line$(line_id)_A
                FROM    $(ls)_Line_Tensions 
                WHERE   LC_ID = $lc AND Sim_ID = $sim AND Time > $(ramp[ls]);
                """,
            ) |> DataFrame
        else
            #TODO
        end
    end
end

function get_tension_of_line_element(ls::String, lc::Int, sim::Int, line_id::Int, elem = "A")

    return (DBInterface.execute(
        db,
        """
        SELECT Line$(line_id)_$elem
        FROM    $(ls)_Line_Tensions 
        WHERE   LC_ID = $lc AND Sim_ID = $sim AND Time > $(ramp[ls]);
        """,
    ) |> DataFrame)[
        !,
        1,
    ]
end

get_lc_name_from_id(lc::Int) = (DBInterface.execute(
    db,
    """
    SELECT LC_Name 
    FROM Simulations_Summary
    WHERE LC_ID = "$lc"
    LIMIT 1
    """,
) |> DataFrame)[1, 1]

function get_lc_id_from_name(ls::String, lc::String; from_db::Bool = false)
    if from_db
        return DataFrame(DBInterface.execute(
            db,
            """
            SELECT LC_ID FROM Simulations_Summary 
            WHERE LC_Name = "$lc" AND LimitState = "$ls"
            LIMIT 1
            """,
        ))[
            1,
            1,
        ]
    else
        ids = loaded[:summary][
            loaded[:summary].LC_Name .== lc .&& loaded[:summary].LimitState .== ls,
            :LC_ID,
        ]
        return isempty(ids) ? -1 : ids[1]
    end
end

get_sim_id_from_name(lc::Union{String, Int}, sim::String) = (DBInterface.execute(
    db,
    """
    SELECT DISTINCT Sim_ID 
    FROM Simulations_Summary
    WHERE Sim_Name = '$sim' AND LC_$(isa(lc, String) ? "Name = '$lc'" : "ID = $lc") 
    LIMIT 1
    """,
) |> DataFrame)[
    1,
    1,
]


function get_all_sim(ls::String, lc::Int; get_id::Bool = false)
    df = loaded[:summary]
    return unique!(df[df.LC_ID .== lc .&& df.LimitState .== ls, get_id ? :Sim_ID : :Sim_Name])
end


function get_simulation_results(cols::String, tbl::String, ls::String, lc::String, sim::Int)
    return DBInterface.execute(
        db,
        """
        SELECT  $cols 
        FROM    $tbl 
        WHERE   LC_ID = (
            SELECT LC_ID 
            FROM Simulations_Summary
            WHERE LC_Name = '$lc'
            LIMIT 1
        )       AND Time > 0;"
        """,
    ) |> DataFrame
end


function get_simulation_results(cols::String, tbl::String, ls::String, lc::Int, sim::Int)

    return DBInterface.execute(
        db,
        """
        SELECT  $cols 
        FROM    $tbl 
        WHERE   LC_ID = $lc AND Sim_ID = $sim $(ramp[ls] > 0 ? "AND Time > $(ramp[ls]);" : ";")
        """,
    ) |> DataFrame
end

function get_platform_data_to_eval(ls::AbstractString, lc::Int, sim::Int, id::Int)
    tbl = "$(ls)_Platform_Motion"
    to_eval = ls_monitors[ls][:platforms][id].vars2eval
    pre = "Platform$(id)_"
    cols = "
        $(join([ 
            var == :Offset ? "$(pre)Surge,$(pre)Sway" : "$(pre)$(string(var))"
            for (var, opt) in pairs(to_eval) if opt
        ], ","))
    "

    return DBInterface.execute(
        db,
        """
        SELECT  $cols
        FROM    $tbl 
        WHERE   LC_ID = $lc AND Sim_ID = $sim AND Time > $(ramp[ls]);
        """,
    ) |> DataFrame
end

function get_platform_results(ls::AbstractString, lc::Int, sim::Int, vars::Vector{String})

    return DBInterface.execute(
        db,
        """ 
            SELECT $(join(vars, ", "))
            FROM $(ls)_Platform_Motion 
            WHERE LC_ID = $(lc) AND Sim_ID = $(sim) AND Time > $(Database.ramp[ls]);
        """,
    ) |> DataFrame
end


function set_order_by_clause(cols::Vector{String}; opts::Union{String, Vector{String}} = "ASC")
    return "$(join(cols .* " " .* opts, ", "))"
end


function set_join_clause(
    join_type::Union{Missing, String} = missing,
    join_::String = "",
    join_on::String = "",
)

    return ismissing(join_type) ? missing : "$(uppercase(join_type)) JOIN $join_ ON $join_on"
end



function get_columns_from_table(
    tbl::String,
    cols::Union{Vector{String}, String, Missing} = missing,
    hint::Union{Missing, String} = missing;
    join_clause::Union{Missing, String} = missing,
    orderby_clause::Union{Missing, String} = missing,
    is_distinct::Bool = false,
    limit::Union{Missing, Int} = missing,
)::DataFrame
    query = """
    SELECT $(is_distinct ? "DISTINCT" : "") 
        $(ismissing(cols) || isempty(cols) ? " * " : isa(cols, String) ? cols : join(cols, ", "))
    FROM 
        $tbl 
    $(ismissing(join_clause) ? "" : join_clause)
    $(ismissing(hint) ? "" : "WHERE $hint")
    $(ismissing(orderby_clause) ? "" : "ORDER BY $orderby_clause")
    $(ismissing(limit) ? "" : "LIMIT $limit")
    """

    return DataFrame(DBInterface.execute(db, query))
end

function get_mat_nested_keys(
    nested_keys::Vector{String},
    simulation::AbstractString,
    load_case::AbstractString,
)
    isempty(nested_keys) && return String[]

    # Get first level
    key1 = (
        nested_keys[1] === "use full description" ? load_case * "_" * simulation :
        nested_keys[1] === "use load case" ? load_case :
        nested_keys[1] === "use simulation" ? simulation : nested_keys[1]
    )

    # Get second level
    if length(nested_keys) === 2
        key2 = (
            nested_keys[2] === "use full description" ? load_case * "_" * simulation :
            nested_keys[2] === "use load case" ? load_case :
            nested_keys[2] === "use simulation" ? simulation : nested_keys[2]
        )
        return [key1, key2]
    else
        return [key1]
    end

end

function get_loaded_res_for_sim(ls::String, lc::String, sim::String, type::Symbol)
    df = loaded[type][ls]
    return df[==(lc).(df.LC) .& ==(sim).(df.Sim), 3:end]
end

function get_if_var_exist_for_component(df::DataFrame, id::Int, var::String, col::Symbol)
    return !isempty(df[==(id).(df.ID) .& ==(var).(df[!, col]), :ID])
end

type_to_col_name_(type::Symbol) = type |> string |> uppercasefirst |> Symbol

function get_summary_of_line_tension(ls::String)
    return DBInterface.execute(
        db,
        """
        SELECT  LC_ID AS LC, Line_ID AS Line, Element  
        FROM    Design_Tension_Summary
        WHERE   LimitState = "$ls";
        """,
    ) |> DataFrame
end

function get_summary_of_motion(ls::String; type = :platform)
    if type == :platform
        return DBInterface.execute(
            db,
            """
            SELECT  LC_ID AS LC, ID, Quantity  
            FROM    Motion_Summary
            WHERE   LimitState = "$ls" AND 
                    Object = "platform";
            """,
        ) |> DataFrame
    else
        LogOptions.add_message(
            "Invalid type to retrieve motion summary",
            new_status = LogOptions.task_warning,
        )
        return DataFrame(:LC => [], :ID => [], :Quantity => [])
    end
end

function get_line_statistics(
    ls::String;
    lc::Union{Nothing, String} = nothing,
    cols::Union{Nothing, String} = nothing,
)
    return DBInterface.execute(
        db,
        """
        SELECT $(isnothing(cols) ? "*" : cols) 
        FROM $(ls)_Line_Statistics 
        $(isnothing(lc) ? "" : "WHERE LC_ID = $lc");
        """,
    ) |> DataFrame
end

function get_lines_for_lc(ls::String, lc::Union{String, Int})
    return get_columns_from_table(
        "$(ls)_Line_Statistics",
        ["Line_ID"],
        """
        LC_$(isa(lc, String) ? """ Name = "$lc" """ : "ID = $lc")
        """;
        is_distinct = true,
    )[
        !,
        1,
    ]
end

function get_lines_for_simulation(ls::String, lc::Union{String, Int}, sim::Union{String, Int})
    return get_columns_from_table(
        "$(ls)_Line_Statistics",
        ["Line_ID"],
        """
        LC_$(isa(lc, String) ? "Name = '$lc'" : "ID = $lc") AND 
        Sim_$(isa(sim, String) ? "Name = '$sim'" : "ID = $sim")
        """;
        is_distinct = true,
    )[
        !,
        1,
    ]
end

function get_loaded_lines_elements(ls::String, lc::String, sim::String)
    df_ = loaded[:lines][ls]
    return df_[df_.LC .== lc .&& df_.Sim .== sim, [:ID, :Element]]
end


function get_loaded_platforms(ls::String, lc::String, sim::String)
    if has_platforms_loaded()
        df = loaded[:platforms][ls]
        return df[df.LC .== lc .&& df.Sim .== sim, [:ID, :Quantity]]
    else
        return DataFrame("ID" => Int[], "Quantity" => String[])
    end
end


function get_motion_statistics(
    ls::String;
    type = "platform",
    lc::Union{Nothing, String} = nothing,
    cols::Union{Nothing, String} = nothing,
)
    return DBInterface.execute(
        db,
        """
        SELECT $(isnothing(cols) ? "*" : cols) 
        FROM $(ls)_Motion_Statistics 
        WHERE 
            Component = "$type" 
            $(isnothing(lc) ? "" : " LC_ID = $lc");
        """,
    ) |> DataFrame
end


function insert_values(
    table::String,
    values::String;
    cols::Union{Nothing, Vector{String}} = nothing,
    or_replace::Bool = false,
)
    SQLite.execute(
        db,
        """
        INSERT $(or_replace ?  "OR REPLACE" : "" ) INTO $table 
            $(isnothing(cols) ? "" : "($(AuxFunc.join_with_comma(cols)))") 
        VALUES $values;
        """,
    )
    return nothing
end

function update_values(
    tbl::String,
    set_pattern::String,
    where_pattern::String;
    with_clause::String = "",
)
    SQLite.execute(
        db,
        """
        $(isempty(with_clause) ? "" : "WITH $with_clause")        
        UPDATE $tbl SET $set_pattern WHERE $where_pattern;
        """,
    )
end


end  # closes Database module

