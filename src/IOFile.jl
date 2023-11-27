
module IOFile

using LazyJSON
using SQLite
using MAT
using CSV
using XLSX
using DataFrames

using ..GeneralOptions
using ..Database
using ..AuxScripts
using ..AuxFunc
using ..LogOptions


const dir = Dict{String, String}("input data" => "./input/simulations", "output" => "./output")

input_file = ""
summary_file = ""

function set_input_file(file_name::String; dir::Union{String, Nothing} = nothing)
    global input_file
    input_file = isnothing(dir) ? file_name : joinpath(dir, file_name)
    if !endswith(input_file, ".json")
        input_file *= ".json"
    end

    return nothing
end


function read_input_file()
    LogOptions.add_message(
        "Reading input file \"$(input_file)\"",
        new_status = LogOptions.task_inprogress,
    )

    # Read JSON file ...
    input_json = LazyJSON.value(read(input_file, String))  #, getproperty=true);
    LogOptions.add_message("Input file was read", new_status = LogOptions.task_done)

    # ... check some basic input syntax
    basic_input_check(input_json) || error("")

    # ... and set model options
    set_model(input_json)

    return nothing
end


function set_directories(;
    input_dir::Union{String, Nothing} = nothing,
    output_dir::Union{String, Nothing} = nothing,
    ui::Bool = false,
)
    # "./input/simulations"
    if !isnothing(input_dir)
        dir["input data"] = input_dir
    end
    if !isnothing(output_dir)
        dir["output"] = output_dir
    end

    return nothing
end


function basic_input_check(inp::AbstractDict)::Bool
    # TODO


    # Check 

    return true
end


function set_model(inp::AbstractDict)

    Database.set_ramp(convert(Dict{String, Float64}, inp["Ramp"]))

    # Define actions to perform
    GeneralOptions.set_actions(convert(Dict{String, Dict{String, Bool}}, inp["Actions"]))

    GeneralOptions.set_code(convert(Dict, get(inp, "Code", Dict())))

    # Define reading options (only if this is required)
    db_actions = GeneralOptions.actions["database"]

    Database.set_database(inp["Database"]["name"], db_actions["reset"])

    if db_actions["reset"] || db_actions["load"]
        set_input_options(
            convert(Dict{String, Any}, inp["Database"]),
            convert(Dict{String, Dict{String, Dict}}, inp["Monitors"]),
            convert(Dict{String, Any}, inp["Resistance"]),
            GeneralOptions.get_mov_limit(get(inp, "Movement Limitation", nothing)),
        )
    end

    action_scripts = convert(Dict{String, Bool}, GeneralOptions.actions["run scripts"])
    any(values(action_scripts)) &&
        AuxScripts.set_scripts(convert(Vector{Dict{String, String}}, inp["Scripts"]))

    return nothing
end


function set_input_options(db_opt::Dict, monitors::Dict, resistance::Dict, mov_lim = nothing)

    # Creates relationship between real structure and database IDs
    # For example, if fairleads [2,5,8] are monitored, the database IDs will be [1,2,3]

    # Define monitor IDs (e.g.: ID numbers of fairleads and plataforms to be monitored during evaluation)
    Database.set_obj_parameters(monitors, resistance, mov_lim) ||
        error("Failed while trying to set monitor parameters!\n")


    # Set default columns (to read data from different limit states) 
    haskey(db_opt, "default columns") &&
        GeneralOptions.set_default_columns(db_opt["default columns"])

    # Set all file (full)names to read for each limit state
    set_simulation_file_reading(db_opt)


    return true
end  # function 'set_input_options'


function set_simulation_file_reading(opt::Dict)
    # Define reading function
    type = convert(String, opt["type"])


    if type === "CSV"
        GeneralOptions.set_simulation_file_names(
            dir["input data"],
            convert(Dict{String, Dict{String, Any}}, opt["limit states"]),
        )
        GeneralOptions.set_csv_reading_options(convert(Dict, opt["input options"]))
    elseif type === "MAT"
        GeneralOptions.set_simulation_file_names(
            dir["input data"],
            convert(Dict{String, Dict{String, Any}}, opt["limit states"]),
            ".mat",
        )
        GeneralOptions.set_mat_reading_options(convert(Dict, opt["input options"]))
    end


    return nothing
end  # function 'set_simulation_file_reading'

function savetable(
    data::Union{DataFrame, Dict{String, DataFrame}},
    filename::String;
    format::String = "csv",
    delim = ',',
    sheet::String = "",
)
    fname = "$(filename).$format"

    if format == "csv"
        CSV.write(fname, data, writeheader = true, delim = delim)
    elseif format == "mat"
        if data isa Dict
            matwrite("matfile.mat", data; compress = true)
        else
            col_names = data |> names
            data = vcat(reshape(col_names, 1, length(col_names)), Matrix(data))

            matfile = matopen(fname, "w")
            write(matfile, "timeseries", data)
            close(matfile)
        end
    elseif format == "xlsx"
        XLSX.openxlsx(fname, mode = isfile(fname) ? "rw" : "w") do xf

            if isa(data, Dict)
                for (sheet_name, sheet_data) in data
                    write_table_to_xlsx(sheet_data, sheet_name, xf)
                end
            else # DataFrame
                write_table_to_xlsx(data, sheet, xf)
            end
        end
    end

    LogOptions.add_message("Table(s) exported to \"$fname\"", new_status = LogOptions.task_done)

    return nothing
end


function write_table_to_xlsx(df::DataFrame, sheet::String, xf::XLSX.XLSXFile)
    # if sheet in XLSX.sheetnames(xf)
    new_sheet = "sheet_$(length(xf.workbook.sheets) + 1)"
    # LogOptions.add_message("Sheet \"$sheet\" already exist in \"$(xf.filepath)\"", 
    #     new_status=LogOptions.task_warning)
    # else
    #     new_sheet = sheet
    # end
    XLSX.writetable!(XLSX.addsheet!(xf, new_sheet), df)
end

end  # IOFile module
