#ifndef ETHERNET_H
#define ETHERNET_H

#include "xil_types.h"

extern int frame_ready;

int ethernet_init(void);
int ethernet_reply(u8 result);

#endif
