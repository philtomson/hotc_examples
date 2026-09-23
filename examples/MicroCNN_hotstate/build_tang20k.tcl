# Tang Nano 20K (GW2AR-18C) build of MicroCNN_hotstate with Gowin's own
# toolchain, run headless through gw_sh:
#
#   gw_sh build_tang20k.tcl        (or: make -f Makefile.synth_tang20k_gowin pack)
#
# Output: build_tang20k/MicroCNN_tang20k/impl/pnr/MicroCNN_tang20k.fs
#
# Why Gowin and not the open-source flow on this board: the open-source flow
# builds this design for the 20K and meets timing, but the bitstream
# misclassifies. The fault is in open-source place-and-route/packing for
# GW2A-18C, not in synthesis. The Tang Primer 25K build
# (Makefile.synth_primer25k) is the open-source one.
#
# create_project chdir's into the project directory, so every path below is
# absolute, derived from this script's own location.

set HERE  [file dirname [file normalize [info script]]]
set IP    [file normalize "$HERE/../../IP"]
set LIB   "$HERE/lib"
set BUILD "$HERE/build_tang20k"

file mkdir $BUILD
create_project -name MicroCNN_tang20k -dir $BUILD -pn GW2AR-LV18QN88C8/I7 -device_version C -force

# The ROM modules' $readmemh("hardware_roms/...") and the template's
# "./main_controller_*.mem" are relative paths. Make them resolve from the
# project directory as well as from the sources' own directories.
file delete -force hardware_roms
file link -symbolic hardware_roms "$HERE/hardware_roms"
foreach m {smdata vardata timdata switchdata} {
    file delete -force main_controller_$m.mem
    file link -symbolic main_controller_$m.mem "$HERE/main_controller_$m.mem"
}

add_file \
  $LIB/gw2a/gowin_mult.v \
  $LIB/gw2a/dsp_multalu_accum.v \
  $LIB/gw2a/conv2_input_ram.v \
  $LIB/gw2a/gowin_sdpb_fc1.v \
  $LIB/gw2a/gowin_sdpb_fc2.v \
  $LIB/gw2a/gowin_rpll.v \
  $IP/hotstate.sv \
  $IP/microcode.sv \
  $IP/control.sv \
  $IP/next_address.sv \
  $IP/variable.sv \
  $IP/switch.sv \
  $IP/stack.sv \
  $IP/timer.sv \
  $HERE/main_controller_template.v \
  $LIB/spatial_3x3_mac_gowin.sv \
  $LIB/ws_conv_core_gowin.sv \
  $LIB/tdm_npu_router.sv \
  $LIB/unified_line_buffer.sv \
  $LIB/maxpool2x2.sv \
  $LIB/argmax_layer.sv \
  $LIB/conv1_param_rom.sv \
  $LIB/conv2_param_rom.sv \
  $LIB/fc1_param_rom.sv \
  $LIB/fc2_param_rom.sv \
  $LIB/fc1_buffer_ram.sv \
  $LIB/fc2_buffer_ram.sv \
  $LIB/fc1_reduction_tree.sv \
  $LIB/fc2_reduction_tree.sv \
  $LIB/fc_npu_array_gowin.sv \
  $LIB/fc_tdm_router.sv \
  $LIB/tdm_fc_router.sv \
  $LIB/img_ram.sv \
  $LIB/conv1_to_conv2_router.sv \
  $LIB/conv2_line_buffer_wrapper.sv \
  $LIB/single_channel_line_buffer.sv \
  $LIB/uart_rx.sv \
  $LIB/uart_tx.sv \
  $LIB/soc_controller.sv \
  $LIB/reset_sync.sv \
  $HERE/npu_top_hotstate.sv \
  $HERE/top_hotstate.sv

add_file $HERE/tang20k.cst

set_option -top_module top
set_option -verilog_std sysv2017
set_option -synthesis_tool gowinsynthesis
# 30 MHz rPLL output, with ~10% margin
set_option -global_freq 33

run all
