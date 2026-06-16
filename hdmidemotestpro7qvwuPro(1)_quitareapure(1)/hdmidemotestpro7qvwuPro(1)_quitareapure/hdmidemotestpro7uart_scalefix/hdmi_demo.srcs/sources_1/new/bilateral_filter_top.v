`timescale 1ns / 1ps

module bilateral_filter_top(
    input  wire        clk,        
    input  wire        rst_n,
    input  wire [1:0]  bf_mode,    
    input  wire        vsync,
    input  wire        de,
    input  wire [15:0] din_rgb565,
    
    output reg         vsync_out,
    output reg         de_out,
    output reg  [15:0] dout_rgb565
);

// =================================================================
// 1. 双行缓存 Line Buffers (第 1 拍)
// =================================================================
reg [10:0] x_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)     x_cnt <= 11'd0;
    else if (!de)   x_cnt <= 11'd0;
    else            x_cnt <= x_cnt + 1'b1;
end

(* ramstyle = "block" *) reg [15:0] line_buf_0 [0:2047];
(* ramstyle = "block" *) reg [15:0] line_buf_1 [0:2047];

reg [15:0] buf0_out, buf1_out;
reg [15:0] rgb_d1;
reg        de_d1, vsync_d1;
reg [10:0] x_cnt_d1;

always @(posedge clk) begin
    if (de) begin
        buf0_out <= line_buf_0[x_cnt];
        buf1_out <= line_buf_1[x_cnt];
    end
    x_cnt_d1 <= x_cnt;
    rgb_d1   <= din_rgb565;
    de_d1    <= de;
    vsync_d1 <= vsync;
end

always @(posedge clk) begin
    if (de_d1) begin
        line_buf_0[x_cnt_d1] <= rgb_d1;
        line_buf_1[x_cnt_d1] <= buf0_out; 
    end
end

// =================================================================
// 2. 构建 3x3 像素矩阵 (第 2 拍)
// =================================================================
reg [15:0] p11, p12, p13;
reg [15:0] p21, p22, p23;
reg [15:0] p31, p32, p33;

reg        de_d2, vsync_d2;
reg [1:0]  mode_d2;

always @(posedge clk) begin
    if (de_d1) begin
        p13 <= p12; p12 <= p11; p11 <= buf1_out;
        p23 <= p22; p22 <= p21; p21 <= buf0_out;
        p33 <= p32; p32 <= p31; p31 <= rgb_d1;
    end else begin
        p11<=0; p12<=0; p13<=0;
        p21<=0; p22<=0; p23<=0;
        p31<=0; p32<=0; p33<=0;
    end
    de_d2    <= de_d1;
    vsync_d2 <= vsync_d1;
    mode_d2  <= bf_mode;
end

// =================================================================
// 3. 核心计算：平滑核、边缘检测 (第 3 拍)
// =================================================================
wire [4:0] r11 = p11[15:11], r12 = p12[15:11], r13 = p13[15:11];
wire [4:0] r21 = p21[15:11], r22 = p22[15:11], r23 = p23[15:11];
wire [4:0] r31 = p31[15:11], r32 = p32[15:11], r33 = p33[15:11];

wire [5:0] g11 = p11[10:5],  g12 = p12[10:5],  g13 = p13[10:5];
wire [5:0] g21 = p21[10:5],  g22 = p22[10:5],  g23 = p23[10:5];
wire [5:0] g31 = p31[10:5],  g32 = p32[10:5],  g33 = p33[10:5];

wire [4:0] b11 = p11[4:0],   b12 = p12[4:0],   b13 = p13[4:0];
wire [4:0] b21 = p21[4:0],   b22 = p22[4:0],   b23 = p23[4:0];
wire [4:0] b31 = p31[4:0],   b32 = p32[4:0],   b33 = p33[4:0];

reg [8:0]  sum_r, sum_b;
reg [9:0]  sum_g;
reg [7:0]  edge_diff; 
reg [15:0] p22_d3;

reg        de_d3, vsync_d3;
reg [1:0]  mode_d3;

always @(posedge clk) begin
    // A. 甜甜圈均值平滑 (求外围8点之和，整体再乘2凑够16的权重，方便后续移位除法)
    sum_r <= (r11 + r12 + r13 + r21 + r23 + r31 + r32 + r33) << 1;
    sum_g <= (g11 + g12 + g13 + g21 + g23 + g31 + g32 + g33) << 1;
    sum_b <= (b11 + b12 + b13 + b21 + b23 + b31 + b32 + b33) << 1;

    // B. G通道十字色差检测 (判定是否为边缘)
    edge_diff <= ((g12 > g22) ? (g12 - g22) : (g22 - g12)) +
                 ((g32 > g22) ? (g32 - g22) : (g22 - g32)) +
                 ((g21 > g22) ? (g21 - g22) : (g22 - g21)) +
                 ((g23 > g22) ? (g23 - g22) : (g22 - g23));

    p22_d3   <= p22; 
    de_d3    <= de_d2;
    vsync_d3 <= vsync_d2;
    mode_d3  <= mode_d2;
end

// =================================================================
// 4. 混合输出：智能分发 (第 4 拍)
// =================================================================
always @(posedge clk) begin
    de_out    <= de_d3;
    vsync_out <= vsync_d3;

    if (de_d3) begin
        if (mode_d3 == 2'b00) begin
            dout_rgb565 <= p22_d3; // 原图透传
        end
        else if (mode_d3 == 2'b01) begin
            // 纯模糊测试：全部输出均值滤波结果 (右移4位)
            dout_rgb565 <= {sum_r[8:4], sum_g[9:4], sum_b[8:4]};
        end
        else if (mode_d3 == 2'b10) begin
            // 𑐠终极特效：漫画卡通渲染风格 (Cell Shading) 𑐍
            // 将阈值设为 30，可以完美过滤掉绝大部分的传感器噪点
            if (edge_diff < 8'd30)
                // 平坦区：输出模糊结果，去除噪点，产生类似“水彩涂抹”的平滑色块
                dout_rgb565 <= {sum_r[8:4], sum_g[9:4], sum_b[8:4]}; 
            else
                // 边缘区：直接用纯黑墨水“勾线”！
                // 这不仅彻底消灭了“彩色闪粉”，还能产生极其强烈的视觉震撼。
                dout_rgb565 <= 16'h0000; 
        end
        else begin
            dout_rgb565 <= p22_d3;
        end
    end else begin
        dout_rgb565 <= 16'd0;
    end
end

endmodule