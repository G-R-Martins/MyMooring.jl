
module CurrentSelection
using ..Database
using GLMakie

ls::Observable{String} = Observable{String}("")
lc::Observable{String} = Observable{String}("")
sim::Observable{String} = Observable{String}("")
line::Observable{Int} = Observable{Int}(-1)
elem::Observable{String} = Observable{String}("A")
const lc_id::Observable{Int} = Observable{Int}(-1)
const sim_id::Observable{Int} = Observable{Int}(-1)
platform::Observable{Int} = Observable{Int}(-1)
dof::Observable{String} = Observable{String}("")

lc_sim_ids_defined::Observable{Bool} = Observable(false)

function set_lc_sim_ids()
    lc_id[] = Database.get_lc_id_from_name(ls[], lc[])
    sim_id[] = Database.get_sim_id_from_name(lc_id[], sim[])
    return nothing
end


function update_selection(;
    ls_::Union{String, Nothing} = nothing,
    lc_::Union{String, Nothing} = nothing,
    sim_::Union{String, Nothing} = nothing,
    line_::Union{Int, Nothing} = nothing,
    elem_::Union{String, Nothing} = nothing,
    platform_::Union{Int, Nothing} = nothing,
    dof_::Union{String, Nothing} = nothing,
)
    !isnothing(ls_) && (ls[] = ls_)
    !isnothing(lc_) && (lc[] = lc_)
    !isnothing(sim_) && (sim[] = sim_)
    !isnothing(line_) && (line[] = line_)
    !isnothing(elem_) && (elem[] = elem_)
    !isnothing(platform_) && (platform[] = platform_)
    !isnothing(dof_) && (dof[] = dof_)

    set_lc_sim_ids()
    return nothing
end

end
