set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir keyboard_games.gprj]
set_option -top_module KeyboardGames
set_option -verilog_std v2001
set_option -use_cpu_as_gpio 1
run all
exit
