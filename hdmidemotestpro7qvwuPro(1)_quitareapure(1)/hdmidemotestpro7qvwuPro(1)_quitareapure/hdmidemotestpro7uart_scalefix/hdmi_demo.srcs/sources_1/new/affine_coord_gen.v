`timescale 1ns / 1ps
/**
 * 仿射变换坐标计算引擎 (逆向映射)
 * 修正版：严格的位宽保护，防止负数截断导致符号位反转
 */
module affine_coord_gen(
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire signed [15:0] mat_a, input  wire signed [15:0] mat_b, input  wire signed [15:0] mat_c,
    input  wire signed [15:0] mat_d, input  wire signed [15:0] mat_e, input  wire signed [15:0] mat_f,

    input  wire [10:0] curr_x, 
    input  wire [10:0] curr_y, 
    input  wire        de_in,
    
    output reg  [10:0] src_x_int,  // 原图 X 坐标整数部分
    output reg  [10:0] src_y_int,  // 原图 Y 坐标整数部分
    output reg  [7:0]  weight_x,   // X 方向小数权重 (0~255)
    output reg  [7:0]  weight_y,   // Y 方向小数权重 (0~255)
    output reg         de_out
);

// =========================================================
// 第一拍：分通道乘法 (DSP资源)
// 12位(curr) * 16位(mat) = 严格的 28 位乘积！
// =========================================================
reg signed [27:0] x_mul_a, y_mul_b;
reg signed [27:0] x_mul_d, y_mul_e;
reg signed [27:0] c_d1, f_d1;
reg               de_d1;

always @(posedge clk) begin
    x_mul_a <= $signed({1'b0, curr_x}) * mat_a;
    y_mul_b <= $signed({1'b0, curr_y}) * mat_b;
    x_mul_d <= $signed({1'b0, curr_x}) * mat_d;
    y_mul_e <= $signed({1'b0, curr_y}) * mat_e;
    
    // 平移参数也统一放大256倍(左移8位)，并转为28位以对齐加法器
    c_d1 <= $signed(mat_c) * 28'd256; 
    f_d1 <= $signed(mat_f) * 28'd256;
    de_d1 <= de_in;
end

// =========================================================
// 第二拍：加法汇总
// 3个28位数字相加，可能产生进位，因此扩展到 30 位绝对防溢出
// =========================================================
reg signed [29:0] sum_x, sum_y;
reg               de_d2;

always @(posedge clk) begin
    sum_x <= x_mul_a + y_mul_b + c_d1;
    sum_y <= x_mul_d + y_mul_e + f_d1;
    de_d2 <= de_d1;
end

// =========================================================
// 第三拍：分离整数与小数权重
// =========================================================
always @(posedge clk) begin
    if (sum_x[29]) begin // 负数边界截断保护
        src_x_int <= 11'd0;
        weight_x  <= 8'd0;
    end else begin
        src_x_int <= sum_x[18:8]; 
        weight_x  <= sum_x[7:0];  // 提取低8位作为小数位，相当于除以256的余数
    end

    if (sum_y[29]) begin // 负数边界截断保护
        src_y_int <= 11'd0;
        weight_y  <= 8'd0;
    end else begin
        src_y_int <= sum_y[18:8]; 
        weight_y  <= sum_y[7:0];
    end
    
    de_out <= de_d2;
end

endmodule