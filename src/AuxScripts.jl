module AuxScripts

export scripts, set_scripts, execute_script

abstract type Script end

@enum Moment begin
    Beginning
    BeforeAnalysis
    AfterAnalysis
    End
end

const scripts = Dict(
    Beginning => Vector{Script}(),
    BeforeAnalysis => Vector{Script}(),
    AfterAnalysis => Vector{Script}(),
    End => Vector{Script}(),
)

struct JuliaFile <: Script
    name::String
    when::Moment
    definition::String
end

struct JuliaInline <: Script
    name::String
    when::Moment
    definition::String
end

struct PythonFile <: Script
    name::String
    when::Moment
    definition::String
end

struct PythonInline <: Script
    name::String
    when::Moment
    definition::String
end

struct TerminalScript <: Script
    name::String
    when::Moment
    definition::String
end

get_possible_moments() = "'Beginning', 'BeforeAnalysis', 'AfterAnalysis'"

function set_scripts(input::Vector{Dict{String, String}})
    for script in input
        type = get_script_type(script["type"])
        !(type <: Script) && continue

        name = get(script, "name", "Script $(length(scripts)+1)")
        moment = try_get_moment_from_string(script["when"])
        push!(scripts[moment], type(name, moment, script["definition"]))
    end

    return nothing
end

function get_script_type(type::String)
    type = titlecase(type)
    if type === "Terminal"
        return TerminalScript
    else
        return replace(titlecase(type), " " => "") |> Symbol |> eval
        # throw(UndefVarError(type))
    end
end

function execute_script(moment::Moment)
    if !isempty(scripts[moment])

        for script in scripts[moment]
            LogOptions.add_message(
                "Executing script \'$(script.name)\'",
                new_status = LogOptions.task_inprogress,
            )

            if script isa JuliaFile
                include(script.definition)
                JuliaFileMain()
            elseif script isa JuliaInline
                eval(Meta.parse(script.definition))
            elseif script isa PythonFile
                run(`python $(script.definition)`)
            elseif script isa PythonInline
                run(`python -c $(script.definition)`)
            else # TerminalScript
                run(`$(script.definition)`)
            end

            LogOptions.add_message(
                "Script \'$(script.name)\' execution has finished",
                new_status = LogOptions.task_done,
            )
        end
    end

    return nothing
end

function try_get_moment_from_string(input::String)
    try
        if input === "Beginning"
            return titlecase(input) |> Symbol |> eval
        else
            return replace(titlecase(input), " " => "") |> Symbol |> eval
        end
    catch e
        if e isa UndefVarError
            LogOptions.add_message(
                """\'$(e.var)\' is an invalid option.
Valid moments are: $(get_possible_moments())""",
                new_status = LogOptions.task_warning,
            )
        else
            LogOptions.add_message("Error: \"e\"", new_status = LogOptions.task_fail)
        end

        return nothing
    end
end

end # module 'AuxScripts'
