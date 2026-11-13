| Device | Slice LUTs | Slice Registers | F7 Muxes | F8 Muxes | Block RAM Tile | DSPs | Bonded IOB | BUFGCTRL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AX7020 (XC7Z020) | 53,200 | 106,400 | 26,600 | 13,300 | 140 | 220 | 125 | 32 |

1.该文件夹下为各基线的utilization报告，基于上一基线的改进内容在对应.v文件的开头注释，
b表格中列出AX7020的资源额度
2.mac_base是未优化的初始版本；先对mac进行了1、2两次优化；

3.line_loader_base1/2/3基于mac_base2进行了三次优化尝试，其中1、2次基本没有改进，第3次改进后满足资源要求

4.image_reader_base1基于image_reader_base源码进行改进，是继line_loader_base3后的改进

5.AverPooling基于AverPoling_base源码改进，是继image_reader_base1后的改进

