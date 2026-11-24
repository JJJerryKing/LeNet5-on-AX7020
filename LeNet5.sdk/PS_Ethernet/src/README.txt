LeNet TCP server (lwIP raw API, standalone Zynq)
================================================

Board: 10.4.162.19:6001, mask 255.255.255.0, gateway 10.4.162.254.
MAC: 00:0a:35:00:01:02. DHCP is disabled in PS_Ethernet_bsp/system.mss.

PC -> PS: "RGB8", width (u32 little-endian), height (u32 little-endian),
then width*height*3 RGB888 bytes, row-major without padding.
Dimensions: 1..1920 by 1..1080.
PS -> PC: one binary class-index byte (0..9).
Use one persistent TCP connection; wait for the result before sending another
frame. Invalid headers/dimensions, premature next frames and extra clients
close that connection. Reconnection starts at a new frame header.

ethernet.c owns TCP setup, receive parsing and result transmission.
main.c runs FRAME -> START -> START_ACK -> RESULT -> RESULT_ACK.
O_data_valid connects directly to IRQ_F2P[0], rising-edge GIC interrupt 61.
ready stays high until valid falls; preprocessing must also be idle before
the PL reset and next frame. Network input and TCP timers continue while
waiting for frames/results; START_ACK promptly completes the start handshake.

DDR 0x10000000..0x107fffff is reserved by lscript.ld. Width/height occupy the
first two u32 words, the next two words are zero, and RGB888 starts at +16.
The receive callback flushes the complete image before publishing frame_ready.

Refresh the SDK project after replacing echo.c with ethernet.c, regenerate
PS_Ethernet_bsp from system.mss, then build against the current exported
hardware platform/bitstream containing the IRQ_F2P connection.
No receive or PL timeout is implemented.
