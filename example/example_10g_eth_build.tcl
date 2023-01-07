# Vivado build script

global output_dir
global src_dir
global build_dir
global ip_dir
global flatten_hierarchy

set fpga_part xczu49dr-ffvf1760-2-e
set project_name example_10g_eth
set output_dir ../build/out
set src_dir ../

set build_dir ../build
set ip_dir ../../src/ip/gen
set core_src_dir ../../src
set core_src_include_dir ../../src/hdl/include

set flatten_hierarchy none

proc init {} {
    
    set_part $::fpga_part
    set_property target_language Verilog [current_project]

    set_property source_mgmt_mode All [current_project]
}

# todo better way to organise sources
proc add_sources {} {

    read_verilog [glob $::src_dir/hdl/*.sv] -sv
    read_verilog [glob $::core_src_dir/hdl/**/*.svh] -sv
    read_verilog [glob $::core_src_dir/hdl/*.sv] -sv
    read_verilog [glob $::core_src_dir/hdl/**/*.sv] -sv

    read_ip [glob $::ip_dir/**/*.xci]

    read_xdc [glob $::src_dir/constraints/*.xdc]
}

# todo out-of-context runs?
proc gen_ip {} {
    generate_target all [get_ips]
}

proc synth {} {
    synth_design -top $::project_name -flatten_hierarchy $::flatten_hierarchy 
    # -include_dirs $::core_src_include_dir
    write_checkpoint -force $::output_dir/post_synth.dcp
    report_timing_summary -file $::output_dir/post_synth_timing_summary.rpt
    report_utilization -file $::output_dir/post_synth_util.rpt
}

proc impl {} {
    opt_design
    place_design
    report_clock_utilization -file $::output_dir/clock_util.rpt

    #get timing violations and run optimizations if needed
    if {[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] < 0} {
    puts "Found setup timing violations => running physical optimization"
    phys_opt_design
    }
    write_checkpoint -force $::output_dir/post_place.dcp
    report_utilization -file $::output_dir/post_place_util.rpt
    report_timing_summary -file $::output_dir/post_place_timing_summary.rpt

    #Route design and generate bitstream
    route_design -directive Explore
    write_checkpoint -force $::output_dir/post_route.dcp
    report_route_status -file $::output_dir/post_route_status.rpt
    report_timing_summary -file $::output_dir/post_route_timing_summary.rpt
    report_power -file $::output_dir/post_route_power.rpt
    report_drc -file $::output_dir/post_imp_drc.rpt
}

proc output {} {
    write_verilog -force $::output_dir/cpu_impl_netlist.v -mode timesim -sdf_anno true
    write_debug_probes -force $::output_dir/$::project_name.ltx
    
    write_bitstream -force $::output_dir/$::project_name
    write_bitstream -bin_file -force $::output_dir/$::project_name
    exec cp $::output_dir/$::project_name.bin $::nfs_dir/$::project_name.bit.bin

    
}

proc write_xsa {} {
    open_checkpoint $::output_dir/post_route.dcp
    write_hw_platform -force -include_bit -fixed $::output_dir/$::project_name.xsa
    
}

proc all {} {
    init
    add_sources
    gen_bd
    finish_bd
    synth
    impl
    output
    write_xsa
}

proc start_synth {} {
    init
    add_sources
    gen_bd
    finish_bd
    synth
}

proc impl_out {} {
    impl
    output
    write_xsa
}
