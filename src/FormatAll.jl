using JuliaFormatter
using DocStringExtensions
# using Documenter

"""
$(SIGNATURES)

"""
function format_all(
    file_path::String = ".";
    overwrite = true,
    verbose = false,
    format_markdown = false,
    style::JuliaFormatter.AbstractStyle = DefaultStyle(),
    indent = 4,
    margin = 100,
    always_for_in::Union{Bool, Nothing} = true,
    whitespace_typedefs = true,
    whitespace_ops_in_indices = true,
    remove_extra_newlines = false,
    import_to_using = false,
    pipe_to_function_call = false,
    short_to_long_function_def = false,
    long_to_short_function_def = true,
    always_use_return = false,
    whitespace_in_kwargs = true,
    annotate_untyped_fields_with_any = true,
    format_docstrings = true,
    align_struct_field = true,
    align_conditional = false,
    align_assignment = false,
    align_pair_arrow = false,
    conditional_to_if = false,
    normalize_line_endings = "auto",
    align_matrix = false,
    trailing_comma = true,
    indent_submodule = false,
    separate_kwargs_with_semicolon = false,
    surround_whereop_typeparameters = true,
)
    JuliaFormatter.format(
        file_path;
        overwrite,
        verbose,
        format_markdown,
        style,
        indent,
        margin,
        always_for_in,
        whitespace_typedefs,
        whitespace_ops_in_indices,
        remove_extra_newlines,
        import_to_using,
        pipe_to_function_call,
        short_to_long_function_def,
        long_to_short_function_def,
        always_use_return,
        whitespace_in_kwargs,
        annotate_untyped_fields_with_any,
        format_docstrings,
        align_struct_field,
        align_conditional,
        align_assignment,
        align_pair_arrow,
        conditional_to_if,
        normalize_line_endings,
        align_matrix,
        trailing_comma,
        indent_submodule,
        separate_kwargs_with_semicolon,
        surround_whereop_typeparameters,
    )

    return nothing
end
