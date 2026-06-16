`timescale 1ns / 1ps

module color_space_top(
    input  wire        clk,        
    input  wire        rst_n,
    input  wire [1:0]  cs_mode,    // 00:原图, 01:Y通道(灰度), 10:Cb通道, 11:Cr通道
    input  wire        vsync,
    input  wire        de,
    input  wire [15:0] din_rgb565,
    
    output reg         vsync_out,
    output reg         de_out,
    output reg  [15:0] dout_rgb565
);

// =================================================================
// 提取 8-bit RGB 通道
// =================================================================
wire [7:0] r8 = {din_rgb565[15:11], 3'b000};
wire [7:0] g8 = {din_rgb565[10:5],  2'b00}; 
wire [7:0] b8 = {din_rgb565[4:0],   3'b000};

// =================================================================
// 拍 1：硬件乘法器阶段 (乘法最耗时，独立一拍)
// =================================================================
reg [15:0] r_77, g_150, b_29;
reg [15:0] r_43, g_84,  b_127;
reg [15:0] r_127,g_106, b_21;
reg [15:0] rgb_d1; reg de_d1, vsync_d1; reg [1:0] mode_d1;

always @(posedge clk) begin
    r_77  <= r8 * 8'd77;   g_150 <= g8 * 8'd150;  b_29  <= b8 * 8'd29;
    r_43  <= r8 * 8'd43;   g_84  <= g8 * 8'd84;   b_127 <= b8 * 8'd127;
    r_127 <= r8 * 8'd127;  g_106 <= g8 * 8'd106;  b_21  <= b8 * 8'd21;
    
    rgb_d1 <= din_rgb565; de_d1 <= de; vsync_d1 <= vsync; mode_d1 <= cs_mode;
end

// =================================================================
// 拍 2：加法与基准偏移阶段 (Cb/Cr含有负数，统一加 128<<8=32768 避免补码溢出)
// =================================================================
reg [15:0] y_sum, cb_sum, cr_sum;
reg [15:0] rgb_d2; reg de_d2, vsync_d2; reg [1:0] mode_d2;

always @(posedge clk) begin
    y_sum  <= r_77 + g_150 + b_29;
    cb_sum <= b_127 + 16'd32768 - r_43 - g_84;
    cr_sum <= r_127 + 16'd32768 - g_106 - b_21;
    
    rgb_d2 <= rgb_d1; de_d2 <= de_d1; vsync_d2 <= vsync_d1; mode_d2 <= mode_d1;
end

// =================================================================
// 拍 3：移位提取阶段 (等效除以 256)
// =================================================================
reg [7:0] y_val, cb_val, cr_val;
reg [15:0] rgb_d3; reg de_d3, vsync_d3; reg [1:0] mode_d3;

always @(posedge clk) begin
    y_val  <= y_sum[15:8];
    cb_val <= cb_sum[15:8];
    cr_val <= cr_sum[15:8];
    
    rgb_d3 <= rgb_d2; de_d3 <= de_d2; vsync_d3 <= vsync_d2; mode_d3 <= mode_d2;
end

// =================================================================
// 拍 4：通道输出选择器 (补齐 4 拍延迟，完美兼容顶层对齐)
// =================================================================
always @(posedge clk) begin
    de_out    <= de_d3;
    vsync_out <= vsync_d3;
    
    if (de_d3) begin
        case (mode_d3)
            2'b00: dout_rgb565 <= rgb_d3; // 原图透传
            // 为了让单通道在屏幕上可见，我们将 Y/Cb/Cr 分别作为灰度图映射到 RGB565 上
            2'b01: dout_rgb565 <= {y_val[7:3],  y_val[7:2],  y_val[7:3]};  // Y 通道 (黑白亮度)
            2'b10: dout_rgb565 <= {cb_val[7:3], cb_val[7:2], cb_val[7:3]}; // Cb 通道 (蓝色分量图)
            2'b11: dout_rgb565 <= {cr_val[7:3], cr_val[7:2], cr_val[7:3]}; // Cr 通道 (红色分量图)
        endcase
    end else begin
        dout_rgb565 <= 16'd0;
    end
end

endmodule