
module MyMooring
const global ui_is_opened = Ref{Bool}(false)

include("AuxFunctions.jl")
include("LogOptions.jl")
include("Database.jl")
include("Analysis.jl")
include("CurrentSelection.jl")
include("Dashboard.jl")
include("AuxScripts.jl")
include("GeneralOptions.jl")
include("IOFile.jl")
include("MyMooringUI.jl")

using Dates
using .LogOptions
export run_program


function run_program(;
    input_file_dir::Union{String, Nothing} = nothing,
    input_file::Union{String, Nothing} = nothing,
    input_dir::Union{String, Nothing} = nothing,
    output_dir::Union{String, Nothing} = nothing,
)
    t0 = now()


    LogOptions.add_message("Started at: $(Dates.format(t0, "yyyy-mm-dd HH:MM:SS"))", new_status = LogOptions.task_info)

    IOFile.set_directories(input_dir = input_dir, output_dir = output_dir)

    ## Read *.json and set general parameters
    if !isnothing(input_file)
        IOFile.set_input_file(input_file, dir = input_file_dir)
    end
    IOFile.read_input_file()

    ## Do requested options
    GeneralOptions.execute_actions()

    tf = now()
    msg = "Execution has finished at $(Dates.format(tf, "yyyy-mm-dd HH:MM:SS"))\nTotal elapsed time: $(canonicalize(tf-t0))"
    LogOptions.add_message(msg, new_status = LogOptions.task_info)

    return
end


function main(;
    input_file::Union{String, Nothing} = nothing,
    input_file_dir::Union{String, Nothing} = nothing,
    input_dir::Union{String, Nothing} = nothing,
    output_dir::Union{String, Nothing} = nothing,
    open_ui::Bool = true,
    execute::Bool = false,
)
    if open_ui
        MyMooringUI.open_ui()
        execute && MyMooringUI.run_from_ui(
            input_file_dir = input_file_dir,
            input_file = input_file,
            input_dir = input_dir,
            output_dir = output_dir,
        )
    elseif execute
        run_program(
            input_file_dir = input_file_dir,
            input_file = input_file,
            input_dir = input_dir,
            output_dir = output_dir,
        )
    end


    return nothing
end

end # Module MyMooring
