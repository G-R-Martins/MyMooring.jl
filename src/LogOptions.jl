module LogOptions
using Gtk
import ..MyMooring: ui_is_opened

@enum LOG_OPT begin
    log_opt_ui
    log_opt_console
end
log_opt::LOG_OPT = log_opt_ui

#==
    Console
==#
const def_list_preffix = Dict(
    :loading => [
        "___________________________________\n\n ⦿ Limit State: ",
        "   ⊚ Load case: ",
        "     ∘ File: ",
        "       ► ",
    ],
    :calc => [" ⟶ ", "    ► ", "    ► "],
    :breaking => ["\n___________________________________\n"],
)

#== 
    UI
==#
@enum TASK_STATUS begin
    task_none
    task_inprogress
    task_done
    task_fail
    task_warning
    task_info
end

const log_icons = Dict{TASK_STATUS, Union{Gtk.GtkImage, Gtk.GtkSpinner}}(
    task_inprogress => GtkSpinner(name = "", active = true),
    task_fail =>
        GtkImage("", icon_name = "gtk-no", storage_type = Gtk.GtkImageType.GTK_IMAGE_ICON_NAME),
    task_done => GtkImage(
        "",
        icon_name = "gtk-yes",
        storage_type = Gtk.GtkImageType.GTK_IMAGE_ICON_NAME,
    ),
    task_warning => GtkImage(
        "",
        icon_name = "gtk-dialog-warning",
        storage_type = Gtk.GtkImageType.GTK_IMAGE_ICON_NAME,
    ),
    task_info => GtkImage(
        "",
        icon_name = "gtk-info",
        storage_type = Gtk.GtkImageType.GTK_IMAGE_ICON_NAME,
    ),
    task_none => GtkImage(
        "",
        icon_name = "gtk-yes",
        storage_type = Gtk.GtkImageType.GTK_IMAGE_ICON_NAME,
    ),
    # task_none => GtkImage("", icon_name="gtk-discard", storage_type=Gtk.GtkImageType.GTK_IMAGE_ICON_NAME),
)

mutable struct CurrentTask
    id::Int
    message::Union{Nothing, String}
    status::TASK_STATUS
end
cur_task = CurrentTask(0, "", task_none)

mutable struct LogUI
    box::Union{Nothing, GtkBox}
    text::Union{Nothing, GtkTextBuffer}
    ts::Union{Nothing, GtkTreeStore}
    win::Union{Nothing, GtkWindow}
end
log_ui = LogUI(nothing, nothing, GtkTreeStore(String), nothing)


function set_log_table(ts::GtkTreeStore)
    log_ui.ts = ts
    return nothing
end

function update_ui_status(new_status::TASK_STATUS)
    # #DESCOMENTAR! cur_task.status == task_none || delete!(log_ui.box, log_icons[cur_task.status])
    # delete!(log_ui.box, log_icons[cur_task.status])

    cur_task.status = new_status
    # cur_task.id > 1 && push!(log_ui.box, log_icons[new_status])
    showall(log_ui.win)

    return nothing
end

function show_message(
    message::Union{Nothing, String} = nothing;
    log_type::Symbol = :text,
    level::Int = 0,
)
    new_status = cur_task.status

    cur_task.message = isnothing(message) ? "Task $(cur_task.id) done" : message
    ############## DESCOMENTAR E APAGAR A DE CIMA
    # cur_task.message = isnothing(message) ? "Task $(cur_task.id)" : message
    log_message =
        new_status == task_inprogress ? "Executing task..." :
        new_status == task_done ? "Task complete!" :
        new_status == task_fail ? "Task failed." : message

    if ui_is_opened[]
        GAccessor.text(log_ui.text, log_message, length(log_message))
        isnothing(message) || push!(log_ui.ts, (cur_task.message,))
        ############## DESCOMENTAR E APAGAR A DE CIMA
        # push!(log_ui.ts, (cur_task.message,))
    else
        if log_type == :text
            println(message)
        else
            println("$(def_list_preffix[log_type][level])")
        end
    end

    return nothing
end

function add_message(
    message::Union{Nothing, String} = nothing;
    new_status::Union{Nothing, TASK_STATUS} = nothing,
    log_type::Symbol = :text,
    level::Int = 0,
)
    cur_task.id += 1

    # @async begin
    if !isnothing(new_status) && ui_is_opened[]
        update_ui_status(new_status)
    end
    show_message(message, log_type = log_type, level = level)

    return nothing
end

function set_log_ui(box::GtkBox, text::GtkTextBuffer, win::GtkWindow)
    log_ui.box = box
    log_ui.text = text
    log_ui.win = win

    # push!(log_ui.box, log_icons[task_none])
    ########
    ########
    #### TROCAR - remover linha abaixo e descomentar a de cima
    ########
    ########
    push!(log_ui.box, GtkImage("", icon_name="gtk-yes", storage_type=Gtk.GtkImageType.GTK_IMAGE_ICON_NAME))
    
    return nothing
end

end # module
