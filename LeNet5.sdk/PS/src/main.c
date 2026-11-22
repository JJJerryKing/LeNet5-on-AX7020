#include "xparameters.h"
#include "xgpio.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xstatus.h"
#include "xuartps.h"
#include "sleep.h"

#define UART_BAUD_RATE          115200U

#define CTRL_START_CHANNEL      1U
#define CTRL_READY_CHANNEL      2U
#define PL_RESET_N_MASK         0x02U
#define STATUS_RESULT_CHANNEL   1U
#define STATUS_FLAG_CHANNEL     2U

#define RESULT_VALID_MASK       0x01U
#define INPUT_READY_MASK        0x02U
#define RESULT_MASK             0x3FFU

#define IMAGE_DDR_BASE          0x10000000U
#define IMAGE_HEADER_BYTES      16U
#define IMAGE_MAX_WIDTH         1920U
#define IMAGE_MAX_HEIGHT        1080U

/*
 * PC -> PS: "RGB8", width (u32 LE), height (u32 LE), then width*height*3
 * raw bytes in R,G,B order, row by row without padding. No ASCII numbers.
 * Send one frame at a time and wait for the complete response before the next.
 * PS -> PC: one raw class-index byte (0..9), without acknowledgement or terminator.
 * The result is sent only after PL has been reset and is ready again.
 * An invalid width/height returns 'E' without starting PL; seek the next RGB8.
 * There is no checksum or receive timeout in this blocking protocol.
 *
 * DDR: width at +0, height at +4, reserved zeros at +8/+12, RGB at +16.
 * IMAGE_DDR_BASE must match PL.DDR_BASE_ADDR and the reserved linker region.
 */

static XUartPs Uart;
static XGpio GpioCtrl;
static XGpio GpioStatus;

static int ConfigureUart(void)
{
    XUartPs_Config *Config;
    XUartPsFormat Format;
    int Status;

    /* Configure PS UART1 as 115200 baud, 8 data bits, no parity, 1 stop. */
    Config = XUartPs_LookupConfig(XPAR_PS7_UART_1_DEVICE_ID);
    if (Config == NULL) {
        return XST_FAILURE;
    }

    Status = XUartPs_CfgInitialize(&Uart, Config, Config->BaseAddress);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    Format.BaudRate = UART_BAUD_RATE;
    Format.DataBits = XUARTPS_FORMAT_8_BITS;
    Format.Parity   = XUARTPS_FORMAT_NO_PARITY;
    Format.StopBits = XUARTPS_FORMAT_1_STOP_BIT;

    Status = XUartPs_SetDataFormat(&Uart, &Format);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    XUartPs_SetOperMode(&Uart, XUARTPS_OPER_MODE_NORMAL);
    return XST_SUCCESS;
}

static int ConfigureControlGpio(void)
{
    int Status;

    /*
     * AXI GPIO control channels are outputs from PS to PL:
     * channel 1 bit 0 = I_data_valid/start, bit 1 = active-low PL reset;
     * keep bit 1 high during idle and processing (0x02 idle, 0x03 start).
     * channel 2 bit 0 = O_data_ready/ack.
     */
    Status = XGpio_Initialize(&GpioCtrl, XPAR_AXI_GPIO_CTRL_DEVICE_ID);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    XGpio_SetDataDirection(&GpioCtrl, CTRL_START_CHANNEL, 0x0U);
    XGpio_SetDataDirection(&GpioCtrl, CTRL_READY_CHANNEL, 0x0U);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, PL_RESET_N_MASK);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_READY_CHANNEL, 0x0U);

    return XST_SUCCESS;
}

static int ConfigureStatusGpio(void)
{
    int Status;

    /*
     * AXI GPIO status channels are inputs from PL to PS:
     * channel 1 = result_q[9:0];
     * channel 2 bit 0 = O_data_valid, bit 1 = I_data_ready.
     */
    Status = XGpio_Initialize(&GpioStatus, XPAR_AXI_GPIO_STATUS_DEVICE_ID);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    XGpio_SetDataDirection(&GpioStatus, STATUS_RESULT_CHANNEL, 0x3FFU);
    XGpio_SetDataDirection(&GpioStatus, STATUS_FLAG_CHANNEL, 0x03U);

    return XST_SUCCESS;
}

static u32 ReceiveUartWord(void)
{
    u32 Value = 0U;
    unsigned int Shift;

    /* Decode a little-endian word independently of the PC's native layout. */
    for (Shift = 0U; Shift < 32U; Shift += 8U) {
        Value |= (u32)XUartPs_RecvByte(Uart.Config.BaseAddress) << Shift;
    }

    return Value;
}

static int ReceiveImageToDdr(void)
{
    static const u8 FrameHeader[] = {'R', 'G', 'B', '8'};
    unsigned int HeaderIndex = 0U;
    u8 Byte;
    u32 Width;
    u32 Height;
    u32 ByteIndex;

    /* Find the frame boundary before interpreting dimensions or pixel data. */
    while (HeaderIndex < sizeof(FrameHeader)) {
        Byte = XUartPs_RecvByte(Uart.Config.BaseAddress);
        if (Byte == FrameHeader[HeaderIndex]) {
            ++HeaderIndex;
        } else {
            HeaderIndex = (Byte == FrameHeader[0]) ? 1U : 0U;
        }
    }

    Width = ReceiveUartWord();
    Height = ReceiveUartWord();
    if (Width == 0U || Width > IMAGE_MAX_WIDTH ||
        Height == 0U || Height > IMAGE_MAX_HEIGHT) {
        return XST_FAILURE;
    }

    /* Valid dimensions bound this transfer to less than the reserved 8 MiB. */
    for (ByteIndex = 0U; ByteIndex < Width * Height * 3U; ++ByteIndex) {
        Xil_Out8(
            IMAGE_DDR_BASE + IMAGE_HEADER_BYTES + ByteIndex,
            XUartPs_RecvByte(Uart.Config.BaseAddress)
        );
    }

    /* Publish the parameters only after the entire RGB payload has arrived. */
    Xil_Out32(IMAGE_DDR_BASE, Width);
    Xil_Out32(IMAGE_DDR_BASE + 4U, Height);
    Xil_Out32(IMAGE_DDR_BASE + 8U, 0U);
    Xil_Out32(IMAGE_DDR_BASE + 12U, 0U);

    /* HP0 does not snoop the PS cache. Flush header and pixels before start. */
    Xil_DCacheFlushRange(
        IMAGE_DDR_BASE,
        IMAGE_HEADER_BYTES + Width * Height * 3U
    );

    return XST_SUCCESS;
}

static void ResetPl(void)
{
    u32 Flags;

    /* Clear both handshakes, then hold channel 1 bit 1 low to reset PL. */
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_READY_CHANNEL, 0x00U);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, PL_RESET_N_MASK);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, 0x00U);
    usleep(10U);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, PL_RESET_N_MASK);

    /* rst_compute releases reset synchronously; wait for clean idle status. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & INPUT_READY_MASK) == 0U ||
             (Flags & RESULT_VALID_MASK) != 0U);
}

static void StartPlProcessing(void)
{
    u32 Flags;

    /* Wait until preprocessing can accept a new frame request. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & INPUT_READY_MASK) == 0U);

    /* Keep reset released while asserting the frame request. */
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, PL_RESET_N_MASK | 0x01U);

    /* Keep valid asserted until preprocessing accepts it and drops ready. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & INPUT_READY_MASK) != 0U);

    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, PL_RESET_N_MASK);
}

static u8 RunPlInference(void)
{
    u32 Flags;
    u32 Result;

    StartPlProcessing();

    /* Wait until PL presents a valid classification result. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & RESULT_VALID_MASK) == 0U);

    Result = XGpio_DiscreteRead(&GpioStatus, STATUS_RESULT_CHANNEL);
    Result &= RESULT_MASK;

    /* Copy first, then hold ready until the result handshake is complete. */
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_READY_CHANNEL, 0x01U);
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & RESULT_VALID_MASK) != 0U);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_READY_CHANNEL, 0x00U);

    /* Wait for preprocessing to finish and drain DDR reads before resetting. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & INPUT_READY_MASK) == 0U);
    ResetPl();

    /* argmax returns the binary class index 0..9, not a one-hot vector. */
    return (u8)Result;
}

int main(void)
{
    int Status;
    u8 Result;

    Status = ConfigureUart();
    if (Status != XST_SUCCESS) {
        return Status;
    }

    Status = ConfigureControlGpio();
    if (Status != XST_SUCCESS) {
        return Status;
    }

    Status = ConfigureStatusGpio();
    if (Status != XST_SUCCESS) {
        return Status;
    }

    ResetPl();

    while (1) {
        Status = ReceiveImageToDdr();
        if (Status != XST_SUCCESS) {
            XUartPs_SendByte(Uart.Config.BaseAddress, 'E');
            continue;
        }

        Result = RunPlInference();
        XUartPs_SendByte(Uart.Config.BaseAddress, Result);
    }

    return 0;
}
