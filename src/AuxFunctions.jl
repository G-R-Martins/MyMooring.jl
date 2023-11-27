
module AuxFunc

using DataFrames, CSV
using SQLite


print_ok() = (printstyled("  ✓\n", bold = true, color = :green); nothing)

function get_text_repeated_var_to_load(sim::String, type::String, id::Int, result::String)
    return "\'$result\' is already loaded for $type $id and simulation '$sim'"
end

function get_vector_or_range(inp_opt)::AbstractVector

    isa(inp_opt, AbstractArray) && return convert(Vector, inp_opt)

    if !isa(inp_opt, AbstractDict) || !haskey(inp_opt, "from") || !haskey(inp_opt, "to")
        isa(inp_opt, Number) && return [inp_opt]

        throw(error("Failed to convert $(inp_opt) to a Vector or Range"))
    else
        return range(
            inp_opt["from"],
            inp_opt["to"],
            step = convert(Number, get(inp_opt, "step", 1)),
        )
    end

end  # AuxFunc.get_vector_or_range()


function combine_prefix_suffix(prefix, suffix)::Vector{AbstractString}
    prefix = isa(prefix, AbstractString) ? prefix : string.(AuxFunc.get_vector_or_range(prefix))
    suffix = isa(suffix, AbstractString) ? suffix : string.(AuxFunc.get_vector_or_range(suffix))

    ret = prefix .* suffix
    return isa(ret, Vector) ? ret : [ret]
end

function push_if_not_in!(dest, data)
    data ∉ dest && push!(dest, data)
    return nothing
end

is_abstract_array(data) = isa(data, AbstractArray)

title_and_symbol(s::AbstractString) = Symbol(titlecase(s))


join_with_comma(values::Union{Vector{String}, String})::String = join(values, ",")



#==
    #* comment
==#

function read_mat_write_csv(
    file_names::Vector{String},
    input_dir::String,
    output_dir::String,
    cols::Vector{Int},
    sample::Float64,
    dt::Float64,
    delim::Char = ';',
)

    for filename in file_names
        mat = matread(input_dir * filename * ".mat")

        CSV.write(
            output_dir * filename * ".csv",
            DataFrame(
                mat[filename]["data"][:, cols][1:Int(sample / dt):end, :],
                convert(Vector{String}, mat[filename]["header"][1, cols]),
            ),
            delim = delim,
        )
    end

    return nothing
end







function createtable!(
    db::SQLite.DB,
    nm::AbstractString,
    ::Tables.Schema{names, types};
    temp::Bool = false,
    ifnotexists::Bool = true,
    primarykey::Int = 0,
) where {names, types}
    temp = temp ? "TEMP" : ""
    ifnotexists = ifnotexists ? "IF NOT EXISTS" : ""
    typs = [types === nothing ? "BLOB" : sqlitetype(fieldtype(types, i)) for i in 1:length(names)]
    primarykey > 0 && (typs[primarykey] *= " PRIMARY KEY")
    columns = [string(esc_id(String(names[i])), ' ', typs[i]) for i in 1:length(names)]

    return SQLite.execute(db, "CREATE $temp TABLE $ifnotexists \"$nm\" ($(join(columns, ',')))")
end

esc_id(x::AbstractString) = "\"" * replace(x, "\"" => "\"\"") * "\""
esc_id(X::AbstractVector{S}) where {S <: AbstractString} = join(map(esc_id, X), ',')

sqlitetype(::Type{T}) where {T <: Integer} = "INTEGER NOT NULL"
sqlitetype(::Type{T}) where {T <: Union{Missing, Integer}} = "INTEGER"
sqlitetype(::Type{T}) where {T <: AbstractFloat} = "REAL NOT NULL"
sqlitetype(::Type{T}) where {T <: Union{Missing, AbstractFloat}} = "REAL"
sqlitetype(::Type{T}) where {T <: AbstractString} = "TEXT NOT NULL"
sqlitetype(::Type{T}) where {T <: Union{Missing, AbstractString}} = "TEXT"
sqlitetype(::Type{Missing}) = "NULL"
sqlitetype(x) = "BLOB"




remove!(v::Vector{T}, item::T) where {T} = deleteat!(v, findall(x -> x == item, v))

function remove_occurrence!(v::Vector{T}, pattern::T) where {T}
    deleteat!(v, findall(x -> occursin(pattern, x), v))
end

end
