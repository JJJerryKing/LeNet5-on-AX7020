#include "xparameters.h"
#include "xgpio.h"
#include "xil_io.h"
#include "xstatus.h"
#include "xuartps.h"

#define UART_BAUD_RATE          115200U

#define CTRL_START_CHANNEL      1U
#define CTRL_READY_CHANNEL      2U
#define STATUS_RESULT_CHANNEL   1U
#define STATUS_FLAG_CHANNEL     2U

#define RESULT_VALID_MASK       0x01U
#define INPUT_READY_MASK        0x02U
#define RESULT_MASK             0x3FFU

#define IMAGE_PIXEL_COUNT       784U
#define IMAGE_BRAM_BASE         XPAR_AXI_BRAM_CTRL_IMAGE_S_AXI_BASEADDR

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
     * channel 1 = I_data_valid/start, channel 2 = O_data_ready/ack.
     */
    Status = XGpio_Initialize(&GpioCtrl, XPAR_AXI_GPIO_CTRL_DEVICE_ID);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    XGpio_SetDataDirection(&GpioCtrl, CTRL_START_CHANNEL, 0x0U);
    XGpio_SetDataDirection(&GpioCtrl, CTRL_READY_CHANNEL, 0x0U);
    XGpio_DiscreteWrite(&GpioCtrl, CTRL_START_CHANNEL, 0x0U);
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

static void ConfigureImageBram(void)
{
    u32 PixelIndex;

    /* Clear the 28x28 image area. One pixel occupies one 32-bit BRAM word. */
    for (PixelIndex = 0U; PixelIndex < IMAGE_PIXEL_COUNT; ++PixelIndex) {
        Xil_Out32(IMAGE_BRAM_BASE + PixelIndex * sizeof(u32), 0U);
    }
}

static void ReceiveImageToBram(void)
{
    u32 PixelIndex;
    u8 Pixel;

    /* Receive exactly 784 raw grayscale bytes and store one per BRAM word. */
    for (PixelIndex = 0U; PixelIndex < IMAGE_PIXEL_COUNT; ++PixelIndex) {
        Pixel = XUartPs_RecvByte(Uart.Config.BaseAddress);
        Xil_Out32(
            IMAGE_BRAM_BASE + PixelIndex * sizeof(u32),
            (u32)Pixel
        );
    }
}

static void PulseControl(u32 Channel)
{
    u32 Flags;

    XGpio_DiscreteWrite(&GpioCtrl, Channel, 0x01U);

    /* Hold start high until image_reader accepts it and ready goes low. */
    if (Channel == CTRL_START_CHANNEL) {
        do {
            Flags = XGpio_DiscreteRead(
                &GpioStatus,
                STATUS_FLAG_CHANNEL
            );
        } while ((Flags & INPUT_READY_MASK) != 0U);
    }

    XGpio_DiscreteWrite(&GpioCtrl, Channel, 0x00U);
}

static u8 RunPlInference(void)
{
    u32 Flags;
    u32 Result;

    /* Wait until PL is idle and ready to accept a new image start. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & INPUT_READY_MASK) == 0U);

    PulseControl(CTRL_START_CHANNEL);

    /* Wait until PL presents a valid classification result. */
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & RESULT_VALID_MASK) == 0U);

    Result = XGpio_DiscreteRead(&GpioStatus, STATUS_RESULT_CHANNEL);
    Result &= RESULT_MASK;

    /* Acknowledge the result, then wait until PL removes valid. */
    PulseControl(CTRL_READY_CHANNEL);
    do {
        Flags = XGpio_DiscreteRead(&GpioStatus, STATUS_FLAG_CHANNEL);
    } while ((Flags & RESULT_VALID_MASK) != 0U);

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


    ConfigureImageBram();

    while (1) {
        ReceiveImageToBram();

        /* I: all 784 image bytes were received and written into BRAM. */
        XUartPs_SendByte(Uart.Config.BaseAddress, 'I');

        Result = RunPlInference();
        XUartPs_SendByte(Uart.Config.BaseAddress, Result);
        XUartPs_SendByte(Uart.Config.BaseAddress, 'a');
    }

    return 0;
}
