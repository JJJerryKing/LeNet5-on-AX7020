#ifndef ETHERNET_H
#define ETHERNET_H

#include "xtime_l.h"

extern int frame_ready;
extern XTime rx_start, rx_end;

int ethernet_init(void);
int ethernet_reply(u8 result);

#endif
