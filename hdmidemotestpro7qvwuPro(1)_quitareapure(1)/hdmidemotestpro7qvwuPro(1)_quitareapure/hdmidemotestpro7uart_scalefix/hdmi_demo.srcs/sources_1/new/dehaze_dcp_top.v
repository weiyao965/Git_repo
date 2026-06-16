`timescale 1ns / 1ps
/**
 * 暗通道先验 (Dark Channel Prior) 图像去雾硬件加速器
 * 核心优化：无除法器设计 (ROM查表)、3x3 流水线暗通道提取
 * 边界修复版：添加了行计数器和 0xFF 边界填充，完美消除左/上亮边
 * 总延迟：9 拍
 */
module dehaze_dcp_top(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [15:0] din_rgb565,
    
    output reg         vsync_out,
    output reg         de_out,
    output reg  [15:0] dout_rgb565
);

// 1. 扩展颜色并求像素级最小通道 (第 1 拍)
wire [7:0] r_in = {din_rgb565[15:11], din_rgb565[15:13]};
wire [7:0] g_in = {din_rgb565[10:5],  din_rgb565[10:9]};
wire [7:0] b_in = {din_rgb565[4:0],   din_rgb565[4:2]};

reg [7:0] min_rgb;
reg [15:0] rgb_d1;
reg de_d1, vsync_d1;

always @(posedge clk) begin
    min_rgb <= (r_in < g_in) ? ((r_in < b_in) ? r_in : b_in) : ((g_in < b_in) ? g_in : b_in);
    rgb_d1 <= din_rgb565;
    de_d1 <= de;
    vsync_d1 <= vsync;
end

// 2. 双行缓存 (Line Buffers) 与行/列计数器 (第 2 拍)
reg [10:0] x_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) x_cnt <= 0;
    else if (!de_d1) x_cnt <= 0;
    else x_cnt <= x_cnt + 1;
end

// ᐠ 新增：行计数器，用于识别画面的最上方两行 ᐍ
reg [10:0] y_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) y_cnt <= 0;
    else if (vsync) y_cnt <= 0; // 帧同步复位
    else if (de && !de_d1) y_cnt <= y_cnt + 1; // 捕获行的起始上升沿
end

(* ramstyle = "block" *) reg [7:0] line_buf_0 [0:1023];
(* ramstyle = "block" *) reg [7:0] line_buf_1 [0:1023];
reg [7:0] buf0_out, buf1_out;

reg [7:0] min_rgb_d2;
reg [15:0] rgb_d2;
reg de_d2, vsync_d2;

always @(posedge clk) begin
    if (de_d1) begin
        // ᐠ 核心修复 1：顶部边界保护。前两行不读脏数据，强制填充 255 (0xFF) ᐍ
        buf0_out <= (y_cnt > 1) ? line_buf_0[x_cnt] : 8'hFF;
        buf1_out <= (y_cnt > 2) ? line_buf_1[x_cnt] : 8'hFF;
        
        line_buf_0[x_cnt] <= min_rgb;
        line_buf_1[x_cnt] <= buf0_out;
    end
    min_rgb_d2 <= min_rgb;
    rgb_d2 <= rgb_d1;
    de_d2 <= de_d1;
    vsync_d2 <= vsync_d1;
end

// 3. 构建 3x3 矩阵 (第 3 拍)
reg [7:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;
reg [15:0] rgb_d3;
reg de_d3, vsync_d3;

always @(posedge clk) begin
    if (de_d2) begin
        p13 <= p12; p12 <= p11; p11 <= buf1_out;
        p23 <= p22; p22 <= p21; p21 <= buf0_out;
        p33 <= p32; p32 <= p31; p31 <= min_rgb_d2;
    end else begin
        // ᐠ 核心修复 2：左侧边界保护。消隐期用 255 填充，防止最小值被 0 污染 ᐍ
        p11<=8'hFF; p12<=8'hFF; p13<=8'hFF; 
        p21<=8'hFF; p22<=8'hFF; p23<=8'hFF; 
        p31<=8'hFF; p32<=8'hFF; p33<=8'hFF;
    end
    rgb_d3 <= rgb_d2;
    de_d3 <= de_d2;
    vsync_d3 <= vsync_d2;
end

// 4. 求 3x3 局部最小值的中间结果 (第 4 拍)
reg [7:0] min_r1, min_r2, min_r3;
reg [15:0] rgb_d4;
reg de_d4, vsync_d4;

always @(posedge clk) begin
    min_r1 <= (p11 < p12) ? ((p11 < p13) ? p11 : p13) : ((p12 < p13) ? p12 : p13);
    min_r2 <= (p21 < p22) ? ((p21 < p23) ? p21 : p23) : ((p22 < p23) ? p22 : p23);
    min_r3 <= (p31 < p32) ? ((p31 < p33) ? p31 : p33) : ((p32 < p33) ? p32 : p33);
    rgb_d4 <= rgb_d3; de_d4 <= de_d3; vsync_d4 <= vsync_d3;
end

// 5. 得到最终暗通道值 Dark Channel (第 5 拍)
reg [7:0] dark_channel;
reg [15:0] rgb_d5;
reg de_d5, vsync_d5;

always @(posedge clk) begin
    dark_channel <= (min_r1 < min_r2) ? ((min_r1 < min_r3) ? min_r1 : min_r3) : ((min_r2 < min_r3) ? min_r2 : min_r3);
    rgb_d5 <= rgb_d4; de_d5 <= de_d4; vsync_d5 <= vsync_d4;
end

// 6. 计算透射率 t(x) (第 6 拍)
reg [7:0] t_x;
reg [15:0] rgb_d6;
reg de_d6, vsync_d6;

always @(posedge clk) begin
    if ((9'd255 - dark_channel + (dark_channel >> 4)) < 9'd26)
        t_x <= 8'd26;
    else
        t_x <= 8'd255 - dark_channel + (dark_channel >> 4);
        
    rgb_d6 <= rgb_d5; de_d6 <= de_d5; vsync_d6 <= vsync_d5;
end

// 7. 使用初始化 ROM 查表求倒数 1/t(x) (第 7 拍)
reg [11:0] inv_t_rom [0:255];
integer i;
initial begin
    for (i = 0; i <= 255; i = i + 1) begin
        if (i < 26) inv_t_rom[i] = 12'd2510;
        else inv_t_rom[i] = 17'd65280 / i;
    end
end

reg [11:0] inv_t;
reg [15:0] rgb_d7;
reg de_d7, vsync_d7;

always @(posedge clk) begin
    inv_t <= inv_t_rom[t_x]; 
    rgb_d7 <= rgb_d6; de_d7 <= de_d6; vsync_d7 <= vsync_d6;
end

// =========================================================================
// 8. 恢复图像辐射度 J(x) (第 8 拍) - 修复偏蓝与偏暗
// 公式: J(x) = (I(x) - A) / t(x) + A
// =========================================================================
wire [7:0] r_d7 = {rgb_d7[15:11], rgb_d7[15:13]};
wire [7:0] g_d7 = {rgb_d7[10:5],  rgb_d7[10:9]};
wire [7:0] b_d7 = {rgb_d7[4:0],   rgb_d7[4:2]};

// 优化 1：引入可调节的大气光 A (建议后续由寄存器配置，这里给典型值)
// 雾通常偏蓝，所以 A_b > A_g > A_r
wire [7:0] A_r = 8'd180; 
wire [7:0] A_g = 8'd200;
wire [7:0] A_b = 8'd220;

// 计算 I(x) - A 的符号与绝对值 (硬件中避免有符号除法)
wire r_sign = (r_d7 < A_r);
wire g_sign = (g_d7 < A_g);
wire b_sign = (b_d7 < A_b);

wire [7:0] r_abs = r_sign ? (A_r - r_d7) : (r_d7 - A_r);
wire [7:0] g_abs = g_sign ? (A_g - g_d7) : (g_d7 - A_g);
wire [7:0] b_abs = b_sign ? (A_b - b_d7) : (b_d7 - A_b);

// 计算绝对值差项: |I - A| * inv_t
wire [19:0] r_delta = (r_abs * inv_t) >> 8;
wire [19:0] g_delta = (g_abs * inv_t) >> 8;
wire [19:0] b_delta = (b_abs * inv_t) >> 8;

reg [7:0] r_out, g_out, b_out;
reg [15:0] rgb_d8;
reg de_d8, vsync_d8;

always @(posedge clk) begin
    // 根据符号恢复真实的 J(x)，并做饱和截断保护
    if (r_sign) r_out <= (A_r > r_delta) ? (A_r - r_delta[7:0]) : 8'd0;
    else        r_out <= ((A_r + r_delta) < 255) ? (A_r + r_delta[7:0]) : 8'd255;

    if (g_sign) g_out <= (A_g > g_delta) ? (A_g - g_delta[7:0]) : 8'd0;
    else        g_out <= ((A_g + g_delta) < 255) ? (A_g + g_delta[7:0]) : 8'd255;

    if (b_sign) b_out <= (A_b > b_delta) ? (A_b - b_delta[7:0]) : 8'd0;
    else        b_out <= ((A_b + b_delta) < 255) ? (A_b + b_delta[7:0]) : 8'd255;
    
    rgb_d8 <= rgb_d7; de_d8 <= de_d7; vsync_d8 <= vsync_d7;
end

// =========================================================================
// 9. 曝光补偿与封包输出 (第 9 拍) - 微调亮度版
// =========================================================================
// 增益调整为 1.125 倍 (即 x + x/8)，防止高光过曝
wire [8:0] r_exp = r_out + (r_out >> 3);
wire [8:0] g_exp = g_out + (g_out >> 3);
wire [8:0] b_exp = b_out + (b_out >> 3);

wire [7:0] r_final = (r_exp > 255) ? 8'd255 : r_exp[7:0];
wire [7:0] g_final = (g_exp > 255) ? 8'd255 : g_exp[7:0];
wire [7:0] b_final = (b_exp > 255) ? 8'd255 : b_exp[7:0];

always @(posedge clk) begin
    de_out <= de_d8;
    vsync_out <= vsync_d8;
    // 转回 RGB565 输出
    dout_rgb565 <= {r_final[7:3], g_final[7:2], b_final[7:3]};
end

endmodule