`timescale 1ns / 1ps

module histogram_equal_top (
    input  wire        clk,        
    input  wire        rst_n,      
    input  wire        vsync,      
    input  wire        de,         
    input  wire [15:0] din_rgb565, 
    output reg  [15:0] dout_rgb565 
);

// =================================================================
// 1. RGB提取与亮度(Y)转换 
// =================================================================
// 修改点：直接将低位补零，防止极细微的 CMOS 底层热噪声进入乘法器被暴力放大
wire [7:0] r8 = {din_rgb565[15:11], 3'b000};
wire [7:0] g8 = {din_rgb565[10:5],  2'b00}; 
wire [7:0] b8 = {din_rgb565[4:0],   3'b000};

reg [7:0] gray_y;
reg [7:0] r_d1, g_d1, b_d1;
reg       de_d1;

// --- 第 1 拍：计算灰度 Y 与提取通道 ---
always @(posedge clk) begin
// 强制使用 16 位乘法，防止数据在相加前被截断溢出！
    gray_y  <= (r8 * 16'd77 + g8 * 16'd150 + b8 * 16'd29) >> 8;
    //gray_y <= (r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29) >> 8;
    r_d1   <= r8; 
    g_d1   <= g8; 
    b_d1   <= b8;
    de_d1  <= de;
end

// =================================================================
// 2. 分布式 RAM 与 平滑夜视映射状态机 (保持不变)
// =================================================================
(* ramstyle = "logic" *) reg [19:0] his_ram [255:0];
reg [15:0] gain_lut [255:0];

reg [16:0] inv_lut [255:0];
integer i;
initial begin
    inv_lut[0] = 0;
    for(i=1; i<256; i=i+1) inv_lut[i] = 65536 / i;
end

reg vsync_d;
always @(posedge clk) vsync_d <= vsync;
wire vsync_pos = vsync & ~vsync_d;

reg [2:0]  state;
reg [8:0]  cnt;
reg [31:0] cdf_sum;
reg [7:0]  map_y;
reg [31:0] map_y_calc;

reg [31:0] raw_gain;
reg [8:0]  night_vision_floor;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= 0; cnt <= 0; cdf_sum <= 0;
    end else begin
        if (vsync_pos) begin
            state <= 2; cnt <= 0; cdf_sum <= 0;
        end 
        else if (state == 2) begin 
            cdf_sum <= cdf_sum + his_ram[cnt[7:0]];
            state   <= 3;
        end 
        else if (state == 3) begin
            map_y_calc <= (cdf_sum * 10'd873) >> 20; 
            state <= 4;
        end 
        else if (state == 4) begin
            map_y = map_y_calc[7:0];
            
            // 基础托底 40：降低极致暴力的放大倍率，换取画面纯净度
            night_vision_floor = cnt + 8'd40; 
            if (night_vision_floor > 255) night_vision_floor = 255;
            
            if (map_y < night_vision_floor[7:0]) begin
                map_y = night_vision_floor[7:0];
            end
            
            raw_gain = ({24'd0, map_y} * inv_lut[cnt[7:0]]) >> 8;
            
            if (cnt == 0) begin
                gain_lut[0] <= 16'd2048; // 控制在 8 倍基础增益
            end else begin
                // 上限封锁在 16 倍 (4096)，防止画面过度撕裂
                if (raw_gain > 32'd4096) 
                    gain_lut[cnt[7:0]] <= 16'd4096; 
                else 
                    gain_lut[cnt[7:0]] <= raw_gain[15:0];
            end

            if (cnt == 255) begin
                state <= 1; cnt <= 0;
            end else begin
                cnt <= cnt + 1; state <= 2; 
            end
        end 
        else if (state == 1) begin
            if (cnt == 255) begin
                state <= 0; cnt <= 0;
            end else cnt <= cnt + 1;
        end
    end
end

always @(posedge clk) begin
    if (state == 1) begin
        his_ram[cnt[7:0]] <= 20'd0; 
    end 
    else if (state == 0 && de_d1) begin
        his_ram[gray_y] <= his_ram[gray_y] + 1'b1; 
    end
end

// =================================================================
// 3. 应用增益与【顺滑去色引擎】 (已修复：拆分为多级流水线，对齐4拍)
// =================================================================
reg [15:0] current_gain;
reg [7:0]  r_d2, g_d2, b_d2, y_d2;
reg        de_d2;

// --- 第 2 拍：获取映射增益与数据对齐 ---
always @(posedge clk) begin
    current_gain <= gain_lut[gray_y];
    r_d2  <= r_d1; 
    g_d2  <= g_d1; 
    b_d2  <= b_d1; 
    y_d2  <= gray_y; 
    de_d2 <= de_d1;
end

// --- 第 3 拍：执行高耗时乘法运算 ---
// (独立分配一个时钟周期跑乘法，彻底解决建立时间违例引发的高位数据乱码/橙红噪点)
reg [23:0] new_r, new_g, new_b;
reg [7:0]  y_d3;
reg        de_d3;

always @(posedge clk) begin
    if (de_d2) begin
        new_r <= ({16'd0, r_d2} * current_gain) >> 8;
        new_g <= ({16'd0, g_d2} * current_gain) >> 8;
        new_b <= ({16'd0, b_d2} * current_gain) >> 8;
        y_d3  <= y_d2;
        de_d3 <= de_d2;
    end else begin
        new_r <= 24'd0;
        new_g <= 24'd0;
        new_b <= 24'd0;
        y_d3  <= 8'd0;
        de_d3 <= 1'b0;
    end
end

// --- 第 4 拍：执行加法、B&W转换与输出饱和截断 ---
// (完美补齐缺失的 1 拍延迟，使得 dout_rgb565 与 hdmi_ctrl 顶层中 sdram_d4 的原图做到像素级精准对齐！)
reg [23:0] bw_sum;
reg [23:0] bw_val;
reg [23:0] final_r, final_g, final_b;

always @(posedge clk) begin
    if (de_d3) begin
        bw_sum = new_r + new_g + new_b;
        bw_val = (bw_sum * 8'd85) >> 8; 

        // 暗部区域切换黑白 + 柔和静噪门
        if (y_d3 < 8'd40) begin
            if (bw_val < 8'd60) begin
                bw_val = bw_val >> 1; 
            end
            final_r = bw_val;
            final_g = bw_val;
            final_b = bw_val;
        end else begin
            final_r = new_r;
            final_g = new_g;
            final_b = new_b;
        end

        // 终极输出：增加硬件饱和截断保护，防止亮部溢出
        dout_rgb565[15:11] <= (final_r > 255) ? 5'h1F : final_r[7:3];
        dout_rgb565[10:5]  <= (final_g > 255) ? 6'h3F : final_g[7:2];
        dout_rgb565[4:0]   <= (final_b > 255) ? 5'h1F : final_b[7:3];
    end else begin
        dout_rgb565 <= 16'd0;
    end
end

endmodule