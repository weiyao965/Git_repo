`timescale 1ns / 1ps

module hdmi_ctrl(
    input           sys_clk,
    input           sys_rst_n,

    input           cmos_key1, 
    input           cmos_key2, 
    input           cmos_key3, 
    output          cmos_led1,  
    output          cmos_led2,  
    output          cmos_led3,  
    output          cmos_led4,  

    input           uart_rxd,   
    output          uart_txd,   

    output          hdmi_clk,
    output  [23:0]  hdmi_d,
    output          hdmi_de,
    output          hdmi_hs,
    output          hdmi_vs,
    output          hdmi_rst_n,
    inout           hdmi_scl,
    inout           hdmi_sda,

    output wire     cmos_xclk,
    output wire     cmos_rst_n,
    output wire     cmos_pwdn,
    input  wire     cmos_pclk,
    input  wire     cmos_href,
    input  wire     cmos_vsync,
    input  wire [7:0] cmos_d,
    inout  wire     cmos_scl,
    inout  wire     cmos_sda,
    
    output wire         sdram_clk,
    output wire         sdram_cke,
    output wire         sdram_cs_n,
    output wire         sdram_ras_n,
    output wire         sdram_cas_n,
    output wire         sdram_we_n,
    output wire [1:0]   sdram_bank,
    output wire [12:0]  sdram_addr,
    inout  wire [15:0]  sdram_dq
);

// =========================================================
// 1. 时钟与复位
// =========================================================
wire    video_clk;
wire    clk_100mhz;
wire    pll_locked;
wire    clk_100mhz_shift;

assign hdmi_clk   = video_clk;
assign hdmi_rst_n = pll_locked;

clk_gen clk_gen_inst(
    .areset  (~sys_rst_n), 
    .inclk0  (sys_clk   ),
    .c0      (clk_100mhz),
    .c1      (video_clk ),        
    .c2      (clk_100mhz_shift),
    .locked  (pll_locked)
);
wire rst_n = sys_rst_n & pll_locked;

// =========================================================
// 2. 双源控制：按键与串口
// =========================================================
wire key1_pulse, key2_pulse, key3_pulse;
key_debounce u_key1(.clk(clk_100mhz), .rst_n(rst_n), .key_in(cmos_key1), .key_pulse(key1_pulse));
key_debounce u_key2(.clk(clk_100mhz), .rst_n(rst_n), .key_in(cmos_key2), .key_pulse(key2_pulse));
key_debounce u_key3(.clk(clk_100mhz), .rst_n(rst_n), .key_in(cmos_key3), .key_pulse(key3_pulse));

wire [7:0]  uart_rx_data; wire uart_rx_flag; wire uart_cmd_valid;
wire [7:0]  uart_cmd_type; wire [15:0] uart_cmd_data;

uart_rx #(.CLK_FREQ(100_000_000), .UART_BPS(1000000)) u_uart_rx (
    .sys_clk(clk_100mhz), .sys_rst_n(rst_n), .rx(uart_rxd), .po_data(uart_rx_data), .po_flag(uart_rx_flag)
);
uart_cmd_parser u_parser (
    .clk(clk_100mhz), .rst_n(rst_n), .rx_data(uart_rx_data), .rx_flag(uart_rx_flag),
    .cmd_valid(uart_cmd_valid), .cmd_type(uart_cmd_type), .cmd_data(uart_cmd_data)
);

// Python 触发抓拍 (0xC1)
reg py_cap_toggle;
always @(posedge clk_100mhz) begin
    if (!rst_n) py_cap_toggle <= 1'b0;
    else if (uart_rx_flag && uart_rx_data == 8'hC1) py_cap_toggle <= ~py_cap_toggle;
end
reg [2:0] py_cap_sync;
always @(posedge cmos_pclk) py_cap_sync <= {py_cap_sync[1:0], py_cap_toggle};
wire py_cap_pulse = py_cap_sync[2] ^ py_cap_sync[1]; 

// Python 触发回传 (0xC2)
wire py_tx_pulse = (uart_rx_flag && uart_rx_data == 8'hC2);

// =========================================================
// 【终极锁定】：死锁缩放系数，彻底杜绝4分屏和串口干扰！
// =========================================================
wire [12:0] scale_step = 13'd256; 
wire        rot_180_en = 1'b0;    
wire        menu_state = 1'b0;    
wire [3:0]  select_idx = 4'd0;    

wire key1_pressed = ~cmos_key1; wire key2_pressed = ~cmos_key2; wire key3_pressed = ~cmos_key3;
assign cmos_led4 = 1'b0; assign cmos_led3 = 1'b0; 
assign cmos_led2 = 1'b0; assign cmos_led1 = 1'b0; 

// =========================================================
// 4. 摄像头时钟与初始化
// =========================================================
wire cam_xclk_w;
cam_clk_gen cam_clk_gen_inst(.clk_in(clk_100mhz), .rst_n(pll_locked), .cam_xclk(cam_xclk_w));
assign cmos_xclk = cam_xclk_w;

reg [23:0] cam_rst_cnt; reg cam_rst_n_reg; reg cam_pwdn_reg;
always @(posedge clk_100mhz or negedge pll_locked) begin
    if (!pll_locked) begin cam_rst_cnt <= 24'd0; cam_rst_n_reg <= 1'b0; cam_pwdn_reg <= 1'b1; end 
    else begin
        if (cam_rst_cnt < 24'd1_000_000) begin cam_rst_cnt <= cam_rst_cnt + 1'b1; cam_pwdn_reg <= 1'b1; cam_rst_n_reg <= 1'b0; end 
        else if (cam_rst_cnt < 24'd2_000_000) begin cam_rst_cnt <= cam_rst_cnt + 1'b1; cam_pwdn_reg <= 1'b0; cam_rst_n_reg <= 1'b0; end 
        else if (cam_rst_cnt < 24'd4_000_000) begin cam_rst_cnt <= cam_rst_cnt + 1'b1; cam_pwdn_reg <= 1'b0; cam_rst_n_reg <= 1'b1; end 
        else begin cam_rst_n_reg <= 1'b1; cam_pwdn_reg <= 1'b0; end
    end
end
assign cmos_rst_n = cam_rst_n_reg; assign cmos_pwdn  = cam_pwdn_reg;

wire [9:0]  cam_lut_index; wire [31:0] cam_lut_data; wire cam_init_done;
ov5640_init ov5640_init_inst(.rot_180_en(rot_180_en), .lut_index (cam_lut_index), .lut_data  (cam_lut_data));
cam_i2c_config cam_i2c_cfg(.rst(~cam_rst_n_reg), .clk(clk_100mhz), .clk_div_cnt(16'd249), .lut_index(cam_lut_index), .lut_data(cam_lut_data), .init_done(cam_init_done), .i2c_scl(cmos_scl), .i2c_sda(cmos_sda));

// =========================================================
// 5. 前级输入流水线与缩放
// =========================================================
wire pipeline_rst_n = rst_n & cam_init_done;
wire [15:0] cap_pixel_data; wire cap_pixel_valid;
cam_capture cam_capture_inst(.sys_rst_n(pipeline_rst_n), .cam_pclk(cmos_pclk), .cam_href(cmos_href), .cam_vsync(cmos_vsync), .cam_data(cmos_d), .pixel_data(cap_pixel_data), .pixel_valid(cap_pixel_valid));

wire [15:0] scaled_pixel_data; wire scaled_pixel_valid;
video_scaler_nn video_scaler_nn_inst (.clk(cmos_pclk), .rst_n(pipeline_rst_n), .scale_step(scale_step), .cam_vsync(cmos_vsync), .cam_href(cmos_href), .cam_data_in(cap_pixel_data), .cam_data_valid(cap_pixel_valid), .scaler_data_out(scaled_pixel_data), .scaler_valid_out(scaled_pixel_valid), .rot_180_en(rot_180_en));

// =========================================================
// 6. UART 抓图与 AI 诊断锁存 (无短路稳定版)
// =========================================================
wire [7:0] mock_g = {scaled_pixel_data[10:5], 2'b0};

reg [10:0] mock_x;
reg [10:0] mock_y;
always @(posedge cmos_pclk) begin
    if (!pipeline_rst_n || cmos_vsync) begin
        mock_x <= 0;
        mock_y <= 0;
    end else if (scaled_pixel_valid) begin
        if (mock_x == 11'd639) begin  // 【必须改回 639】：缩放器输出的是640像素流，绝不能在159斩断！
            mock_x <= 0; 
			mock_y <= mock_y + 1;
        end else begin
            mock_x <= mock_x + 1;
        end
    end
end

(* ramstyle = "block" *) reg [7:0] dbg_bram [0:19199];
reg [14:0] dbg_wr_addr;
reg dbg_capturing;

always @(posedge cmos_pclk) begin
    if (!pipeline_rst_n) begin
        dbg_wr_addr <= 0;
        dbg_capturing <= 0;
    end else begin
        if (key1_pulse || py_cap_pulse) dbg_capturing <= 1;

        if (dbg_capturing && scaled_pixel_valid) begin
            if (mock_x[1:0] == 2'b00 && mock_y[1:0] == 2'b00) begin
                dbg_bram[dbg_wr_addr] <= mock_g;
                if (dbg_wr_addr == 15'd19199) begin
                    dbg_wr_addr <= 0; dbg_capturing <= 0; 
                end else begin
                    dbg_wr_addr <= dbg_wr_addr + 1;
                end
            end
        end
    end
end

wire [10:0] face_x, face_y, face_w, face_h;
wire        face_valid;

reg [10:0] dbg_face_x, dbg_face_y, dbg_face_w, dbg_face_h;
reg        dbg_face_valid;

always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        dbg_face_valid <= 0;
    end else if (key1_pulse || py_cap_pulse) begin
        dbg_face_valid <= face_valid;
        dbg_face_x <= face_x;
        dbg_face_y <= face_y;
        dbg_face_w <= face_w;
        dbg_face_h <= face_h;
    end
end

reg [14:0] tx_rd_addr;
reg [11:0] tx_wait_cnt;
reg tx_sending;
reg [7:0] uart_tx_data;
reg uart_tx_flag;

always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        tx_sending <= 0; tx_rd_addr <= 0; tx_wait_cnt <= 0; uart_tx_flag <= 0;
    end else begin
        if ((key2_pulse || py_tx_pulse) && !dbg_capturing) begin
            tx_sending <= 1; tx_rd_addr <= 0; tx_wait_cnt <= 0;
        end
        uart_tx_flag <= 0; 

        if (tx_sending) begin
            if (tx_wait_cnt == 0) begin
                if (tx_rd_addr < 15'd19200)
                    uart_tx_data <= dbg_bram[tx_rd_addr]; 
                else if (tx_rd_addr == 15'd19200)
                    uart_tx_data <= dbg_face_valid ? 8'h01 : 8'h00; 
                else if (tx_rd_addr == 15'd19201)
                    uart_tx_data <= dbg_face_x[9:2]; 
                else if (tx_rd_addr == 15'd19202)
                    uart_tx_data <= dbg_face_y[9:2]; 
                else if (tx_rd_addr == 15'd19203)
                    uart_tx_data <= dbg_face_w[9:2]; 
                else if (tx_rd_addr == 15'd19204)
                    uart_tx_data <= dbg_face_h[9:2]; 

                uart_tx_flag <= 1; tx_wait_cnt <= 1200; 
                
                if (tx_rd_addr == 15'd19204) begin 
                    tx_sending <= 0; 
                end else begin
                    tx_rd_addr <= tx_rd_addr + 1;
                end
            end else begin
                tx_wait_cnt <= tx_wait_cnt - 1;
            end
        end
    end
end

uart_tx #(
    .CLK_FREQ(100_000_000), 
    .UART_BPS(1000000)
) u_uart_tx_dbg (
    .sys_clk(clk_100mhz), .sys_rst_n(rst_n), .pi_data(uart_tx_data), .pi_flag(uart_tx_flag), .tx(uart_txd)       
);

// =========================================================
// 7. AI 人脸追踪协处理器 
// =========================================================
ai_face_tracker #(
    .SRC_W(640), .SRC_H(480), .AI_W(160), .AI_H(120)
) u_ai_face_tracker (
    .clk_sys(video_clk), .rst_n(rst_n), .cam_pclk(cmos_pclk), .cam_vsync(cmos_vsync),    
    .cam_de(scaled_pixel_valid), .cam_data(scaled_pixel_data),
    .face_x(face_x), .face_y(face_y), .face_w(face_w), .face_h(face_h),
    .face_valid(face_valid) // 连接真实的 AI 引擎输出！
);

// =========================================================
// 8. SDRAM 帧缓存 
// =========================================================
wire sdram_init_done; wire [15:0] sdram_rd_data; wire cam_rd_en_w;
wire wr_flush = ~rst_n | ~cam_init_done; 

sdram_top sdram_top_inst(
    .I_ref_clk(clk_100mhz), .I_out_clk(clk_100mhz_shift), .I_rst_n(rst_n),              
    .I_fifo_wr_clk(cmos_pclk), .I_fifo_wr_req(scaled_pixel_valid), .I_fifo_wr_data(scaled_pixel_data), .I_fifo_wr_load(wr_flush),          
    .I_wr_burst(10'd128), .I_wr_saddr(24'd0), .I_wr_eaddr(24'd307200),        
    .I_fifo_rd_clk(video_clk), .I_fifo_rd_req(cam_rd_en_w), .O_fifo_rd_data(sdram_rd_data), .I_fifo_rd_load(~rst_n),              
    .I_rd_burst(10'd128), .I_rd_saddr(24'd0), .I_rd_eaddr(24'd307200),
    .I_sdram_rd_valid(1'b1), .I_sdram_pingpang_en(1'b1), .O_sdram_init_done(sdram_init_done),
    .O_sdram_clk(sdram_clk), .O_sdram_cke(sdram_cke), .O_sdram_cs_n(sdram_cs_n), .O_sdram_ras_n(sdram_ras_n), .O_sdram_cas_n(sdram_cas_n), .O_sdram_we_n(sdram_we_n), .O_sdram_bank(sdram_bank), 
    .O_sdram_addr(sdram_addr), .IO_sdram_dq(sdram_dq), .rot_180_en(rot_180_en)
);

// =========================================================
// 9. HDMI 视频驱动基准生成
// =========================================================
wire        video_hs, video_vs, video_de; wire [10:0] pixel_xpos, pixel_ypos;
wire        data_req; wire [23:0] pixel_data_w;
wire [7:0] cam_R = {sdram_rd_data[15:11], 3'b000};
wire [7:0] cam_G = {sdram_rd_data[10:5],  2'b00};
wire [7:0] cam_B = {sdram_rd_data[4:0],   3'b000};
wire [23:0] buf_pixel_data = {cam_R, cam_G, cam_B};

hdmi_display hdmi_display_inst(
    .hdmi_clk(video_clk), .rst_n(rst_n), .data_req(data_req), .pixel_xpos(pixel_xpos), .pixel_ypos(pixel_ypos),
    .pixel_data(pixel_data_w), .cam_pixel_data(buf_pixel_data),  
    .cam_buf_ready(sdram_init_done), .cam_rd_en(cam_rd_en_w), .dbg_vsync(cmos_vsync), .dbg_href(cmos_href)
);

wire drv_hs, drv_vs, drv_de; wire [23:0] drv_rgb;
hdmi_driver hdmi_driver_u(
    .pixel_clk(video_clk), .sys_rst_n(rst_n),      
    .pixel_data(pixel_data_w), .pixel_xpos(pixel_xpos), .pixel_ypos(pixel_ypos),
    .data_req(data_req), .video_hs(drv_hs), .video_vs(drv_vs), .video_de(drv_de), .video_rgb(drv_rgb) 
);

// =========================================================
// 10. 深层打拍与对齐流水线 
// =========================================================
reg hs_d1, hs_d2, hs_d3, hs_d4, hs_d5, hs_d6;
reg vs_d1, vs_d2, vs_d3, vs_d4, vs_d5, vs_d6;
reg de_d1, de_d2, de_d3, de_d4, de_d5, de_d6;
reg [23:0] rgb_d1, rgb_d2, rgb_d3, rgb_d4, rgb_d5, rgb_d6;

reg [10:0] xpos_d1, xpos_d2, xpos_d3, xpos_d4, xpos_d5, xpos_d6;
reg [10:0] ypos_d1, ypos_d2, ypos_d3, ypos_d4, ypos_d5, ypos_d6;

always @(posedge video_clk) begin
    hs_d1 <= drv_hs; hs_d2 <= hs_d1; hs_d3 <= hs_d2; hs_d4 <= hs_d3; hs_d5 <= hs_d4; hs_d6 <= hs_d5;
    vs_d1 <= drv_vs; vs_d2 <= vs_d1; vs_d3 <= vs_d2; vs_d4 <= vs_d3; vs_d5 <= vs_d4; vs_d6 <= vs_d5;
    de_d1 <= drv_de; de_d2 <= de_d1; de_d3 <= de_d2; de_d4 <= de_d3; de_d5 <= de_d4; de_d6 <= de_d5;
    rgb_d1 <= drv_rgb; rgb_d2 <= rgb_d1; rgb_d3 <= rgb_d2; rgb_d4 <= rgb_d3; rgb_d5 <= rgb_d4; rgb_d6 <= rgb_d5;

    xpos_d1 <= pixel_xpos; xpos_d2 <= xpos_d1; xpos_d3 <= xpos_d2; xpos_d4 <= xpos_d3; xpos_d5 <= xpos_d4; xpos_d6 <= xpos_d5;
    ypos_d1 <= pixel_ypos; ypos_d2 <= ypos_d1; ypos_d3 <= ypos_d2; ypos_d4 <= ypos_d3; ypos_d5 <= ypos_d4; ypos_d6 <= ypos_d5;
end

// =========================================================
// 11. 终极多路复用器、硬裁剪与 OSD 算法
// =========================================================
reg        hdmi_hs_out, hdmi_vs_out, hdmi_de_out;
reg [23:0] hdmi_rgb_out;

always @(posedge video_clk) begin
    hdmi_hs_out <= hs_d6; hdmi_vs_out <= vs_d6;               
    hdmi_de_out <= de_d6; hdmi_rgb_out <= rgb_d6;
end

reg [10:0] final_x_cnt;
always @(posedge video_clk) begin
    if (!hdmi_de_out) final_x_cnt <= 11'd0;
    else final_x_cnt <= final_x_cnt + 1'b1;
end

wire [10:0] curr_x = xpos_d6;
wire [10:0] curr_y = ypos_d6;

// 固定引导框
wire [10:0] roi_x = 11'd160;
wire [10:0] roi_y = 11'd80;
wire [10:0] roi_w = 11'd320;
wire [10:0] roi_h = 11'd320;

wire draw_roi_x = (curr_x >= roi_x) && (curr_x <= roi_x + roi_w) &&
                  ((curr_x < roi_x + 3) || (curr_x > roi_x + roi_w - 3)); 
wire draw_roi_y = (curr_y >= roi_y) && (curr_y <= roi_y + roi_h) &&
                  ((curr_y < roi_y + 3) || (curr_y > roi_y + roi_h - 3));

wire is_roi_edge = (draw_roi_x && (curr_y >= roi_y) && (curr_y <= roi_y + roi_h)) ||
                   (draw_roi_y && (curr_x >= roi_x) && (curr_x <= roi_x + roi_w));
                   
// 【连接真实的 AI 动态输出坐标】
wire [10:0] mapped_face_x = face_x; 
wire [10:0] mapped_face_y = face_y;
wire [10:0] mapped_face_w = face_w;
wire [10:0] mapped_face_h = face_h;

wire draw_face_x = (curr_x >= mapped_face_x) && (curr_x <= mapped_face_x + mapped_face_w) &&
                   ((curr_x < mapped_face_x + 3) || (curr_x > mapped_face_x + mapped_face_w - 3));
wire draw_face_y = (curr_y >= mapped_face_y) && (curr_y <= mapped_face_y + mapped_face_h) &&
                   ((curr_y < mapped_face_y + 3) || (curr_y > mapped_face_y + mapped_face_h - 3));

wire is_face_edge = face_valid && (
                   (draw_face_x && (curr_y >= mapped_face_y) && (curr_y <= mapped_face_y + mapped_face_h)) ||
                   (draw_face_y && (curr_x >= mapped_face_x) && (curr_x <= mapped_face_x + mapped_face_w))
                   );

assign hdmi_hs = hdmi_hs_out;
assign hdmi_vs = hdmi_vs_out;
assign hdmi_de = hdmi_de_out;

// 【颜色动态切换逻辑】当检测到人脸时，大检测框也会变成红色
wire [23:0] roi_color = face_valid ? 24'hFF0000 : 24'h00FF00;

// 【像素渲染优先级】小红框优先 -> 大判定框 -> 摄像头原画
assign hdmi_d  = (hdmi_de_out && (final_x_cnt < 11'd634)) ? 
                 (is_face_edge ? 24'hFF0000 : 
                 (is_roi_edge  ? roi_color  : 
                 hdmi_rgb_out)) : 
                 24'h000000;
                 
// =========================================================
// 12. HDMI SII9134 I2C 初始化
// =========================================================
wire [9:0] lut_index;
wire [31:0] lut_data;
i2c_config i2c_config_m0(.rst(~pll_locked), .clk(clk_100mhz), .clk_div_cnt(16'd499), .i2c_addr_2byte(1'b0), .lut_index(lut_index), .lut_dev_addr(lut_data[31:24]), .lut_reg_addr(lut_data[23:8]), .lut_reg_data(lut_data[7:0]), .error(), .done(), .i2c_scl(hdmi_scl), .i2c_sda(hdmi_sda));
lut_sil9134 lut_sil9134_m0(.lut_index(lut_index), .lut_data(lut_data));

endmodule