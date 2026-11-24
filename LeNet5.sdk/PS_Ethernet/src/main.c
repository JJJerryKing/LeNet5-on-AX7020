/******************************************************************************
*
* Copyright (C) 2009 - 2014 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* Use of the Software is limited solely to applications:
* (a) running on a Xilinx device, or
* (b) that interact with a Xilinx device through a bus or interconnect.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
* OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* Except as contained in this notice, the name of the Xilinx shall not be used
* in advertising or otherwise to promote the sale, use or other dealings in
* this Software without prior written authorization from Xilinx.
*
******************************************************************************/

#include "xparameters.h"
#include "xparameters_ps.h"
#include "xgpio.h"
#include "xscugic.h"
#include "sleep.h"
#include "lwip/init.h"
#include "lwip/tcp.h"
#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"
#include "xil_printf.h"
#include "ethernet.h"

#define CTRL_START_CHANNEL    1U
#define CTRL_READY_CHANNEL    2U
#define STATUS_RESULT_CHANNEL 1U
#define STATUS_FLAG_CHANNEL   2U
#define PL_RESET_N_MASK       0x02U
#define RESULT_VALID_MASK     0x01U
#define INPUT_READY_MASK      0x02U

enum app_state { FRAME, START, START_ACK, RESULT, RESULT_ACK };

void tcp_fasttmr(void);
void tcp_slowtmr(void);
extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;
static struct netif server_netif;
/* Used by the template's Ethernet RX watchdog. */
struct netif *echo_netif = &server_netif;
static XGpio gpio_ctrl;
static XGpio gpio_status;
static volatile int result_done;

static void result_isr(void *arg)
{
    (void)arg;
    result_done = 1;
}

static void reset_pl(void)
{
    XGpio_DiscreteWrite(&gpio_ctrl, CTRL_READY_CHANNEL, 0U);
    XGpio_DiscreteWrite(&gpio_ctrl, CTRL_START_CHANNEL, 0U);
    usleep(10U);
    XGpio_DiscreteWrite(&gpio_ctrl, CTRL_START_CHANNEL, PL_RESET_N_MASK);
}

static int init_pl(void)
{
    if (XGpio_Initialize(&gpio_ctrl, XPAR_AXI_GPIO_CTRL_DEVICE_ID) != XST_SUCCESS ||
        XGpio_Initialize(&gpio_status, XPAR_AXI_GPIO_STATUS_DEVICE_ID) != XST_SUCCESS)
        return -1;

    XGpio_SetDataDirection(&gpio_ctrl, CTRL_START_CHANNEL, 0U);
    XGpio_SetDataDirection(&gpio_ctrl, CTRL_READY_CHANNEL, 0U);
    XGpio_SetDataDirection(&gpio_status, STATUS_RESULT_CHANNEL, 0x3FFU);
    XGpio_SetDataDirection(&gpio_status, STATUS_FLAG_CHANNEL, 0x03U);
    reset_pl();

    /* O_data_valid connects directly to IRQ_F2P[0] (GIC ID 61). */
    XScuGic_RegisterHandler(XPAR_SCUGIC_0_CPU_BASEADDR, XPS_FPGA0_INT_ID,
                           result_isr, NULL);
    XScuGic_SetPriTrigTypeByDistAddr(XPAR_SCUGIC_0_DIST_BASEADDR,
                                   XPS_FPGA0_INT_ID, 0xA0U, 0x03U);
    XScuGic_WriteReg(XPAR_SCUGIC_0_DIST_BASEADDR,
                    XSCUGIC_PENDING_CLR_OFFSET + (XPS_FPGA0_INT_ID / 32U) * 4U,
                    1U << (XPS_FPGA0_INT_ID % 32U));
    XScuGic_EnableIntr(XPAR_SCUGIC_0_DIST_BASEADDR, XPS_FPGA0_INT_ID);
    return 0;
}

int main(void)
{
    struct ip_addr ipaddr, netmask, gw;
    unsigned char mac_addr[] = {0x00, 0x0A, 0x35, 0x00, 0x01, 0x02};
    enum app_state state = FRAME;
    u32 flags;
    u8 result = 0;

    init_platform();
    lwip_init();
    IP4_ADDR(&ipaddr, 10, 4, 162, 19);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 10, 4, 162, 254);
    if (xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac_addr,
                  PLATFORM_EMAC_BASEADDR) == NULL)
        return -1;
    netif_set_default(echo_netif);
    netif_set_up(echo_netif);
    if (init_pl() != 0 || ethernet_init() != 0)
        return -1;
    platform_enable_interrupts();
    xil_printf("LeNet TCP server: 10.4.162.19:6001\r\n");

    while (1) {
        /* Observe start acceptance promptly before ready can rise again. */
        if (state != START_ACK) {
            if (TcpFastTmrFlag) {
                TcpFastTmrFlag = 0;
                tcp_fasttmr();
            }
            if (TcpSlowTmrFlag) {
                TcpSlowTmrFlag = 0;
                tcp_slowtmr();
            }
            xemacif_input(echo_netif);
        }
        flags = XGpio_DiscreteRead(&gpio_status, STATUS_FLAG_CHANNEL);

        switch (state) {
        case FRAME:
            if (frame_ready)
                state = START;
            break;
        case START:
            if ((flags & (INPUT_READY_MASK | RESULT_VALID_MASK)) == INPUT_READY_MASK) {
                result_done = 0;
                XGpio_DiscreteWrite(&gpio_ctrl, CTRL_START_CHANNEL,
                                    PL_RESET_N_MASK | 0x01U);
                state = START_ACK;
            }
            break;
        case START_ACK:
            if ((flags & INPUT_READY_MASK) == 0U) {
                XGpio_DiscreteWrite(&gpio_ctrl, CTRL_START_CHANNEL, PL_RESET_N_MASK);
                state = RESULT;
            }
            break;
        case RESULT:
            if (result_done) {
                result = (u8)XGpio_DiscreteRead(&gpio_status, STATUS_RESULT_CHANNEL);
                XGpio_DiscreteWrite(&gpio_ctrl, CTRL_READY_CHANNEL, 1U);
                state = RESULT_ACK;
            }
            break;
        case RESULT_ACK:
            if ((flags & RESULT_VALID_MASK) == 0U) {
                XGpio_DiscreteWrite(&gpio_ctrl, CTRL_READY_CHANNEL, 0U);
                /* Drain preprocessing DDR reads before resetting/reusing DDR. */
                if ((flags & INPUT_READY_MASK) != 0U && ethernet_reply(result)) {
                    reset_pl();
                    state = FRAME;
                }
            }
            break;
        }
    }
}
