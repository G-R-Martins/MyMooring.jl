include("MyMooring.jl");

using .MyMooring 

MyMooring.main(
    open_ui=true, 
    # input_file="./input/test_turb", 
    # input_file="./input/cat1000m_turb", 
    input_file="C:/Users/Guilherme/repos/MyMooring.jl/input/case_turb", 
    input_dir="C:/Users/Guilherme/repos/MyMooring.jl/input/simulations/TurbEval", 
    # input_file="./input/teste", 
    # input_dir="./input/s  imulations/ULS/T50y", 
    # input_file="./input/cat1000m_als", 
    # input_dir="./input/simulations/ALS", 
    # input_dir="G:/My Drive/Mestrado/FOWT/Estudo-Linhas/catenaria_1000m", 
    # input_dir="G:/My Drive/Mestrado/FOWT/DadosAmbientais/Turbulencia", 
    execute=true
)

showall(MyMooring.MyMooringUI.glade["window_main"])
MyMooring.LogOptions.update_ui_status(task_done)
push!(MyMooring.LogOptions.log_ui.box, GtkImage("", icon_name="gtk-yes", storage_type=Gtk.GtkImageType.GTK_IMAGE_ICON_NAME))


using Gtk, SQLite, DataFrames
using GLMakie