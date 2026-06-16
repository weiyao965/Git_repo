`timescale 1ns / 1ps

module sobel_edge_top(
    input  wire        clk,        
    input  wire        rst_n,
    input  wire [1:0]  sobel_mode, // 00: 原图透传, 01: 纯黑白轮廓, 10: 霓虹描边特效
    input  wire        vsync,
    input  wire        de,
    input  wire [15:0] din_rgb565,
    
    output reg         vsync_out,
    output reg         de_out,
    output reg  [15:0] dout_rgb565
);

// =================================================================
// 第 1 拍：RGB 转灰度 (Grayscale)
// =================================================================
wire [7:0] r8 = {din_rgb565[15:11], 3'b000};
wire [7:0] g8 = {din_rgb565[10:5],  2'b00};
wire [7:0] b8 = {din_rgb565[4:0],   3'b000};

reg [7:0]  gray_d1;
reg [15:0] rgb_d1;
reg        de_d1, vsync_d1;

always @(posedge clk) begin
    // 强制使用 16 位乘法，防止数据在相加前被截断溢出！
    gray_d1  <= (r8 * 16'd77 + g8 * 16'd150 + b8 * 16'd29) >> 8;
    rgb_d1   <= din_rgb565;
    de_d1    <= de;
    vsync_d1 <= vsync;
end

// =================================================================
// 第 2 拍：双行缓存 (Line Buffers) 
// =================================================================
reg [10:0] x_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)     x_cnt <= 11'd0;
    else if (!de_d1) x_cnt <= 11'd0;
    else            x_cnt <= x_cnt + 1'b1;
end

(* ramstyle = "block" *) reg [7:0] line_buf_0 [0:2047];
(* ramstyle = "block" *) reg [7:0] line_buf_1 [0:2047];

reg [7:0] buf0_out, buf1_out;
reg [7:0] gray_d2;
reg [15:0] rgb_d2;
reg        de_d2, vsync_d2;
reg [10:0] x_cnt_d1;

always @(posedge clk) begin
    if (de_d1) begin
        buf0_out <= line_buf_0[x_cnt];
        buf1_out <= line_buf_1[x_cnt];
    end
    x_cnt_d1 <= x_cnt;
    gray_d2  <= gray_d1;
    rgb_d2   <= rgb_d1;
    de_d2    <= de_d1;
    vsync_d2 <= vsync_d1;
end

always @(posedge clk) begin
    if (de_d2) begin
        line_buf_0[x_cnt_d1] <= gray_d2;
        line_buf_1[x_cnt_d1] <= buf0_out; 
    end
end

// =================================================================
// 第 3 拍：构建 3x3 矩阵
// =================================================================
reg [7:0] p11, p12, p13;
reg [7:0] p21, p22, p23;
reg [7:0] p31, p32, p33;

reg        de_d3, vsync_d3;
reg [15:0] rgb_d3;
reg [1:0]  mode_d3;

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
    mode_d3  <= sobel_mode;
end

// =================================================================
// 第 4 拍：Sobel 卷积计算 (分离正负方向，防止溢出)
// =================================================================
reg [9:0] gx_p, gx_n; // X方向正负梯度
reg [9:0] gy_p, gy_n; // Y方向正负梯度

reg        de_d4, vsync_d4;
reg [15:0] rgb_d4;
reg [1:0]  mode_d4;

always @(posedge clk) begin
    // X方向: [1 0 -1; 2 0 -2; 1 0 -1]
    gx_p <= p13 + (p23 << 1) + p33;
    gx_n <= p11 + (p21 << 1) + p31;
    
    // Y方向: [1 2 1; 0 0 0; -1 -2 -1]
    gy_p <= p11 + (p12 << 1) + p13;
    gy_n <= p31 + (p32 << 1) + p33;
    
    rgb_d4   <= rgb_d3;
    de_d4    <= de_d3;
    vsync_d4 <= vsync_d3;
    mode_d4  <= mode_d3;
end

// =================================================================
// 第 5 拍：求绝对值与幅值求和
// =================================================================
reg [9:0] gx_abs, gy_abs;
reg [10:0] g_sum;

reg        de_d5, vsync_d5;
reg [15:0] rgb_d5;
reg [1:0]  mode_d5;

always @(posedge clk) begin
    gx_abs <= (gx_p > gx_n) ? (gx_p - gx_n) : (gx_n - gx_p);
    gy_abs <= (gy_p > gy_n) ? (gy_p - gy_n) : (gy_n - gy_p);
    g_sum  <= gx_abs + gy_abs;

    rgb_d5   <= rgb_d4;
    de_d5    <= de_d4;
    vsync_d5 <= vsync_d4;
    mode_d5  <= mode_d4;
end

// =================================================================
// 第 6 拍：二值化阈值判定与艺术效果输出
// =================================================================
localparam EDGE_THRESHOLD = 11'd40; // 先调低到 40 确保能看到明显的边缘，后续可视情况微调

always @(posedge clk) begin
    de_out    <= de_d5;
    vsync_out <= vsync_d5;
    
    if (de_d5) begin
        case (mode_d5)
            2'b00: dout_rgb565 <= rgb_d5; // 原图透传
            
            2'b01: // 纯粹的黑底白线边缘提取
                dout_rgb565 <= (g_sum > EDGE_THRESHOLD) ? 16'hFFFF : 16'h0000;
                
            2'b10: // 霓虹灯艺术特效：在彩色原图上叠加青色或紫色的亮光描边
                dout_rgb565 <= (g_sum > EDGE_THRESHOLD) ? 16'h07FF : rgb_d5; 
				
			2'b11: // ᐠ 新增：白底黑线算法 ᐍ
                // 当梯度超过阈值时输出黑色(0x0000)，否则输出白色(0xFFFF)
                dout_rgb565 <= (g_sum > EDGE_THRESHOLD) ? 16'h0000 : 16'hFFFF;
                
            default: dout_rgb565 <= rgb_d5;
        endcase
    end else begin
        dout_rgb565 <= 16'd0;
    end
end

endmodule