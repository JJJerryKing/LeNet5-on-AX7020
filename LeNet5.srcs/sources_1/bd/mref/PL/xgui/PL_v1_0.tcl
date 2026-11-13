# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CHANNEL_I_1" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CHANNEL_O_1" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CHANNEL_O_2" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CHANNEL_O_3" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CHANNEL_O_4" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CHANNEL_O_5" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CONV_CORE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LINE_LEN" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LINE_NUMS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PADDING" -parent ${Page_0}
  ipgui::add_param $IPINST -name "QUANT_SIZE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "WEIGHT_SIZE" -parent ${Page_0}


}

proc update_PARAM_VALUE.CHANNEL_I_1 { PARAM_VALUE.CHANNEL_I_1 } {
	# Procedure called to update CHANNEL_I_1 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNEL_I_1 { PARAM_VALUE.CHANNEL_I_1 } {
	# Procedure called to validate CHANNEL_I_1
	return true
}

proc update_PARAM_VALUE.CHANNEL_O_1 { PARAM_VALUE.CHANNEL_O_1 } {
	# Procedure called to update CHANNEL_O_1 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNEL_O_1 { PARAM_VALUE.CHANNEL_O_1 } {
	# Procedure called to validate CHANNEL_O_1
	return true
}

proc update_PARAM_VALUE.CHANNEL_O_2 { PARAM_VALUE.CHANNEL_O_2 } {
	# Procedure called to update CHANNEL_O_2 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNEL_O_2 { PARAM_VALUE.CHANNEL_O_2 } {
	# Procedure called to validate CHANNEL_O_2
	return true
}

proc update_PARAM_VALUE.CHANNEL_O_3 { PARAM_VALUE.CHANNEL_O_3 } {
	# Procedure called to update CHANNEL_O_3 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNEL_O_3 { PARAM_VALUE.CHANNEL_O_3 } {
	# Procedure called to validate CHANNEL_O_3
	return true
}

proc update_PARAM_VALUE.CHANNEL_O_4 { PARAM_VALUE.CHANNEL_O_4 } {
	# Procedure called to update CHANNEL_O_4 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNEL_O_4 { PARAM_VALUE.CHANNEL_O_4 } {
	# Procedure called to validate CHANNEL_O_4
	return true
}

proc update_PARAM_VALUE.CHANNEL_O_5 { PARAM_VALUE.CHANNEL_O_5 } {
	# Procedure called to update CHANNEL_O_5 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNEL_O_5 { PARAM_VALUE.CHANNEL_O_5 } {
	# Procedure called to validate CHANNEL_O_5
	return true
}

proc update_PARAM_VALUE.CONV_CORE { PARAM_VALUE.CONV_CORE } {
	# Procedure called to update CONV_CORE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CONV_CORE { PARAM_VALUE.CONV_CORE } {
	# Procedure called to validate CONV_CORE
	return true
}

proc update_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to update DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to validate DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.LINE_LEN { PARAM_VALUE.LINE_LEN } {
	# Procedure called to update LINE_LEN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LINE_LEN { PARAM_VALUE.LINE_LEN } {
	# Procedure called to validate LINE_LEN
	return true
}

proc update_PARAM_VALUE.LINE_NUMS { PARAM_VALUE.LINE_NUMS } {
	# Procedure called to update LINE_NUMS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LINE_NUMS { PARAM_VALUE.LINE_NUMS } {
	# Procedure called to validate LINE_NUMS
	return true
}

proc update_PARAM_VALUE.PADDING { PARAM_VALUE.PADDING } {
	# Procedure called to update PADDING when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PADDING { PARAM_VALUE.PADDING } {
	# Procedure called to validate PADDING
	return true
}

proc update_PARAM_VALUE.QUANT_SIZE { PARAM_VALUE.QUANT_SIZE } {
	# Procedure called to update QUANT_SIZE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.QUANT_SIZE { PARAM_VALUE.QUANT_SIZE } {
	# Procedure called to validate QUANT_SIZE
	return true
}

proc update_PARAM_VALUE.WEIGHT_SIZE { PARAM_VALUE.WEIGHT_SIZE } {
	# Procedure called to update WEIGHT_SIZE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.WEIGHT_SIZE { PARAM_VALUE.WEIGHT_SIZE } {
	# Procedure called to validate WEIGHT_SIZE
	return true
}


proc update_MODELPARAM_VALUE.DATA_WIDTH { MODELPARAM_VALUE.DATA_WIDTH PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH}] ${MODELPARAM_VALUE.DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.QUANT_SIZE { MODELPARAM_VALUE.QUANT_SIZE PARAM_VALUE.QUANT_SIZE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.QUANT_SIZE}] ${MODELPARAM_VALUE.QUANT_SIZE}
}

proc update_MODELPARAM_VALUE.WEIGHT_SIZE { MODELPARAM_VALUE.WEIGHT_SIZE PARAM_VALUE.WEIGHT_SIZE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.WEIGHT_SIZE}] ${MODELPARAM_VALUE.WEIGHT_SIZE}
}

proc update_MODELPARAM_VALUE.LINE_LEN { MODELPARAM_VALUE.LINE_LEN PARAM_VALUE.LINE_LEN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LINE_LEN}] ${MODELPARAM_VALUE.LINE_LEN}
}

proc update_MODELPARAM_VALUE.LINE_NUMS { MODELPARAM_VALUE.LINE_NUMS PARAM_VALUE.LINE_NUMS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LINE_NUMS}] ${MODELPARAM_VALUE.LINE_NUMS}
}

proc update_MODELPARAM_VALUE.PADDING { MODELPARAM_VALUE.PADDING PARAM_VALUE.PADDING } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PADDING}] ${MODELPARAM_VALUE.PADDING}
}

proc update_MODELPARAM_VALUE.CONV_CORE { MODELPARAM_VALUE.CONV_CORE PARAM_VALUE.CONV_CORE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CONV_CORE}] ${MODELPARAM_VALUE.CONV_CORE}
}

proc update_MODELPARAM_VALUE.CHANNEL_I_1 { MODELPARAM_VALUE.CHANNEL_I_1 PARAM_VALUE.CHANNEL_I_1 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNEL_I_1}] ${MODELPARAM_VALUE.CHANNEL_I_1}
}

proc update_MODELPARAM_VALUE.CHANNEL_O_1 { MODELPARAM_VALUE.CHANNEL_O_1 PARAM_VALUE.CHANNEL_O_1 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNEL_O_1}] ${MODELPARAM_VALUE.CHANNEL_O_1}
}

proc update_MODELPARAM_VALUE.CHANNEL_O_2 { MODELPARAM_VALUE.CHANNEL_O_2 PARAM_VALUE.CHANNEL_O_2 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNEL_O_2}] ${MODELPARAM_VALUE.CHANNEL_O_2}
}

proc update_MODELPARAM_VALUE.CHANNEL_O_3 { MODELPARAM_VALUE.CHANNEL_O_3 PARAM_VALUE.CHANNEL_O_3 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNEL_O_3}] ${MODELPARAM_VALUE.CHANNEL_O_3}
}

proc update_MODELPARAM_VALUE.CHANNEL_O_4 { MODELPARAM_VALUE.CHANNEL_O_4 PARAM_VALUE.CHANNEL_O_4 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNEL_O_4}] ${MODELPARAM_VALUE.CHANNEL_O_4}
}

proc update_MODELPARAM_VALUE.CHANNEL_O_5 { MODELPARAM_VALUE.CHANNEL_O_5 PARAM_VALUE.CHANNEL_O_5 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNEL_O_5}] ${MODELPARAM_VALUE.CHANNEL_O_5}
}

