cd   "D:/eHiWay/eLinx3.0/bin/shell/bin"
set tclFile  "D:/eHiWay/eLinx3.0/bin/shell/bin/run_bitgen.tcl"
set dir "D:/IC_Competition/hdmidemotestpro7qvwuPro(1)_quitareapure(1)/hdmidemotestpro7qvwuPro(1)_quitareapure/hdmidemotestpro7uart_scalefix"
set prj hdmi_demo
set topEntity hdmi_ctrl
set seriesName "eHiChip6"
set deviceName EQ6HL130
set packageName CSG484_H
set SynthName synth_1
set ImpleName imple_1
source $tclFile
run_bitgen $dir $prj $topEntity $seriesName $deviceName $packageName $SynthName $ImpleName
exit 0
