
module MyMooringUI

using Gtk, SQLite, DataFrames
using GLMakie, CairoMakie
using Distributions

using ..Database
using ..Dashboard
using ..IOFile
using ..LogOptions
using ..AuxFunc
import ..CurrentSelection as cur

using ..MyMooring


#==
    STRUCTS
==#

mutable struct TimeSeriesData
    cols::Vector{String}
    data::Matrix{Float64}
    df::DataFrame
    ls::String
    lc::Int
    sim::Int

    TimeSeriesData() = new(String[], Matrix{Float64}(undef, 0, 0), DataFrame(), "", -1, -1)
    TimeSeriesData(cols::Vector{String}, data::Matrix{Float64}, df::DataFrame) =
        new(cols, data, df, "", 1, 1)
end
const timeseries_data = TimeSeriesData()


@enum DESC_TAB_OPT begin
    Simulations = 0
    LinesEval
    LinesResist
    PlatformsEval
    MotionLim
end
@enum RES_TAB_OPT begin
    Design_Tension = 0
    Motion
end
@enum VAR_OPT begin
    LineTension
    PlatformMotion
end

mutable struct ResultTableOpt
    desc::Union{Nothing, DESC_TAB_OPT}
    res::Union{Nothing, RES_TAB_OPT}
    ls::String
    lc::Int
    var::Union{Nothing, VAR_OPT}
    save_fmt::String

    ResultTableOpt() = new(Simulations, Design_Tension, "", -1, nothing, "csv")
end
const res_tab = ResultTableOpt()

@enum RESULT_TAB_DATA begin
    DESCRIPTION
    RESULTS
    SIMULATION_STATS
end

#==
    MODULE VARIABLES
==#
glade = GtkBuilder(filename = "src/UI_Gtk.glade")

GLMakie.activate!()

"""
"""
opt_res = (ls = String[], lc = Dict{String, Int}(), var = Dict{String, VAR_OPT}())


#==
    FUNCTIONS
==#


function show_table(
    parent_container,
    df::DataFrame;
    cell_type::Union{Type, Vector{Type}} = String,
    sort_col::Union{Nothing, Int} = nothing,
    resizable_cols::Bool = true,
    reordable_cols::Bool = true,
)
    empty!(parent_container)

    n_cols = size(df, 2)
    list_store = GtkTreeStore(repeat([cell_type], n_cols)...)

    foreach(row -> push!(list_store, string.(Tuple(row))), eachrow(df))

    tv = GtkTreeView(
        GtkTreeModel(list_store),
        enable_grid_lines = Gtk.GtkTreeViewGridLines.GTK_TREE_VIEW_GRID_LINES_BOTH,
        enable_tree_lines = true,
    )

    col_names = names(df)
    cols = [
        GtkTreeViewColumn(
            col_names[i + 1],
            GtkCellRendererText(),
            Dict([("text", i)]),
            sort_column_id = i,
        ) for i in 0:(n_cols - 1)
    ]
    push!(tv, cols...)
    push!(parent_container, tv)

    # make columns resizable and reorderable
    reordable_cols && foreach((c, i) -> GAccessor.reorderable(c, i), cols, 1:n_cols)
    resizable_cols && foreach(c -> GAccessor.resizable(c, true), cols)

    # make column with time sortable
    isnothing(sort_col) || GAccessor.sort_column_id(cols[sort_col], sort_col)

    showall(glade["window_main"])

    return nothing
end


function add_table_to_container(
    container,
    data::DataFrame;
    cell_type = String,
    new_col_names::Union{Missing, Vector{String}} = missing,
    sort_col::Union{Nothing, Int} = nothing,
    resizable_cols::Bool = true,
    reordable_cols::Bool = true,
    fill_table::Bool = false,
)
    n_cols = isempty(new_col_names) ? size(data, 2) : length(new_col_names)
    # create List Store
    list_store = GtkTreeStore(repeat([cell_type], n_cols)...)

    if fill_table
        display(data)
        foreach(row -> push!(list_store, string.(Tuple(row))), eachrow(data))
    end

    # create List View
    tv = GtkTreeView(
        GtkTreeModel(list_store),
        enable_grid_lines = Gtk.GtkTreeViewGridLines.GTK_TREE_VIEW_GRID_LINES_BOTH,
        enable_tree_lines = true,
    )

    col_names = ismissing(new_col_names) ? names(data) : new_col_names
    cols = [
        GtkTreeViewColumn(
            col_names[i + 1],
            GtkCellRendererText(),
            Dict([("text", i)]),
            sort_column_id = i,
        ) for i in 0:(n_cols - 1)
    ]
    push!(tv, cols...)
    push!(container, tv)

    # make columns resizable and reorderable
    reordable_cols && foreach((c, i) -> GAccessor.reorderable(c, i), cols, 1:n_cols)
    resizable_cols && foreach(c -> GAccessor.resizable(c, true), cols)

    # make column with time sortable
    isnothing(sort_col) || GAccessor.sort_column_id(cols[sort_col], sort_col)

    return list_store
end

function reset_table(list_store, data::DataFrame)
    empty!(list_store)
    foreach(row -> push!(list_store, string.(Tuple(row))), eachrow(data))

    return nothing
end


function push_checkbtn_to_container!(
    box::Union{GtkBox, GtkTreeStore},
    btn::GtkCheckButton,
    label::String;
    ls::String,
    lc::Int = -1,
    sim::Int = -1,
)

    push!(box, btn)
    signal_connect(btn, "toggled") do e
        timeseries_data.ls = ls
        timeseries_data.lc = lc
        timeseries_data.sim = sim

        isActive = get_gtk_property(btn, :active, Bool)
        if isActive
            push!(timeseries_data.cols, label)
        else
            AuxFunc.remove!(timeseries_data.cols, label)
        end
    end
end


function set_timeseries_data()

    timeseries_begin = get_gtk_property(glade["entry_timeseries_begin"], "text", String)
    timeseries_end = get_gtk_property(glade["entry_timeseries_end"], "text", String)
    timeseries_step = parse(Int, get_gtk_property(glade["entry_timeseries_step"], "text", String))

    timeseries_data.df = Database.get_columns_from_table(
        "$(timeseries_data.ls)_Line_Tensions",
        vcat("Time", timeseries_data.cols),
        """
            LC_ID = $(timeseries_data.lc) AND Sim_ID = $(timeseries_data.sim) AND 
            Time BETWEEN $timeseries_begin AND $timeseries_end
        """,
    )
    timeseries_data.df = timeseries_data.df[begin:timeseries_step:end, :]

    return nothing
end



function fill_combobox_ls()
    for ls in Database.loaded[:summary].LimitState |> unique
        push!(glade["cb_ls"], ls)
        push!(opt_res.ls, ls)
    end

    return nothing
end


function fill_combobox_child(selected::String)
    if selected == "ls"
        push!(glade["cb_lc"], "All")
        opt_res.lc["All"] = 0

        df = MyMooring.Database.loaded[:summary]
        df = df[df.LimitState .== res_tab.ls, [:LC_ID, :LC_Name]] |> unique
        for (lc_id, lc_name) in Tables.namedtupleiterator(df)

            push!(glade["cb_lc"], lc_name)
            opt_res.lc[lc_name] = lc_id
        end
    elseif selected == "lc"
        push!(glade["cb_var"], "Line tension")
        opt_res.var["Line tension"] = LineTension

        push!(glade["cb_var"], "Platform motion")
        opt_res.var["Platform motion"] = PlatformMotion
    end

    return nothing
end


function set_res_combobox_events()
    # cb_ls = glade["cb_ls"];
    # cb_lc = glade["cb_lc"];
    # cb_var = glade["cb_var"];

    signal_connect(glade["cb_ls"], "changed") do widget, others...
        # Gtk.@sigatom res_tab.ls = Gtk.bytestring(GAccessor.active_text(glade["cb_ls"]))
        Gtk.@sigatom begin
            res_tab.ls = Gtk.bytestring(GAccessor.active_text(glade["cb_ls"]))
            clear_combobox_items(glade["cb_lc"])
            clear_combobox_items(glade["cb_var"])

            empty!(opt_res.lc)
            empty!(opt_res.var)
            fill_combobox_child("ls")
        end

    end

    signal_connect(glade["cb_lc"], "changed") do widget, others...
        # Gtk.@sigatom res_tab.lc = opt_res.lc[Gtk.bytestring(GAccessor.active_text(glade["cb_lc"]))]
        Gtk.@sigatom begin
            res_tab.lc = opt_res.lc[Gtk.bytestring(GAccessor.active_text(glade["cb_lc"]))]
            clear_combobox_items(glade["cb_var"])

            empty!(opt_res.var)
            fill_combobox_child("lc")
        end
    end

    signal_connect(glade["cb_var"], "changed") do widget, others...
        Gtk.@sigatom res_tab.var =
            opt_res.var[Gtk.bytestring(GAccessor.active_text(glade["cb_var"]))]
    end


    signal_connect(glade["cb_desc"], "changed") do widget, others...
        res_tab.desc = DESC_TAB_OPT(get_gtk_property(glade["cb_desc"], :active, Int))
    end
    signal_connect(glade["cb_res"], "changed") do widget, others...
        res_tab.res = RES_TAB_OPT(get_gtk_property(glade["cb_res"], :active, Int))
    end
    signal_connect(glade["res_save_fmt"], "changed") do widget, others...
        res_tab.save_fmt = get_gtk_property(glade["res_save_fmt"], :active, String)
    end

    return nothing
end



function place_timeseries_btns()
    btnbox = glade["box_timeseries"]

    for ((ls,), ls_data) in pairs(groupby(Database.loaded[:summary] |> unique, :LimitState))
        # Tree view for results of the current limit state
        expander_ls = GtkExpander(
            ls,
            halign = Gtk.GtkAlign.GTK_ALIGN_START,
            valign = Gtk.GtkAlign.GTK_ALIGN_START,
        )
        push!(btnbox, expander_ls)

        # Vertical box with buttons for summaries and LC trees
        btnbox_ls =
            GtkBox(:v, halign = Gtk.GtkAlign.GTK_ALIGN_START, valign = Gtk.GtkAlign.GTK_ALIGN_START)
        push!(expander_ls, btnbox_ls)

        for ((lc,), lc_data) in pairs(groupby(ls_data, :LC_Name))
            # Tree for load cases
            expander_lc = GtkExpander(
                "LC: $(lc)",
                margin_left = 10,
                margin_right = 10,
                halign = Gtk.GtkAlign.GTK_ALIGN_START,
                valign = Gtk.GtkAlign.GTK_ALIGN_START,
            )
            # push!(expander_ls, expander_lc);
            push!(btnbox_ls, expander_lc)

            # Vertical box with buttons to trigger results' statistics 
            btnbox_lc = GtkBox(
                :v,
                halign = Gtk.GtkAlign.GTK_ALIGN_START,
                valign = Gtk.GtkAlign.GTK_ALIGN_START,
            )
            push!(expander_lc, btnbox_lc)

            for row_ in eachrow(lc_data[!, [:Sim_ID, :Sim_Name]])
                # Tree for load cases
                expander_sim = GtkExpander(
                    "Sim: $(row_.Sim_Name)",
                    margin_left = 15,
                    margin_right = 15,
                    halign = Gtk.GtkAlign.GTK_ALIGN_START,
                    valign = Gtk.GtkAlign.GTK_ALIGN_START,
                )
                # push!(expander_lc, expander_sim);
                push!(btnbox_lc, expander_sim)

                # Vertical box with buttons to trigger results' statistics 
                btnbox_sim = GtkBox(
                    :v,
                    halign = Gtk.GtkAlign.GTK_ALIGN_START,
                    valign = Gtk.GtkAlign.GTK_ALIGN_START,
                )
                push!(expander_sim, btnbox_sim)

                for row in Tables.namedtupleiterator(
                    Database.get_loaded_lines_elements(ls, lc, row_.Sim_Name),
                )
                    push_checkbtn_to_container!(
                        btnbox_sim,
                        GtkCheckButton(
                            "Line $(row.ID) - Element $(row.Element)",
                            halign = Gtk.GtkAlign.GTK_ALIGN_START,
                            valign = Gtk.GtkAlign.GTK_ALIGN_START,
                        ),
                        "Line$(row.ID)_$(row.Element)";
                        ls = ls,
                        lc = Database.get_lc_id_from_name(ls, lc),
                        sim = row_.Sim_ID,
                    )
                end
            end
        end
    end
end


function open_chooser(action::Int32 = GtkFileChooserAction.OPEN; file_format::String = "json")
    if action == GtkFileChooserAction.OPEN
        return open_dialog(
            "Choose input file",
            GtkNullContainer(),
            ("*.$file_format", GtkFileFilter("*.$file_format", name = "All supported formats")),
            action = action,
        )
        # return splitpath(dialog_out)[end];
    else
        return open_dialog("Choose directory", GtkNullContainer(), action = action)
    end
end


function set_menu_case()

    menu_case = Gtk.Menu(glade["menuitem_case"])
    summary = Database.loaded[:summary][!, [:LimitState, :LC_Name, :Sim_Name]] |> unique

    for ((ls,), ls_data) in pairs(groupby(summary, :LimitState))
        item_ls = Gtk.MenuItem(ls, use_underline = false)
        push!(menu_case, item_ls)
        # Menu for load cases
        menu_lc = Gtk.Menu(item_ls)
        for ((lc,), lc_data) in pairs(groupby(ls_data, :LC_Name))
            item_lc = Gtk.MenuItem(lc, use_underline = false)
            push!(menu_lc, item_lc)
            # Menu for simulations 
            menu_sim = Gtk.Menu(item_lc)
            for sim in lc_data.Sim_Name
                item_sim = Gtk.MenuItem(sim, use_underline = false)
                push!(menu_sim, item_sim)


                # Click event
                signal_connect(item_sim, "activate") do widget
                    cur.update_selection(; ls_ = ls, lc_ = lc, sim_ = sim)
                    set_menu_line_tension(Database.get_loaded_lines_elements(ls, lc, sim))
                    Database.has_platforms_loaded() &&
                        set_menu_platform(Database.get_loaded_platforms(ls, lc, sim))
                    str = "$ls | $lc | $sim"
                    GAccessor.text(glade["tb_dash_case"], str, length(str))
                    showall(glade["window_main"])
                end
            end
        end
    end
end


function set_menu_line_tension(lines::DataFrame)
    # Menu for lines
    menu_lines = Gtk.Menu(glade["menuitem_timeseries"])
    for line in sort(lines.ID)
        item_line = Gtk.MenuItem("Line $line", use_underline = false)
        push!(menu_lines, item_line)
        # Menu for line element 
        menu_elem = Gtk.Menu(item_line)
        for elem in lines[lines.ID .== line, :Element]
            item_elem = Gtk.MenuItem(elem, use_underline = false)
            push!(menu_elem, item_elem)
            # Click event
            signal_connect(item_elem, "activate") do widget
                cur.update_selection(; line_ = line, elem_ = elem)
                Dashboard.load_timeseries()
                str = "Line $line | Element $elem"
                GAccessor.text(glade["tb_dash_timeseries"], str, length(str))
            end
        end
    end
end

function set_menu_platform(platforms)
    # Menu for lines
    menu_platfs = Gtk.Menu(glade["menuitem_platf_motion"])
    for platf in sort(platforms.ID |> unique)
        item_platf = Gtk.MenuItem("Platform $platf", use_underline = false)
        push!(menu_platfs, item_platf)
        # Menu for platform variables
        menu_var = Gtk.Menu(item_platf)
        for var in platforms[platforms.ID .== platf, :Quantity]
            item_var = Gtk.MenuItem(var, use_underline = false)
            push!(menu_var, item_var)
            # Click event
            signal_connect(item_var, "activate") do widget
                cur.update_selection(; platform_ = platf, dof_ = var)
                Dashboard.load_timeseries(:platform)
                Dashboard.update_plot!(:platf_motion)
                str = "Platform $platf | $var"
                GAccessor.text(glade["tb_dash_motion"], str, length(str))
            end
        end
    end
end

function set_menu_timeseries()

    menu_timeseries = Gtk.Menu(glade["menuitem_timeseries"])
    summary = Database.loaded[:summary][!, [:LimitState, :LC_Name, :Sim_Name]]

    for ((ls,), ls_data) in pairs(groupby(summary, :LimitState))
        item_ls = Gtk.MenuItem(ls, use_underline = false)
        push!(menu_timeseries, item_ls)
        # Menu for load cases
        menu_lc = Gtk.Menu(item_ls)
        for ((lc,), lc_data) in pairs(groupby(ls_data, :LC_Name))
            item_lc = Gtk.MenuItem(lc, use_underline = false)
            push!(menu_lc, item_lc)
            # Menu for simulations 
            menu_sim = Gtk.Menu(item_lc)
            for sim in lc_data.Sim_Name
                item_sim = Gtk.MenuItem(sim, use_underline = false)
                push!(menu_sim, item_sim)

                # Menu for lines
                menu_lines = Gtk.Menu(item_sim)
                for line in Database.get_loaded_lines_elements(ls, lc, sim).ID
                    item_line = Gtk.MenuItem("Line $line", use_underline = false)
                    push!(menu_lines, item_line)
                    # Menu for line element 
                    menu_elem = Gtk.Menu(item_line)
                    for elem in ["A"]
                        item_elem = Gtk.MenuItem(elem, use_underline = false)
                        push!(menu_elem, item_elem)
                        # Click event
                        signal_connect(item_elem, "activate") do widget
                            cur.update_selection(;
                                ls_ = ls,
                                lc_ = lc,
                                sim_ = sim,
                                line_ = line,
                                elem_ = elem,
                            )
                            Dashboard.load_timeseries()
                            str = "$ls | $lc | $sim | Line $line | $elem"
                            GAccessor.text(glade["tb_dash_timeseries"], str, length(str))
                        end
                    end
                end
            end
        end
    end

    return nothing
end


function clear_simulation_stats_combobox()
    # clear_combobox_items(glade["cb_ls"]);
    clear_combobox_items(glade["cb_lc"])
    clear_combobox_items(glade["cb_var"])

    return nothing
end


function clear_combobox_items(cb)
    Gtk.@sigatom set_gtk_property!(cb, "active", 0) #! s 
    # set_gtk_property!(cb, "active", 0) #! s 
    # @async set_gtk_property!(cb, "active", 0) #! s 

    while get_gtk_property(cb, "active", Int) >= 0
        delete!(cb, 1)
        Gtk.@sigatom set_gtk_property!(cb, "active", 0)
        # set_gtk_property!(cb, "active", 0) 
        # @async set_gtk_property!(cb, "active", 0) 
    end

    return nothing
end


function get_res_tab_data(type::RESULT_TAB_DATA)
    tbl = ""
    cols = ""
    where_ = missing
    orderby_clause = missing
    join_clause = missing

    if type == SIMULATION_STATS
        tbl = "$(res_tab.ls)_$(res_tab.var == LineTension ? "Line" : "Motion")_Statistics AS stats"
        cols =
            res_tab.var == LineTension ? """
         LC_Name AS LC, 
         Sim_Name AS Simulation, 
         Line_ID AS Line, 
         Element, 
         Max AS "Maximum Tension (N)", 
         Mean AS "Mean Tension (N)", 
         Min AS "Minimum Tension (N)",
         Std AS "Std Tension (N)", 
         CV_percent AS "CV (%)", 
         Skewness, 
         Kurtosis, 
         Max_Dyn_Amplification_Factor AS "Max Dynamic Amplification"
     """ : """
         LC_Name AS LC,
         Sim_Name AS Simulation,
         ID AS Platform,
         Quantity AS Variable,
         Max AS "Maximum (m or deg)",
         Mean AS "Mean (m or deg)",
         Min AS "Minimum (m or deg)",
         Std AS "Std (m or deg)",
         CV_percent AS "CV (%)",
         Skewness,
         Kurtosis
     """
        where_ = iszero(res_tab.lc) ? missing : "stats.LC_ID = $(res_tab.lc)"
        join_clause = Database.set_join_clause(
            "INNER",
            "Simulations_Summary AS summary",
            "summary.LC_Id = stats.LC_Id AND summary.Sim_Id = stats.Sim_Id",
        )

    elseif type == RESULTS
        tbl = "$(res_tab.res)_Summary AS summary"
        cols = res_tab.res == Design_Tension ? """
            LC_Name AS LC,
            Line_ID AS Line,
            Element,
            Mean_Tension AS "Mean Tension (N)", 
            Dyn_Tension AS "Dynamic Tension (N)", 
            Resistance AS "Resistance (N)", 
            Design_Tension AS "Design Tension (N)", 
            Utilization_Factor AS "Utilization Factor", 
            Safety_Factor AS "Safety Factor", 
            Status 
        """ : """
            LC_Name AS LC,
            ID AS Platform,
            Quantity AS Variable,
            Max AS "Maximum (m or deg)", 
            Min AS "Minimum (m or deg)", 
            Allowed AS "Allowed (m or deg)", 
            Status 
        """
        where_ = """summary.LimitState = "$(res_tab.ls)" """
        join_clause = Database.set_join_clause(
            "INNER",
            "Simulations_Summary AS sim",
            "sim.LC_Id = summary.LC_Id",
        )

    else # type == DESCRIPTION
        if res_tab.desc == Simulations
            tbl = "Simulations_Summary"
            cols = """
                LimitState AS "Limit state",
                LC_Name AS LC,
                Sim_Name AS Simulation
            """
            orderby_clause =
                Database.set_order_by_clause([""" "Limit state" """, "LC", "Simulation"])
        elseif res_tab.desc == LinesEval
            tbl = "Line_Elements"
            cols = """
                LimitState AS "Limit state",
                Line_ID AS Line,
                Element
            """
            orderby_clause = Database.set_order_by_clause([""" "Limit state" """, "Line"])
        elseif res_tab.desc == PlatformsEval
            tbl = "Platforms"
            cols = """
                LimitState AS "Limit state",
                Platform_ID AS Platform,
                Quantity AS Variable
            """
            orderby_clause = Database.set_order_by_clause([""" "Limit state" """, "Platform"])
        elseif res_tab.desc == LinesResist
            tbl = "Resistances"
            cols = """
                ID AS Line,
                Element,
                Value AS "Strength (N)"
            """
            orderby_clause = Database.set_order_by_clause(["Line"])
            where_ = "Object = 'Line' AND Quantity = 'Strength'"
        elseif res_tab.desc == MotionLim
            tbl = "Movement_Limitation"
            cols = """
                ID AS Platform,
                Quantity AS Variable,
                Value AS "Value (m or deg)"
            """
            orderby_clause = Database.set_order_by_clause(["Platform"])
            where_ = "Object = 'Platform'"
        end
    end

    df = Database.get_columns_from_table(
        tbl,
        cols,
        where_,
        join_clause = join_clause,
        orderby_clause = orderby_clause,
        is_distinct = true,
    )
    
    return df
end

function save_results(
    tab_opt::RESULT_TAB_DATA,
    fname::String;
    df::Union{Nothing, DataFrame} = nothing,
    format = "CSV",
)
    IOFile.savetable(
        isnothing(df) ? get_res_tab_data(tab_opt) : df,
        joinpath(get_gtk_property(glade["tb_output_dir"], :text, String), fname);
        format = format,
    )

    return nothing
end

function set_glade_btns_events()

    #==
        Event to load time series data
    ==#
    signal_connect(glade["btn_timeseries_load"], "clicked") do e
        set_timeseries_data()

        view_timeseries = glade["view_timeseries_table"]
        empty!(view_timeseries)
        store = add_table_to_container(
            view_timeseries,
            timeseries_data.df;
            new_col_names = names(timeseries_data.df),
            resizable_cols = false,
            reordable_cols = false,
            fill_table = true,
        )
        showall(glade["window_main"])
    end

    #==
        IO events    
    https://discourse.julialang.org/t/gtk-jl-gtkfilechooserbutton-question/24526
    ==#
    # Directories
    signal_connect(glade["btn_choose_input_file"], "clicked") do widget
        txt = open_chooser(GtkFileChooserAction.OPEN)
        update_text("input_file", txt)
        IOFile.set_input_file(txt)
    end

    signal_connect(glade["btn_choose_input_dir"], "clicked") do widget
        txt = open_chooser(GtkFileChooserAction.SELECT_FOLDER)
        update_text("input_dir", txt)
        IOFile.set_directories(input_dir = txt)
    end

    signal_connect(glade["btn_choose_output_dir"], "clicked") do widget
        txt = open_chooser(GtkFileChooserAction.SELECT_FOLDER)
        update_text("output_dir", txt)
        IOFile.set_directories(output_dir = txt)
    end

    #== 
        Timeseries tab
    ==#

    # Timeseries table
    signal_connect(glade["btn_timeseries_save"], "clicked") do e
        set_timeseries_data()
        fname = get_gtk_property(glade["entry_timeseries_filename"], :text, String)

        if length(fname) < 1
            LogOptions.add_message(
                "Please specify the file name to export the table.",
                new_status = LogOptions.task_warning,
            )
        else
            IOFile.savetable(
                timeseries_data.df,
                joinpath(get_gtk_property(glade["tb_output_dir"], :text, String), fname);
                format = lowercase(
                    get_gtk_property(glade["entry_timeseries_format"], :text, String),
                ),
            )
        end
    end


    #==
        Results tab
    ==#

    # Save data
    signal_connect(glade["btn_desc_save"], "clicked") do e
        save_results(
            DESCRIPTION,
            replace(Gtk.bytestring(GAccessor.active_text(glade["cb_desc"])), " " => "_"),
            format = lowercase(Gtk.bytestring(GAccessor.active_text(glade["res_save_fmt"]))),
        )
    end
    signal_connect(glade["btn_res_save"], "clicked") do e
        save_results(
            RESULTS,
            replace(Gtk.bytestring(GAccessor.active_text(glade["cb_res"])), " " => "_"),
            format = lowercase(Gtk.bytestring(GAccessor.active_text(glade["res_save_fmt"]))),
        )
    end
    signal_connect(glade["btn_simulation_stats_save"], "clicked") do e
        fname =
            replace(Gtk.bytestring(GAccessor.active_text(glade["cb_ls"])), " " => "_") *
            replace(Gtk.bytestring(GAccessor.active_text(glade["cb_lc"])), " " => "_") *
            replace(Gtk.bytestring(GAccessor.active_text(glade["cb_var"])), " " => "_")

        save_results(
            SIMULATION_STATS,
            fname,
            format = lowercase(Gtk.bytestring(GAccessor.active_text(glade["res_save_fmt"]))),
        )
    end

    # Load data
    signal_connect(glade["btn_desc_load"], "clicked") do e
        show_table(glade["sw_res_up"], get_res_tab_data(DESCRIPTION))
    end
    signal_connect(glade["btn_res_load"], "clicked") do e
        show_table(glade["sw_res_up"], get_res_tab_data(RESULTS))
    end
    signal_connect(glade["btn_simulation_stats_load"], "clicked") do e
        show_table(glade["sw_res_down"], get_res_tab_data(SIMULATION_STATS))
    end


    #==
        Dashboards
    ==#

    # Lines
    signal_connect(glade["btn_dash_tension"], "clicked") do e
        Dashboard.show_dashboard(:timeseries)
    end
    signal_connect(glade["btn_dash_tension_stats"], "clicked") do e
        Dashboard.show_dashboard(:stats)
    end
    signal_connect(glade["btn_dash_tension_save"], "clicked") do e
        fname = join(["tension", cur.ls[], cur.lc[], cur.sim[], cur.line[], cur.elem[]], "_")
        save_fig(Dashboard.dashboard_timeseries, fname)
    end

    # Platforms
    signal_connect(glade["btn_dash_motion"], "clicked") do e
        Dashboard.show_dashboard(:platf_motion)
    end


    #==
        Run
    ==#
    signal_connect(glade["btn_run"], "clicked") do e
        run_from_ui()
    end

end




function save_fig(fig::Figure, fname::String; format::String = "pdf")
    CairoMakie.activate!()
    fname = "$(joinpath(get_gtk_property(glade["tb_output_dir"], :text, String), fname)).$format"
    CairoMakie.save(fname, fig)
    GLMakie.activate!()

    return nothing
end



function update_text(buffer::String, txt::String)
    GAccessor.text(glade["tb_$buffer"], txt, length(txt))
    return nothing
end

function run_from_ui(;
    input_file_dir::Union{String, Nothing} = nothing,
    input_file::Union{String, Nothing} = nothing,
    input_dir::Union{String, Nothing} = nothing,
    output_dir::Union{String, Nothing} = nothing,
)
    isnothing(input_file) || update_text("input_file", input_file)
    isnothing(input_dir) || update_text("input_dir", input_dir)
    isnothing(output_dir) || update_text("output_dir", output_dir)

    MyMooring.run_program(
        input_file_dir = input_file_dir,
        input_file = input_file,
        input_dir = input_dir,
        output_dir = output_dir,
    )

    # place_stats_btns();
    fill_combobox_ls()
    set_res_combobox_events()
    place_timeseries_btns()
    set_menu_case()

    showall(glade["window_main"])

    return nothing
end


function open_ui()
    LogOptions.set_log_table(
        add_table_to_container(
            glade["sw_log"],
            DataFrame();
            new_col_names = ["Description"],
            sort_col = nothing,
            reordable_cols = false,
        ),
    )

    clear_simulation_stats_combobox()
    set_glade_btns_events()
    LogOptions.set_log_ui(glade["box_log"], glade["tb_log_progress"], glade["window_main"])

    if !isinteractive()
        @async Gtk.gtk_main()
        Gtk.waitforsignal(glade["window_main"], :destroy)
    end

    showall(glade["window_main"])

    MyMooring.ui_is_opened[] = true

    return nothing
end

end


