module Dashboard

using ..Database
import ..CurrentSelection as cur

using GLMakie
using SQLite
using DataFrames
using KernelDensity


dashboard_timeseries = Figure(;size = (1280, 720))
dashboard_stats = Figure(;size = (1280, 720))
dashboard_platf_motion = Figure(;size = (1280, 720))

tension_x = Observable{Vector{Float32}}([0.0f0, 1.0f0])
tension_y = Observable{Vector{Float32}}([0.0f0, 1.0f0])

platf_motion_df = Observable{DataFrame}()

const axis = Dict{Symbol, Union{Axis, Vector{Axis}}}()
plot_tension_density::Bool = true

const dashboard_defined = Dict{Symbol, Bool}(:timeseries => false, :stats => false)

function set_dashboards(; show_current_time::Bool = true, linkdensity::Bool = true)

    set_dash_line_timeseries(show_current_time, linkdensity)
    set_dash_line_stats()

    return nothing
end

function set_dash_line_timeseries(show_current_time::Bool, linkdensity::Bool)

    l_rng_tension_plt = 1:8

    if plot_tension_density
        axis[:timeseries] = Axis(
            dashboard_timeseries[l_rng_tension_plt, 1:3],
            title = @lift(
                "Line $($(cur.line)) - Element $($(cur.elem))  |  $($(cur.ls)) - $($(cur.lc)) - $($(cur.sim))"
            ),
            xlabel = "Time  (s)",
            ylabel = "Tension  (N)",
        )

        if linkdensity
            axis[:density] = Axis(
                dashboard_timeseries[l_rng_tension_plt, 4],
                title = "Tension density",
                xlabel = "Density",
            )
            linkyaxes!(axis[:timeseries], axis[:density])
            hideydecorations!(axis[:density])
        else
            axis[:density] = Axis(
                dashboard_timeseries[l_rng_tension_plt, 4:5],
                title = "Tension density",
                xlabel = "Tension  (N)",
                ylabel = "Density",
            )
        end
    else
        axis[:timeseries] = Axis(
            dashboard_timeseries[l_rng_tension_plt, :],
            title = "Line tension",
            xlabel = "Time  (s)",
            ylabel = "Tension  (N)",
        )
    end

    # Initial plot
    first_case = Database.loaded[:summary][1, :]
    df_tension = Database.get_columns_from_table(
        "$(first_case.LimitState)_Line_Tensions",
        ["*"],
        "LC_ID = $(first_case.LC_ID) AND Sim_ID = $(first_case.Sim_ID)",
    )[
        !,
        1:2,
    ]

    tension_x[] = df_tension[!, 1]
    tension_y[] = df_tension[!, 2]
    lines!(axis[:timeseries], tension_x, tension_y)
    autolimits!(axis[:timeseries])

    plot_tension_density &&
        density!(axis[:density], tension_y, direction = linkdensity ? :y : :x, inspectable = false)


    if show_current_time
        slider = Slider(
            dashboard_timeseries[9, 2:end],
            range = Observable([0.0f0, 1.0f0]),
            startvalue = 0.0f0,
        )
        set_cur_time_line(slider)

        on(axis[:timeseries].xaxis.attributes.limits) do limits_
            t0 = limits_[1] < tension_x[][begin] ? tension_x[][begin] : limits_[1]
            tf = limits_[2] > tension_x[][end] ? tension_x[][end] : limits_[2]

            slider.range[] = tension_x[][tension_x[] .>= t0 .&& tension_x[] .<= tf]
        end
    end

    DataInspector(dashboard_timeseries)
    return nothing
end

function set_dash_platf_timeseries(;
    is_offset::Bool = true,
    label::Union{Nothing, Observable{String}} = nothing,
    linkdensity::Bool = true,
)
    # Clear Figure
    Makie.empty!(dashboard_platf_motion)

    # Set plot title
    motion_title = @lift(
        "Platform $($(cur.platform)) - $($(cur.dof)) | $($(cur.ls)) - $($(cur.lc)) - $($(cur.sim))"
    )


    if is_offset
        # Set Axis()
        axlabels = (x = "Surge  (m)", y = "Sway  (m)")
        axis[:platf_motion] = Axis(
            dashboard_platf_motion[1, 1:5],
            title = motion_title,
            xlabel = axlabels.x,
            ylabel = axlabels.y,
        )

        Label(dashboard_platf_motion[2, 1], label, fontsize = 18, justification = :left)

    else
        # Set labels (of axes and offset)
        unit_ = cur.dof[] in ["Roll", "Pitch", "Yaw"] ? "deg" : "m"
        axlabels = (x = "Time  (s)", y = "$(cur.dof[])  ($unit_)")

        # Set Axis()
        axis[:platf_motion] = Axis(
            dashboard_platf_motion[1, 1:3],
            title = motion_title,
            xlabel = axlabels.x,
            ylabel = axlabels.y,
        )

        if linkdensity
            axis[:platf_motion_density] =
                Axis(dashboard_platf_motion[:, 4:5], title = "Motion density", xlabel = "Density")
            linkyaxes!(axis[:platf_motion], axis[:platf_motion_density])
            hideydecorations!(axis[:platf_motion_density])
        else
            axis[:platf_motion_density] = Axis(
                dashboard_platf_motion[:, 4:5],
                title = "Motion density",
                xlabel = "$(cur.dof[])",
                ylabel = "Density",
            )
        end

    end





    return nothing
end


function update_plot!(ax_name::Symbol)

    if ax_name == :platf_motion
        update_platf_motion!()
    end

    return nothing
end


function update_platf_motion!(; linkdensity = true)

    isoffset = lowercase(cur.dof.val) == "offset" ? true : false

    # Data to plot (from current simulation)
    df = platf_motion_df.val

    if isoffset

        # Data of current time
        row = @lift(df[df.Time .== parse(Float64, $(s_)), :])
        x = @lift([Float32($(row)[1, 2])])
        y = @lift([Float32($(row)[1, 3])])

        # Arrow (platform heading)
        a = Observable(0.3f0) # length
        u = @lift([$(a) * cosd($(row)[1, 4])])
        v = @lift([$(a) * sind($(row)[1, 4])])
        arrow_color = Observable(:magenta)

        # Set plot axis, labels, etc
        label_ = @lift("""
            Position (m, m): ($($(x)[1]), $($(y)[1]))
            Offset (m): $(round(sqrt(($(x)[1])^2 + ($(y)[1])^2), digits=2))
        """)
        set_dash_platf_timeseries(is_offset = isoffset, label = label_)

        # Plot data        
        contourf!(
            axis[:platf_motion],
            kde((df[!, 2], df[!, 3])),
            colormap = :jet,
            levels = 25, #0.005:0.005:0.995,
            linewidth = 0,
            # extendhigh = :white,
            # mode = :relative,
        )
        arrows!(x, y, u, v, linecolor = arrow_color, arrowcolor = arrow_color, linewidth = 3)
    else
        set_dash_platf_timeseries(is_offset = isoffset, linkdensity = linkdensity)

        lines!(axis[:platf_motion], df[!, 1], df[!, 2])
        density!(
            axis[:platf_motion_density],
            df[!, 2],
            direction = linkdensity ? :y : :x,
            inspectable = false,
        )
    end
end


function load_timeseries(component::Symbol = :line)
    if component == :line
        _df = Database.get_columns_from_table(
            "$(cur.ls.val)_Line_Tensions",
            ["Time", "Line$(cur.line.val)_$(cur.elem.val)"],
            "LC_ID = $(cur.lc_id.val) AND Sim_ID = $(cur.sim_id.val)",
        )

        tension_x[] = _df[!, 1]
        tension_y[] = _df[!, 2]
        autolimits!(axis[:timeseries])
        plot_tension_density && autolimits!(axis[:density])
    elseif component == :platform
        isoffset = lowercase(cur.dof.val) == "offset" ? true : false
        cols =
            isoffset ?
            [
                "Time",
                "Platform$(cur.platform.val)_Surge",
                "Platform$(cur.platform.val)_Sway",
                "Platform$(cur.platform.val)_Yaw",
            ] : ["Time", "Platform$(cur.platform.val)_$(cur.dof.val)"]

        platf_motion_df[] = Database.get_columns_from_table(
            "$(cur.ls.val)_Platform_Motion",
            cols,
            "LC_ID = $(cur.lc_id.val) AND Sim_ID = $(cur.sim_id.val)",
        )

    end

    return nothing
end


function set_dash_line_stats()
    toggle_LC = Toggle(dashboard_stats, active = false)
    toggle_lines = Toggle(dashboard_stats, active = false)

    menu_groupby =
        Menu(dashboard_stats, options = ["Load case", "Line", "Simulation"], default = "Simulation")
    menu_plot = Menu(dashboard_stats, options = ["Boxplot", "Violin"], default = "Boxplot")


    axis[:stats] =
        Axis(dashboard_stats[:, 2], xlabel = menu_groupby.selection, ylabel = "Tension  (N)")

    dashboard_stats[1, 1] = vgrid!(
        Label(dashboard_stats, "Load case(s):", tellwidth = false, halign = :left),
        hgrid!(
            toggle_LC,
            Label(dashboard_stats, @lift($(toggle_LC.active) ? "All" : "Current")),
            tellwidth = false,
            halign = :left,
        ),
        Label(dashboard_stats, "Line(s):", tellwidth = false, halign = :left),
        hgrid!(
            toggle_lines,
            Label(dashboard_stats, @lift($(toggle_lines.active) ? "All" : "Current")),
            tellwidth = false,
            halign = :left,
        ),
        Label(dashboard_stats, "Group by:", tellwidth = false, halign = :left),
        menu_groupby,
        Label(dashboard_stats, "Plot type:", tellwidth = false, halign = :left),
        menu_plot,
        tellheight = false,
        width = 150,
        halign = :left,
    )

    btn_update_plot = Button(
        dashboard_stats[2, 1],
        label = "Update",
        buttoncolor = :lightgrey,
        buttoncolor_hover = :lightskyblue1,
    )
    on(btn_update_plot.clicks) do s
        update_stats_plot!(
            axis[:stats],
            toggle_LC.active.val,
            toggle_lines.active.val,
            menu_groupby.selection.val,
            menu_plot.selection.val,
        )
    end

    return nothing

end # set_dashboard()




function search_offset_plot()
    for i in 1:length(menu_motion)
        menu_motion[i].selection[] === "Offset" && return i
    end

    return 0
end

function load_data_of_line(ls, lc, sim, line, time)
    data = Database.get_line_tension(ls, lc, sim, line)
    return [time Array(data)], vcat("Time (s)", names(data) .* " (N)")
end



function set_cur_time_line(slider::Slider)
    global s_ = @lift(string($(slider.value)))
    vlines!(axis[:timeseries], slider.value, color = :red)

    tb = Textbox(
        dashboard_timeseries[9, 1],
        placeholder = "Time",
        width = 100,
        validator = Float64,
        displayed_string = s_,
    )
    on(tb.stored_string) do str
        Channel() do channel
            set_close_to!(slider, parse(Float64, str))
        end
    end

    return nothing
end


function update_stats_plot!(
    ax::Axis,
    all_lc::Bool,
    all_lines::Bool,
    group_by::String,
    plot_type::String,
)
    plot_func = plot_type == "Boxplot" ? boxplot! : violin!
    if plot_type == "Boxplot"
        plot_func = boxplot!
        attributes = (; show_median = true, show_outliers = true, show_notch = true)
    else
        plot_func = violin!
        attributes = (; show_median = true)
    end
    lc_to_plot =
        all_lc ? Database.get_load_cases_from_limit_state(cur.ls.val; col = :LC_ID) : cur.lc_id.val

    clear_axis!(ax)

    xs = Int[] # data of x-axis 
    ys = Float64[]
    for lc_id in lc_to_plot
        lines_to_plot = all_lines ? Database.get_lines_for_lc(cur.ls.val, lc_id) : cur.line.val
        for line_id in lines_to_plot
            for sim_id in Database.get_all_sim(cur.ls.val, lc_id; get_id = true)
                ys_ = Database.get_tension_of_line_element(cur.ls.val, lc_id, sim_id, line_id)
                append!(ys, ys_)

                groupby_ = group_by == "Line" ? line_id : group_by == "Simulation" ? sim_id : lc_id
                append!(xs, fill(groupby_, length(ys_)))

            end
        end
    end
    plot_func(ax, xs, ys)

    return nothing
end

clear_axis!(ax::Axis) = empty!(ax.scene)

show_dashboard(dash::Symbol) =
    if dash == :timeseries
        display(GLMakie.Screen(), dashboard_timeseries)
    elseif dash == :stats
        display(GLMakie.Screen(), dashboard_stats)
    elseif dash == :platf_motion
        display(GLMakie.Screen(), dashboard_platf_motion)
    end

end # module
