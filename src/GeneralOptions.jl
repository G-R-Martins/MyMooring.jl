module GeneralOptions

using Dates

using ..AuxFunc
using ..Analysis
using ..AuxScripts
using ..Database
using ..Dashboard
using ..LogOptions


const default_opt =
    (individual_folder = (load_cases = true, limit_states = true), abs_position = true)

const valid_opt =
    (codes = Set(["DNV"]), limit_states = Set(["ULS"]), database = Set(["CSV", "MAT"]))

const actions = Dict(
    "database" => Dict("load" => false, "reset" => false),
    "verifications" => Dict("ULS" => true, "ALS" => false, "FLS" => false),
    "export" => Dict("figures" => false, "summary" => false),
    "dashboard" => Dict("show current time" => true, "link density" => true),
    "run scripts" => Dict(
        "beginning" => false,
        "before analysis" => false,
        "after analysis" => false,
        "end" => false,
    ),
)

const default_cols = Dict{String, Dict{String, Vector{Int}}}()

const file_reading_settings = Dict()

const simulation_names =
    Dict("ULS" => Dict{String, Vector{String}}(), "ALS" => Dict{String, Vector{String}}())

const file_reading_opt =
    Dict{String, @NamedTuple{folder_with_ls::String, one_folder_per_lc::Bool, join_str::String}}()





set_actions(options::Dict{String, Dict{String, Bool}}) = (merge!(actions, options); nothing)


function set_code(inp::Dict)
    haskey(inp, "option") && (code = convert(String, inp["option"]))

    # consequence class
    if haskey(inp, "consequence class")
        Analysis.set_load_factors(convert(Int, inp["consequence class"]))
    else
        Analysis.set_load_factors()
    end

    return nothing
end


function get_mov_limit(inp)
    isnothing(inp) && return nothing

    # mov_lim_data["platforms"][1]["maxOffset"]
    mov_lim_data = Dict{String, Dict{Int, Dict{String, Any}}}()

    # `component` == platforms || turbines
    for (component, data) in convert(Dict{String, Dict{String, Any}}, inp)
        isplatform, isturbine = false, false

        if component === "platforms"
            isplatform = true
        elseif component === "turbines"
            isturbine = true
        end

        # Same definitions for all platforms
        if isa(data, AbstractDict)
            # Default data
            ref = convert(Vector{Float64}, data["reference"])
            isdeg = get(data, "is degree", true)

            if isplatform
                offset = convert(Float64, data["max offset"])
                rot = convert(Vector{Float64}, data["max rotations"])
                disp_ = convert(Vector{Float64}, data["max translations"])

                mov_lim_data["platforms"] = Dict()
                for id in convert(Vector{Int}, data["ids"])
                    mov_lim_data["platforms"][id] = Dict(
                        "reference" => ref,
                        "max offset" => offset,
                        "max translations" => disp_,
                        "max rotations" => rot,
                        "is degree" => isdeg,
                    )
                end
            elseif isturbine
                # TODO
            end

        end

    end

    return isempty(mov_lim_data) ? nothing : mov_lim_data
end


function set_default_columns(opt)
    # TODO: check repeated IDs 

    # Example: default_cols["lines"]["fairleads"]
    for (structure, struct_data) in opt
        default_cols[structure] = Dict{String, Vector{Int}}()
        for (component, data) in struct_data
            default_cols[structure][component] = AuxFunc.get_vector_or_range(data)
        end
    end

    return nothing
end


function set_csv_reading_options(opt::Dict)
    file_reading_settings["type"] = "csv"
    file_reading_settings["first data row"] = convert(Int, get(opt, "first data row", 1))
    file_reading_settings["delimiter"] = convert(Char, get(opt, ["delimiter"][1], ','))
    file_reading_settings["threads"] = convert(Int, get(opt, "threads", 8))
    file_reading_settings["solver"] =
        haskey(opt, "solver") ? convert(String, opt["solver"]) : nothing

    return nothing
end


function set_mat_reading_options(opt::Dict)
    file_reading_settings["type"] = "mat"
    file_reading_settings["nested keys"] =
        convert(Vector{String}, get(opt, "nested keys", String[]))
    file_reading_settings["solver"] =
        haskey(opt, "solver") ? convert(String, opt["solver"]) : nothing

    file_reading_settings["n nested keys"] = length(file_reading_settings["nested keys"])
    file_reading_settings["n nested keys"] > 2 &&
        error("You can have up to 2 nested levels in a MAT file.")

    return nothing
end

function set_simulation_file_names(root_folder::String, ls_opt::Dict, format = ".csv")

    #  Example: simulation_files_fullname["ULS"]["LC 1.A"][n]
    for (ls, ls_definition) in ls_opt
        folder_def = convert(Dict{String, Bool}, ls_definition["use specific folder"])
        folder_with_ls =
            get(folder_def, "limit state", false) ? joinpath(root_folder, "$ls") : root_folder

        one_folder_per_lc = get(folder_def, "load cases", false)
        loadcases =
            isa(ls_definition["load cases"], AbstractVector) ?
            convert(Vector{String}, ls_definition["load cases"]) :
            AuxFunc.combine_prefix_suffix(
                ls_definition["load cases"]["prefix"],
                ls_definition["load cases"]["suffix"],
            )

        sim_names = AuxFunc.combine_prefix_suffix(
            ls_definition["simulations"]["prefix"],
            ls_definition["simulations"]["suffix"],
        )

        join_str = get(ls_definition, "join string", "")

        file_reading_opt[ls] = (
            folder_with_ls = get(folder_def, "limit state", false) ?
                             joinpath(root_folder, "$ls") : root_folder,
            one_folder_per_lc = get(folder_def, "load cases", false),
            join_str = join_str,
        )

        for lc in loadcases
            simulation_names[ls][lc] = sim_names
        end
    end

    return nothing
end


function execute_actions()
    actions["run scripts"]["beginning"] && AuxScripts.execute_script(AuxScripts.Beginning)

    t0 = now()
    if actions["database"]["load"] || actions["database"]["reset"]
        LogOptions.add_message(
            "Started loading database at: $t0",
            new_status = LogOptions.task_inprogress,
        )
        Database.load_data(simulation_names, file_reading_opt, default_cols, file_reading_settings)
        LogOptions.add_message(
            ######### DESCOMENTAR
            # "Elapsed time to load/create database: $(canonicalize(t0-now()))",
            new_status = LogOptions.task_done,
        )
    else
        Database.set_loaded_data(empty_db = true)
    end


    ls_to_verify = get_ls_to_verify()

    actions["run scripts"]["before analysis"] &&
        AuxScripts.execute_script(AuxScripts.BeforeAnalysis)

    isempty(ls_to_verify) ||
        Analysis.do_verifications(Database.db, ls_to_verify, Database.to_analyze)

    actions["run scripts"]["after analysis"] && AuxScripts.execute_script(AuxScripts.AfterAnalysis)

    Dashboard.set_dashboards(
        show_current_time = actions["dashboard"]["show current time"],
        linkdensity = true,
    )

    actions["run scripts"]["end"] && AuxScripts.execute_script(AuxScripts.End)

    return nothing
end

function get_ls_to_verify()
    return [
        ls for (ls, to_verify) in actions["verifications"] if to_verify &&
        (!isempty(Database.to_analyze[:lines][ls]) || !isempty(Database.to_analyze[:platforms][ls]))
    ]
end

end  # module GeneralOptions




