`timescale 1ns / 1ps

module retinex_ssr_top(
    input  wire        clk,        
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [15:0] din_rgb565,
    
    output reg         vsync_out,
    output reg         de_out,
    output reg  [15:0] dout_rgb565
);

// =================================================================
// 第 1 拍：RGB 转灰度 (提取亮度 Y)
// =================================================================
wire [7:0] r8 = {din_rgb565[15:11], 3'b000};
wire [7:0] g8 = {din_rgb565[10:5],  2'b00};
wire [7:0] b8 = {din_rgb565[4:0],   3'b000};

reg [7:0]  gray_d1;
reg [23:0] rgb_d1;
reg        de_d1, vsync_d1;

always @(posedge clk) begin
    gray_d1  <= (r8 * 16'd77 + g8 * 16'd150 + b8 * 16'd29) >> 8;
    rgb_d1   <= {r8, g8, b8};
    de_d1    <= de;
    vsync_d1 <= vsync;
end

// =================================================================
// 第 2 拍：双行缓存 (Line Buffers) 
// =================================================================
reg [10:0] x_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)      x_cnt <= 11'd0;
    else if (!de_d1) x_cnt <= 11'd0;
    else             x_cnt <= x_cnt + 1'b1;
end

(* ramstyle = "block" *) reg [7:0] line_buf_0 [0:1023];
(* ramstyle = "block" *) reg [7:0] line_buf_1 [0:1023];

reg [7:0] buf0_out, buf1_out;
reg [7:0] gray_d2;
reg [23:0] rgb_d2;
reg        de_d2, vsync_d2;

always @(posedge clk) begin
    if (de_d1) begin
        buf0_out <= line_buf_0[x_cnt];
        buf1_out <= line_buf_1[x_cnt];
        line_buf_0[x_cnt] <= gray_d1;
        line_buf_1[x_cnt] <= buf0_out; 
    end
    gray_d2  <= gray_d1;
    rgb_d2   <= rgb_d1;
    de_d2    <= de_d1;
    vsync_d2 <= vsync_d1;
end

// =================================================================
// 第 3 拍：构建 3x3 亮度矩阵
// =================================================================
reg [7:0] p11, p12, p13;
reg [7:0] p21, p22, p23;
reg [7:0] p31, p32, p33;
reg [23:0] rgb_d3;
reg        de_d3, vsync_d3;

always @(posedge clk) begin
    if (de_d2) begin
        p13 <= p12; p12 <= p11; p11 <= buf1_out;
        p23 <= p22; p22 <= p21; p21 <= buf0_out;
        p33 <= p32; p32 <= p31; p31 <= gray_d2;
    end else begin
        p11<=0; p12<=0; p13<=0; p21<=0; p22<=0; p23<=0; p31<=0; p32<=0; p33<=0;
    end
    rgb_d3   <= rgb_d2;
    de_d3    <= de_d2;
    vsync_d3 <= vsync_d2;
end

// =================================================================
// 第 4 拍：高斯模糊估计环境光 (L)
// 权重: [1 2 1; 2 4 2; 1 2 1] / 16
// =================================================================
reg [11:0] L_sum;
reg [7:0]  l_val;
reg [23:0] rgb_d4;
reg        de_d4, vsync_d4;

always @(posedge clk) begin
    L_sum <= p11 + p13 + p31 + p33 + ((p12 + p21 + p23 + p32) << 1) + (p22 << 2);
    l_val <= L_sum[11:4]; // 相当于除以 16
    
    rgb_d4   <= rgb_d3;
    de_d4    <= de_d3;
    vsync_d4 <= vsync_d3;
end

// =================================================================
// 第 5 拍：SSR LUT 查表获取增益
// =================================================================
reg [7:0] gain_val; // Q2.6 格式增益 (64 = 1.0倍)

// 载入由 Python 生成的查找表
`include "retinex_lut.vh"

reg [23:0] rgb_d5;
reg        de_d5, vsync_d5;

always @(posedge clk) begin
    rgb_d5   <= rgb_d4;
    de_d5    <= de_d4;
    vsync_d5 <= vsync_d4;
end

// =================================================================
// 第 6 拍：应用增益 (I * Gain)
// =================================================================
reg [15:0] r_ext, g_ext, b_ext;
reg        de_d6, vsync_d6;

always @(posedge clk) begin
    // 原始RGB乘以查表得到的增益，避免了除法
    r_ext <= rgb_d5[23:16] * gain_val;
    g_ext <= rgb_d5[15:8]  * gain_val;
    b_ext <= rgb_d5[7:0]   * gain_val;
    
    de_d6    <= de_d5;
    vsync_d6 <= vsync_d5;
end

// =================================================================
// 第 7 拍：溢出截断与输出对齐 (已修复位截断 BUG)
// =================================================================
always @(posedge clk) begin
    de_out    <= de_d6;
    vsync_out <= vsync_d6;
    
    if (de_d6) begin
        // r_ext[15:6] 代表还原后的 8 位真实颜色值。
        // 取其高 5 位即 r_ext[13:9] 作为 RGB565 的 R 通道
        dout_rgb565[15:11] <= (r_ext[15:6] > 10'd255) ? 5'h1F : r_ext[13:9];
        
        // 取其高 6 位即 g_ext[13:8] 作为 RGB565 的 G 通道
        dout_rgb565[10:5]  <= (g_ext[15:6] > 10'd255) ? 6'h3F : g_ext[13:8];
        
        // 取其高 5 位即 b_ext[13:9] 作为 RGB565 的 B 通道
        dout_rgb565[4:0]   <= (b_ext[15:6] > 10'd255) ? 5'h1F : b_ext[13:9];
    end else begin
        dout_rgb565 <= 16'd0;
    end
end

endmodule