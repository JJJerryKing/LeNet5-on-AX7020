#include <string.h>
#include "lwip/tcp.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "ethernet.h"

#define IMAGE_DDR_BASE  0x10000000U
#define IMAGE_HDR_SIZE  16U
#define IMAGE_MAX_WIDTH 1920U
#define IMAGE_MAX_HEIGHT 1080U
#define TCP_PORT        6001U

/* PC sends RGB8 + u32 LE width/height + RGB888; waits for one class byte. */
int frame_ready;
static struct tcp_pcb *client;
static u8 header[12];
static u32 rx_count;
static u32 frame_bytes;

static u32 read_le32(const u8 *data)
{
    return (u32)data[0] | ((u32)data[1] << 8) |
           ((u32)data[2] << 16) | ((u32)data[3] << 24);
}

static void recv_error(void *arg, err_t err)
{
    (void)arg;
    (void)err;
    client = NULL;
    rx_count = 0;
    frame_bytes = 0;
    /* Keep a completed frame locked until main finishes using it. */
}

static err_t recv_callback(void *arg, struct tcp_pcb *pcb,
                           struct pbuf *p, err_t err)
{
    struct pbuf *part;
    const u8 *data;
    u16_t remaining;
    u16_t count;
    u32 width;
    u32 height;

    (void)arg;
    if (p == NULL) {
        tcp_recv(pcb, NULL);
        tcp_err(pcb, NULL);
        recv_error(NULL, ERR_OK);
        if (tcp_close(pcb) != ERR_OK) {
            tcp_abort(pcb);
            return ERR_ABRT;
        }
        return ERR_OK;
    }
    if (err != ERR_OK || frame_ready)
        goto abort;

    for (part = p; part != NULL; part = part->next) {
        data = part->payload;
        remaining = part->len;
        while (remaining != 0U) {
            if (frame_ready)
                goto abort;
            if (rx_count < sizeof(header)) {
                count = sizeof(header) - rx_count;
                if (count > remaining)
                    count = remaining;
                memcpy(header + rx_count, data, count);
                rx_count += count;
                data += count;
                remaining -= count;
                if (rx_count != sizeof(header))
                    continue;

                width = read_le32(header + 4);
                height = read_le32(header + 8);
                if (memcmp(header, "RGB8", 4) != 0 ||
                    width == 0U || width > IMAGE_MAX_WIDTH ||
                    height == 0U || height > IMAGE_MAX_HEIGHT)
                    goto abort;

                frame_bytes = width * height * 3U;
                Xil_Out32(IMAGE_DDR_BASE, width);
                Xil_Out32(IMAGE_DDR_BASE + 4U, height);
                Xil_Out32(IMAGE_DDR_BASE + 8U, 0U);
                Xil_Out32(IMAGE_DDR_BASE + 12U, 0U);
            } else {
                count = remaining;
                if (count > frame_bytes + sizeof(header) - rx_count)
                    count = frame_bytes + sizeof(header) - rx_count;
                memcpy((void *)(UINTPTR)(IMAGE_DDR_BASE + IMAGE_HDR_SIZE +
                       rx_count - sizeof(header)), data, count);
                rx_count += count;
                data += count;
                remaining -= count;
                if (rx_count == sizeof(header) + frame_bytes) {
                    /* PL HP0 reads DDR without snooping the PS cache. */
                    Xil_DCacheFlushRange(IMAGE_DDR_BASE,
                                        IMAGE_HDR_SIZE + frame_bytes);
                    frame_ready = 1;
                }
            }
        }
    }
    tcp_recved(pcb, p->tot_len);
    pbuf_free(p);
    return ERR_OK;

abort:
    pbuf_free(p);
    tcp_abort(pcb);
    return ERR_ABRT;
}

static err_t accept_callback(void *arg, struct tcp_pcb *pcb, err_t err)
{
    (void)arg;
    if (err != ERR_OK || client != NULL || frame_ready) {
        tcp_abort(pcb);
        return ERR_ABRT;
    }
    client = pcb;
    rx_count = 0;
    frame_bytes = 0;
    tcp_recv(pcb, recv_callback);
    tcp_err(pcb, recv_error);
    return ERR_OK;
}

int ethernet_init(void)
{
    struct tcp_pcb *pcb = tcp_new();
    struct tcp_pcb *listener;

    if (pcb == NULL)
        return -1;
    if (tcp_bind(pcb, IP_ADDR_ANY, TCP_PORT) != ERR_OK) {
        tcp_abort(pcb);
        return -1;
    }
    listener = tcp_listen(pcb);
    if (listener == NULL) {
        tcp_abort(pcb);
        return -1;
    }
    tcp_accept(listener, accept_callback);
    return 0;
}

int ethernet_reply(u8 result)
{
    if (client != NULL) {
        if (tcp_write(client, &result, 1, TCP_WRITE_FLAG_COPY) != ERR_OK)
            return 0;
        tcp_output(client);
    }
    rx_count = 0;
    frame_bytes = 0;
    frame_ready = 0;
    return 1;
}
