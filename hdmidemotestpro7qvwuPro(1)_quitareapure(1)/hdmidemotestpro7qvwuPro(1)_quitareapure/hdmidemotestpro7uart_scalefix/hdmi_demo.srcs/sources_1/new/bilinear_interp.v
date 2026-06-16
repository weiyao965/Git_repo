`timescale 1ns / 1ps
/**
 * 硬件双线性插值流水线 (RGB565 专用)
 * 延迟：2 拍
 */
module bilinear_interp(
    input  wire        clk,
    // 4个相邻像素 (左上, 右上, 左下, 右下)
    input  wire [15:0] p11, input wire [15:0] p12,
    input  wire [15:0] p21, input wire [15:0] p22,
    // 亚像素权重 (0~255)
    input  wire [7:0]  weight_x,
    input  wire [7:0]  weight_y,
    // 插值输出
    output reg  [15:0] rgb_out
);

// 扩展为 8位 色彩通道进行高精度计算
wire [7:0] r11 = {p11[15:11], 3'b0}, g11 = {p11[10:5], 2'b0}, b11 = {p11[4:0], 3'b0};
wire [7:0] r12 = {p12[15:11], 3'b0}, g12 = {p12[10:5], 2'b0}, b12 = {p12[4:0], 3'b0};
wire [7:0] r21 = {p21[15:11], 3'b0}, g21 = {p21[10:5], 2'b0}, b21 = {p21[4:0], 3'b0};
wire [7:0] r22 = {p22[15:11], 3'b0}, g22 = {p22[10:5], 2'b0}, b22 = {p22[4:0], 3'b0};

wire [8:0] inv_wx = 9'd256 - weight_x;
wire [8:0] inv_wy = 9'd256 - weight_y;

// --- 第一拍：X 方向混合 ---
// 8位色彩 * 9位权重 = 17位结果
reg [16:0] r_top, r_bot, g_top, g_bot, b_top, b_bot;
reg [8:0]  wy_d1, inv_wy_d1;

always @(posedge clk) begin
    r_top <= r11 * inv_wx + r12 * weight_x;
    r_bot <= r21 * inv_wx + r22 * weight_x;
    g_top <= g11 * inv_wx + g12 * weight_x;
    g_bot <= g21 * inv_wx + g22 * weight_x;
    b_top <= b11 * inv_wx + b12 * weight_x;
    b_bot <= b21 * inv_wx + b22 * weight_x;
    wy_d1 <= weight_y; 
    inv_wy_d1 <= inv_wy;
end

// --- 第二拍：Y 方向混合并封包 ---
// (x_top[16:8] 相当于把第一步的结果除以 256)
always @(posedge clk) begin
    rgb_out[15:11] <= ((r_top[16:8] * inv_wy_d1 + r_bot[16:8] * wy_d1) >> 8) >> 3;
    rgb_out[10:5]  <= ((g_top[16:8] * inv_wy_d1 + g_bot[16:8] * wy_d1) >> 8) >> 2;
    rgb_out[4:0]   <= ((b_top[16:8] * inv_wy_d1 + b_bot[16:8] * wy_d1) >> 8) >> 3;
end

endmodule