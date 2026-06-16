`timescale 1ns / 1ps

module video_address_mapper (
    input  wire [1:0]  rot_mode,    // 旋转模式: 00=0°, 01=90°, 10=180°, 11=270°
    input  wire [10:0] pixel_x,     // 当前视频流所在的 X 坐标
    input  wire [10:0] pixel_y,     // 当前视频流所在的 Y 坐标
    input  wire [10:0] img_width,   // 图像原始宽度 (如 640)
    input  wire [10:0] img_height,  // 图像原始高度 (如 480)
    
    output reg  [23:0] sdram_addr   // 映射后的 SDRAM 绝对物理地址
);

    wire [23:0] orig_addr;
    wire [23:0] rot90_addr;
    wire [23:0] rot180_addr;
    wire [23:0] rot270_addr;

    // 0度：常规线性映射 (Y * 宽度 + X)
    assign orig_addr = (pixel_y * img_width) + pixel_x;

    // 90度顺时针：矩阵转置 + X轴镜像
    // 新 X = 原 Y ; 新 Y = (宽度 - 1 - 原 X)
    assign rot90_addr = ((img_width - 1'b1 - pixel_x) * img_height) + pixel_y;

    // 180度：中心对称点映射
    assign rot180_addr = ((img_height - 1'b1 - pixel_y) * img_width) + (img_width - 1'b1 - pixel_x);

    // 270度顺时针：矩阵转置 + Y轴镜像
    // 新 X = (高度 - 1 - 原 Y) ; 新 Y = 原 X
    assign rot270_addr = (pixel_x * img_height) + (img_height - 1'b1 - pixel_y);

    // 多路选择器输出最终写入地址
    always @(*) begin
        case (rot_mode)
            2'b00: sdram_addr = orig_addr;
            2'b01: sdram_addr = rot90_addr;
            2'b10: sdram_addr = rot180_addr;
            2'b11: sdram_addr = rot270_addr;
            default: sdram_addr = orig_addr;
        endcase
    end

endmodule