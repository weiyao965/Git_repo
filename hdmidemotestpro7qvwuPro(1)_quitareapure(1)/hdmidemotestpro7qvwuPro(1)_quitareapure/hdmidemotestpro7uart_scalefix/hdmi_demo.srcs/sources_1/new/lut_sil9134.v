module lut_sil9134(
    input  wire [9:0]  lut_index,   // 查找表索引
    output reg  [31:0] lut_data     // 输出格式: {device_addr, reg_addr[15:0], reg_data[7:0]}
);
            
    always @(*) begin
        case (lut_index)
            10'd0: lut_data = {8'h76, 16'h0005, 8'h01};     // 复位: Soft reset all sections (寄存器 0x05 = 0x01)
            10'd1: lut_data = {8'h76, 16'h0005, 8'h00};     // 复位结束: Disable reset (寄存器 0x05 = 0x00)
            //10'd2: lut_data = {8'h76, 16'h0008, 8'h37};   // 配置视频控制寄存器 0x08 = 0x37: HSYNC/VSYNC 正常模式, RGB 24bit, 升沿触发&#8203;:contentReference[oaicite:2]{index=2}
            10'd2: lut_data = {8'h76, 16'h0008, 8'h35};     // 配置视频控制寄存器 0x08 = 0x35: HSYNC/VSYNC 正常模式, RGB 24bit, 降沿触发&#8203;:contentReference[oaicite:2]{index=2}
            10'd3: lut_data = {8'h76, 16'h0049, 8'h00};     // 禁用颜色空间转换: 寄存器 0x49 = 0x00
            10'd4: lut_data = {8'h76, 16'h004a, 8'h00};     // 继续禁用其他功能模块: 寄存器 0x4A = 0x00
            10'd5: lut_data = {8'h76, 16'h0082, 8'h25};     // // 0x82: TCLKSEL=01 (1x), LVBIAS=1, STERM=1
            //10'd6: lut_data = {8'h76, 16'h0083, 8'h58};   //TMDS 2倍输出 post_count = 01
            10'd6: lut_data = {8'h76, 16'h0083, 8'h18};     //TMDS 1倍输出 post_count = 00
            10'd7: lut_data = {8'h76, 16'h0084, 8'h33};     // PLL 设置: 寄存器 0x84 = 0x33 （PLL 滤波后置分频配置）
            10'd8: lut_data = {8'h76, 16'h0085, 8'h00};     // PLL 设置: 寄存器 0x85 = 0x00 （PLL 前置计数设置）
            10'd9: lut_data = {8'h7e,16'h2f,8'h00};         //禁止audio
            10'd10: lut_data = {8'hFF, 24'h000000};         // LUT 结束标志 (dev_addr = 0xFF)
            default: lut_data = {8'hFF, 24'h000000};        // 默认也为结束标志
        endcase
    end

endmodule
