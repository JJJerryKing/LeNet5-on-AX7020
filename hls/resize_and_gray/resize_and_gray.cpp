/*
 * resize_and_gray：从 DDR 读取 RGB888，转换为 28x28 灰度图并逐行输出。
 *
 * 数据路径：
 * DDR 参数头/RGB888 -> 灰度转换 -> hls::Resize -> 按行打包 -> LeNet。
 * PS 在启动前写完参数和像素；处理期间保持该内存块内容不变。
 */

// ============================================================================
// 1. HLS 基础类型与视频处理库
// ============================================================================
#include <ap_int.h>  // 仅用于整行 368 位 AXIS 数据，普通数值使用 C++ 基本类型。
#include <hls_stream.h>
#include <hls_video.h>

namespace preprocessing {

// ============================================================================
// 2. 固定格式与输出规格：输入 RGB888，输出 28 行、每行 28 个 13 位像素
// ============================================================================
static const int RGB_CHANNELS = 3;
static const int QUANT_SIZE   = 13;
static const int LINE_LEN     = 28;
// 输入最大尺寸沿用参考代码；运行时宽高由 DDR 参数头提供。
static const int IMG_MAX_ROWS = 1080;
static const int IMG_MAX_COLS = 1920;

// 整行位宽直接由像素数和量化位宽计算，并向上对齐到完整字节。
// 标准 C++ 整数无法容纳这一整行，因此仅在此处保留 ap_uint。
typedef ap_uint<((LINE_LEN * QUANT_SIZE + 7) / 8) * 8> line_t;

// ============================================================================
// 3. DDR 参数头：偏移均以字节为单位，小端序，图片紧接 16 字节参数头
// ============================================================================
static const unsigned int HEADER_BYTES      = 16;
static const unsigned int SRC_WIDTH_OFFSET  = 0x00;
static const unsigned int SRC_HEIGHT_OFFSET = 0x04;
// 0x08、0x0C 为保留字，PS 写 0；RGB 数据从 HEADER_BYTES 处开始。
//
// m_axi 的基址输入在 PL 中接固定常量 DDR_BASE_ADDR，具体地址尚待确定。
// 不另设图片基地址端口；参数头与图片共用同一个 DDR 内存块。
// ddr 指针按 32 位字索引，实际读取时需要将上述字节偏移换算为字索引。

// RGB888：按行、从左到右紧密连续存放，每个像素的字节顺序为 R、G、B。
// 行末不填充；每行字节数直接使用 src_width * RGB_CHANNELS。
// 像素 (r,c) 的 R 分量相对 DDR 基址的字节偏移：
// HEADER_BYTES + (r * src_width + c) * RGB_CHANNELS。
// 不假定三个颜色分量位于同一个 32 位 DDR 字内。
// 行起点也不保证 32 位对齐，后续读取需要按连续字节偏移正确拆包。

// ============================================================================
// 4. DDR RGB888 读取：一个 32 位缓存字跨像素、跨行复用
// ============================================================================
static hls::Scalar<RGB_CHANNELS, unsigned char> read_rgb_pixel(
    const unsigned int *ddr,
    unsigned int pixel_index,
    unsigned int &word,
    unsigned int &cached_word_index)
{
#pragma HLS INLINE

    // Scalar 是视频库写入一个 RGB 像素所需的三通道容器。
    hls::Scalar<RGB_CHANNELS, unsigned char> pixel;

    for (unsigned int channel = 0; channel < RGB_CHANNELS; ++channel) {
#pragma HLS PIPELINE II=1
        // cached_word_index 记录历史缓存字，重复读取像素时也能正确复用。
        // 当前字地址直接计算；不另设行间隔或当前字节偏移变量。
        if ((HEADER_BYTES + pixel_index * RGB_CHANNELS + channel)
            / sizeof(unsigned int) != cached_word_index) {
            cached_word_index =
                (HEADER_BYTES + pixel_index * RGB_CHANNELS + channel)
                / sizeof(unsigned int);
            word = ddr[cached_word_index];
        }

        // 小端序：低地址字节位于 word 的低位。
        pixel.val[channel] = static_cast<unsigned char>(
            word >> (((HEADER_BYTES + pixel_index * RGB_CHANNELS + channel)
                      % sizeof(unsigned int)) * 8));
    }

    return pixel;
}

static void read_rgb(
    const unsigned int *ddr,
    unsigned int src_width,
    unsigned int src_height,
    hls::Mat<IMG_MAX_ROWS, IMG_MAX_COLS, HLS_8UC3> &rgb_mat)
{
#pragma HLS INLINE off

    unsigned int word = 0;
    unsigned int cached_word_index = ~0U;

    for (unsigned int src_row = 0; src_row < rgb_mat.rows; ++src_row) {
        for (unsigned int src_col = 0; src_col < rgb_mat.cols; ++src_col) {
            // 若原图只有一行/一列，给视频库重复该行/列，扩展到 2。
            // 地址始终使用 DDR 中的原始宽度，正常图片坐标不变。
            rgb_mat.write(read_rgb_pixel(
                ddr,
                (src_row < src_height ? src_row : 0) * src_width
                    + (src_col < src_width ? src_col : 0),
                word, cached_word_index));
        }
    }
}

// ============================================================================
// 5. 输出打包：一拍一整行，第一列在最低位，每个像素零扩展为 13 位
// ============================================================================
static void write_lines(
    hls::Mat<LINE_LEN, LINE_LEN, HLS_8UC1> &resized_mat,
    hls::stream<line_t> &DATA_LINE)
{
#pragma HLS INLINE off

    for (unsigned int out_row = 0; out_row < LINE_LEN; ++out_row) {
        line_t line_pack = 0;

        for (unsigned int out_col = 0; out_col < LINE_LEN; ++out_col) {
#pragma HLS PIPELINE II=1
            // 每个灰度像素只读一次，直接写入对应的 13 位切片。
            line_pack >>= QUANT_SIZE;
            line_pack.range(LINE_LEN * QUANT_SIZE - 1,
                            (LINE_LEN - 1) * QUANT_SIZE)
                = resized_mat.read().val[0];
        }

        // 高 4 位保持 0；阻塞写由 AXIS 接口转换成 TVALID/TREADY 握手。
        DATA_LINE.write(line_pack);
    }
}

// ============================================================================
// 6. 帧处理数据流：各阶段并发运行，避免流容量有限时顺序调用造成阻塞
// ============================================================================
static void process_frame(
    const unsigned int *ddr,
    unsigned int src_width,
    unsigned int src_height,
    hls::stream<line_t> &DATA_LINE)
{
#pragma HLS INLINE off
#pragma HLS DATAFLOW

    // Mat 保存流通道和尺寸信息，不在此处保存一整帧像素数组。
    // 2017.4 的双线性 Resize 需要至少两行两列；重复单像素维度保持灰度值。
    hls::Mat<IMG_MAX_ROWS, IMG_MAX_COLS, HLS_8UC3> rgb_mat(
        src_height == 1 ? 2 : src_height, src_width == 1 ? 2 : src_width);
    hls::Mat<IMG_MAX_ROWS, IMG_MAX_COLS, HLS_8UC1> gray_mat(
        src_height == 1 ? 2 : src_height, src_width == 1 ? 2 : src_width);
    hls::Mat<LINE_LEN, LINE_LEN, HLS_8UC1> resized_mat(LINE_LEN, LINE_LEN);

    read_rgb(ddr, src_width, src_height, rgb_mat);
    hls::CvtColor<HLS_RGB2GRAY>(rgb_mat, gray_mat);
    hls::Resize(gray_mat, resized_mat, HLS_INTER_LINEAR);
    write_lines(resized_mat, DATA_LINE);
}

} // namespace preprocessing

// ============================================================================
// 7. 顶层接口约定：DDR 读取、整帧请求、逐行输出分别使用独立协议
// ============================================================================
/*
 * HLS C++ 顶层参数：
 *   ddr        ：m_axi，只读取参数头和 RGB 图片，32 位数据。
 *   DATA_LINE  ：axis，每拍一整行；低 364 位有效，高 4 位补 0。
 *   return     ：ap_ctrl_hs，由 RTL 封装适配为下面的整帧请求握手。
 *
 * 预处理模块对外握手，方向以预处理模块为参照：
 *   I_data_valid ：输入；请求处理固定 DDR 地址中的一帧图片。
 *   I_data_ready ：输出；当前可以接收一个新的整帧请求。
 *   O_data_valid ：输出；当前 DATA_LINE 有效，对应 AXIS TVALID。
 *   O_data_ready ：输入；LeNet 可以接收当前行，对应 AXIS TREADY。
 *
 * I_data_valid && I_data_ready：接受一帧请求。
 * O_data_valid && O_data_ready：传输一行，一帧共传输 28 行。
 * O_data_valid && !O_data_ready：保持当前行与 valid，直到握手成功。
 * I_data_ready 只在本帧处理结束且输出全部排空后重新有效。
 *
 * 四个握手信号由 RTL 封装/AXIS 接口承载，不重复声明成 HLS 标量参数。
 * HLS ap_ready 不能直接等同于 I_data_ready；封装需要管理一次整帧事务，
 * 并按 ap_ctrl_hs 协议保持 ap_start，直到 HLS 接受启动。
 * frame_state 属于后续 RTL 封装，不在 C++ 中再定义一套状态机。
 *
 * 时钟/复位由 HLS 生成 ap_clk/ap_rst_n，封装对应连接 clk/rstn。
 * 低有效复位需在 HLS 配置中明确设置，不能只依靠端口注释。
 *
 * 第一版不使用 s_axilite：启动沿用 GPIO，尺寸放在 DDR 参数头中，
 * 基址由 PL 固定连接。不再增加 start、width/height 或地址控制寄存器。
 * DATA_LINE 是普通整行 AXIS 数据，不使用 AXI4-Stream Video 帧标记。
 * 固定输出 28 行，不额外定义 TLAST、line_valid 或 line_ready。
 */
void resize_and_gray(
    const unsigned int *ddr,
    hls::stream<preprocessing::line_t> &DATA_LINE)
{
#pragma HLS INTERFACE m_axi port=ddr offset=direct bundle=ddr
#pragma HLS INTERFACE axis port=DATA_LINE
#pragma HLS INTERFACE ap_ctrl_hs port=return

    // 先读取参数，再进入数据流区域；不新增 AXI-Lite 尺寸寄存器。
    // PS 保证 1 <= src_width <= 1920、1 <= src_height <= 1080。
    unsigned int src_width =
        ddr[preprocessing::SRC_WIDTH_OFFSET / sizeof(unsigned int)];
    unsigned int src_height =
        ddr[preprocessing::SRC_HEIGHT_OFFSET / sizeof(unsigned int)];

    preprocessing::process_frame(ddr, src_width, src_height, DATA_LINE);
}
