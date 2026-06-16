`timescale 1ns / 1ps

module morphology_top(
    input  wire        clk,        
    input  wire        rst_n,
    input  wire [1:0]  morph_mode, 
    input  wire        vsync,
    input  wire        de,
    input  wire [15:0] din_rgb565,
    
    output reg         vsync_out,
    output reg         de_out,
    output reg  [15:0] dout_rgb565
);

// =================================================================
// 1. 灰度化与二值化 (第 1 拍)
// =================================================================
wire [7:0] r8 = {din_rgb565[15:11], 3'b000};
wire [7:0] g8 = {din_rgb565[10:5],  2'b00}; 
wire [7:0] b8 = {din_rgb565[4:0],   3'b000};

// 提前计算灰度与二值 (组合逻辑)
wire [15:0] gray = (r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29) >> 8;
wire        bin_val = (gray > 16'd128) ? 1'b1 : 1'b0;

reg        binary_d1;
reg [15:0] rgb_d1;
reg        de_d1, vsync_d1;

always @(posedge clk) begin
    if (de) binary_d1 <= bin_val;
    else    binary_d1 <= 1'b0;
    
    rgb_d1   <= din_rgb565;
    de_d1    <= de;
    vsync_d1 <= vsync;
end

// =================================================================
// 2. 双行缓存 (Line Buffers) - 解决 BRAM 读写冲突 (第 2 拍)
// =================================================================
reg [10:0] x_cnt; // 11位，支持最大 2048 宽度的分辨率
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        x_cnt <= 11'd0;
    else if (!de_d1) 
        x_cnt <= 11'd0;
    else 
        x_cnt <= x_cnt + 1'b1;
end

(* ramstyle = "block" *) reg line_buf_0 [0:2047];
(* ramstyle = "block" *) reg line_buf_1 [0:2047];

reg        buf0_out, buf1_out;
reg        binary_d2;
reg [15:0] rgb_d2;
reg        de_d2, vsync_d2;
reg [10:0] x_cnt_d1;

// A. 读操作: 从 BRAM 读出前两行的历史数据
always @(posedge clk) begin
    if (de_d1) begin
        buf0_out <= line_buf_0[x_cnt];
        buf1_out <= line_buf_1[x_cnt];
    end
    x_cnt_d1  <= x_cnt; // 锁存读地址
    binary_d2 <= binary_d1;
    rgb_d2    <= rgb_d1;
    de_d2     <= de_d1;
    vsync_d2  <= vsync_d1;
end

// B. 写操作: 错开一拍写入，彻底避免 Read-During-Write 综合问题
always @(posedge clk) begin
    if (de_d2) begin
        line_buf_0[x_cnt_d1] <= binary_d2;
        line_buf_1[x_cnt_d1] <= buf0_out; // 刚好把老数据往下级推
    end
end

// =================================================================
// 3. 构建 3x3 像素矩阵 (第 3 拍)
// =================================================================
reg matrix_p11, matrix_p12, matrix_p13;
reg matrix_p21, matrix_p22, matrix_p23;
reg matrix_p31, matrix_p32, matrix_p33;

reg        de_d3, vsync_d3;
reg [15:0] rgb_d3;
reg [1:0]  mode_d3;

always @(posedge clk) begin
    if (de_d2) begin
        matrix_p13 <= matrix_p12; matrix_p12 <= matrix_p11; matrix_p11 <= buf1_out;
        matrix_p23 <= matrix_p22; matrix_p22 <= matrix_p21; matrix_p21 <= buf0_out;
        matrix_p33 <= matrix_p32; matrix_p32 <= matrix_p31; matrix_p31 <= binary_d2;
    end else begin
        matrix_p11 <= 0; matrix_p12 <= 0; matrix_p13 <= 0;
        matrix_p21 <= 0; matrix_p22 <= 0; matrix_p23 <= 0;
        matrix_p31 <= 0; matrix_p32 <= 0; matrix_p33 <= 0;
    end
    rgb_d3   <= rgb_d2;
    de_d3    <= de_d2;
    vsync_d3 <= vsync_d2;
    mode_d3  <= morph_mode;
end

// =================================================================
// 4. 形态学计算与输出多路器 (第 4 拍)
// =================================================================
always @(posedge clk) begin
    de_out    <= de_d3;
    vsync_out <= vsync_d3;
    
    if (de_d3) begin
        case (mode_d3)
            2'b00: dout_rgb565 <= rgb_d3; // 原图透传
            
            2'b01: dout_rgb565 <= matrix_p22 ? 16'hFFFF : 16'h0000; // 纯二值化
            
            2'b10: dout_rgb565 <= (matrix_p11 & matrix_p12 & matrix_p13 &
                                   matrix_p21 & matrix_p22 & matrix_p23 &
                                   matrix_p31 & matrix_p32 & matrix_p33) 
                                   ? 16'hFFFF : 16'h0000; // 腐蚀(Erosion): 局部最小 (全白才白)
                                   
            2'b11: dout_rgb565 <= (matrix_p11 | matrix_p12 | matrix_p13 |
                                   matrix_p21 | matrix_p22 | matrix_p23 |
                                   matrix_p31 | matrix_p32 | matrix_p33) 
                                   ? 16'hFFFF : 16'h0000; // 膨胀(Dilation): 局部最大 (有白就白)
        endcase
    end else begin
        dout_rgb565 <= 16'd0;
    end
end

endmodule