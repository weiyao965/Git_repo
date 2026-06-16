`timescale 1ns / 1ps
`include "global.v"

module ai_face_tracker #(
    // 假设输入的原图是 640x480，我们做 1/2 降采样，喂给 AI 的尺寸就是 320x240
    parameter SRC_W = 640,
    parameter SRC_H = 480,
    parameter AI_W  = 160,
    parameter AI_H  = 120
)(
    input  wire        clk_sys,     // 系统时钟 (用于 AI 计算，如 50M 或 100M)
    input  wire        rst_n,

    // 摄像头输入视频流 (接在摄像头采集模块之后)
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_de,
    input  wire [15:0] cam_data,    // RGB565

    // 输出的人脸框坐标 (映射回原图尺寸)
    output reg  [10:0] face_x,
    output reg  [10:0] face_y,
    output reg  [10:0] face_w,
    output reg  [10:0] face_h,
    output wire        face_valid
);

    // =========================================================
    // 1. 降采样与灰度化 (RGB565 -> 8bit Gray)
    // =========================================================
    wire [7:0] r8 = {cam_data[15:11], 3'b000};
    wire [7:0] g8 = {cam_data[10:5],  2'b00};
    wire [7:0] b8 = {cam_data[4:0],   3'b000};
    wire [7:0] gray = (r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29) >> 8;

    reg [10:0] pix_x, pix_y;
    reg        cam_vsync_d1;
    always @(posedge cam_pclk) cam_vsync_d1 <= cam_vsync;
    wire vsync_fall = cam_vsync_d1 & ~cam_vsync; // 帧结束标记

    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) begin
            pix_x <= 0; pix_y <= 0;
        end else if (cam_vsync) begin
            pix_x <= 0; pix_y <= 0;
        end else if (cam_de) begin
            if (pix_x == SRC_W - 1) begin
                pix_x <= 0;
                pix_y <= pix_y + 1;
            end else begin
                pix_x <= pix_x + 1;
            end
        end
    end

	// 1/4 降采样：只在 pix_x 和 pix_y 是 4 的倍数时提取
    wire write_en = cam_de && (pix_x[1:0] == 2'b00) && (pix_y[1:0] == 2'b00);
    wire [16:0] write_addr = (pix_y[10:2] * AI_W) + pix_x[10:2]; // BRAM 写入地址

	// =========================================================
    // 2. inferred 双口 BRAM (存放给 AI 计算的灰度小图)
    // =========================================================
	// 160 * 120 = 19200 字节的双口 BRAM
    // 强烈建议加上 ramstyle 原语强制推断 BRAM
    (* ramstyle = "block" *) reg [7:0] ai_frame_buf [0:AI_W*AI_H-1];
	
    // 摄像头的写端口 (跨时钟域写)
    always @(posedge cam_pclk) begin
        if (write_en) ai_frame_buf[write_addr] <= gray;
    end
	
	// 1. 显式声明总线宽度，防止隐式定义成 1-bit 导致地址被截断！
    wire [16:0] read_addr_w;
    reg  [7:0]  read_data_w;

    // 2. 推断双口 BRAM 的读端口 (AI 引擎的读时钟域)
    always @(posedge clk_sys) begin
        read_data_w <= ai_frame_buf[read_addr_w];
    end

// =========================================================
    // 3. 增强版：多尺度 AI 控制状态机 (Multi-Scale Engine)
    // =========================================================
    reg [4:0]  current_step;
    reg [10:0] cur_pic_w, cur_pic_h;
    reg        vj_go;
    wire       vj_ready;
    
    // 场同步下降沿检测 (一帧采集完毕，启动 AI)
    reg [2:0] vsync_cdc;
    always @(posedge clk_sys) vsync_cdc <= {vsync_cdc[1:0], cam_vsync};
    wire frame_start = vsync_cdc[2] && ~vsync_cdc[1];

    // 多尺度状态机
    reg [1:0] ms_state;
    localparam MS_IDLE = 2'd0;
    localparam MS_RUN  = 2'd1;
    localparam MS_NEXT = 2'd2;
    localparam MAX_STEP = 5'd4; // 开启 4 个尺度 (在 640x480 下检测 96, 192, 288, 384 大小的脸)

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            ms_state <= MS_IDLE;
            vj_go <= 1'b0;
            current_step <= 5'd1;
            cur_pic_w <= AI_W;
            cur_pic_h <= AI_H;
        end else begin
            case (ms_state)
                MS_IDLE: begin
                    if (frame_start) begin
                        current_step <= 5'd1;
                        cur_pic_w <= AI_W;       // 160
                        cur_pic_h <= AI_H;       // 120
                        vj_go <= 1'b1;           // 启动尺度 1
                        ms_state <= MS_RUN;
                    end else begin
                        vj_go <= 1'b0;
                    end
                end
                MS_RUN: begin
                    vj_go <= 1'b0; // 撤销启动脉冲
                    if (vj_ready) ms_state <= MS_NEXT; // 当前尺度扫描完成
                end
                MS_NEXT: begin
                    if (current_step < MAX_STEP) begin
                        current_step <= current_step + 1'b1;
                        
                        // 硬件中无需除法器，直接用常量分配计算下一个尺度的长宽边界
                        if (current_step == 1) begin cur_pic_w <= AI_W/2; cur_pic_h <= AI_H/2; end
                        if (current_step == 2) begin cur_pic_w <= AI_W/3; cur_pic_h <= AI_H/3; end
                        if (current_step == 3) begin cur_pic_w <= AI_W/4; cur_pic_h <= AI_H/4; end
                        
                        vj_go <= 1'b1; // 启动下一个尺度
                        ms_state <= MS_RUN;
                    end else begin
                        ms_state <= MS_IDLE; // 所有尺度跑完，睡眠等待下一帧
                    end
                end
                default: ms_state <= MS_IDLE;
            endcase
        end
    end

    // =========================================================
    // 4. VJ 流水线 (接入动态多尺度参数)
    // =========================================================
    wire [`W1P*`W_SIZE-1:0] pixels_w;
    wire                    pixels_en_w;
    wire                    vj_init_w;
    wire                    next_col_w;
    wire                    cascade_end_w;
    wire                    col_end_w;
    wire [`W_PW:0]          vj_x_out;
    wire [`W_PH:0]          vj_y_out;
    wire                    vj_face_detected;
	// 【核心修复】：原版 step 带有 1 位小数，必须左移 1 位 (乘以 2)
    // current_step=1 -> 传入2(1.0x); current_step=2 -> 传入4(2.0x)
    wire [4:0] actual_vj_step = current_step << 1;
	
    vj_fetch u_vj_fetch(
        .clk                (clk_sys),
        .rstn               (rst_n),
        .pic_width          (cur_pic_w),    // 𑐠动态输入当前尺度的宽
        .pic_height         (cur_pic_h),    // 𑐠动态输入当前尺度的高
        .step               (actual_vj_step), // 𑐠传入左移修正后的真实步长
        .vj_fetch_go        (vj_go),
        .pixels             (pixels_w),
        .pixels_en          (pixels_en_w),
        .vj_row_init        (vj_init_w),
        .ready_for_next_col (next_col_w),
        .cascade_end        (cascade_end_w),
        .col_end            (col_end_w),
        .vj_col             (vj_x_out),
        .vj_row             (vj_y_out),
        .vj_frame_ready     (vj_ready),
        .aa_frame_buf       (read_addr_w),
        .cena_frame_buf     (), 
        .qa_frame_buf       (read_data_w),
        .face_detected      (vj_face_detected)
    );

    vj u_vj (
        .clk                (clk_sys),
        .rstn               (rst_n),
        .pic_width          (cur_pic_w),    // 𑐠同样需要动态宽高
        .pic_height         (cur_pic_h),
        .init               (vj_init_w),
        .pixel_i            (pixels_w),
        .pixel_i_en         (pixels_en_w),
        .ready_for_next_col (next_col_w),
        .cascade_ready      (cascade_end_w),
        .col_end            (col_end_w),
        .face_detected      (vj_face_detected)
    );

	// =========================================================
    // 5. 坐标恢复与帧同步稳定锁存
    // =========================================================
    reg face_valid_reg;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            face_x <= 0; face_y <= 0; face_w <= 0; face_h <= 0;
            face_valid_reg <= 1'b0;
        end else if (frame_start) begin  
            // 每一帧画面重新开始扫描时，清除上一帧的红框状态
            face_valid_reg <= 1'b0;
        end else if (vj_face_detected && !face_valid_reg) begin
            // 𑐠多尺度终极映射算法：
            // BRAM真实坐标 = 模型输出(vj_out) * 缩放步进(current_step)
            // 原图绝对坐标 = BRAM真实坐标 * 4倍降采样恢复
            face_x <= (vj_x_out * current_step) << 2;
            face_y <= (vj_y_out * current_step) << 2;
            
            // 探测框尺寸 = (24 * 步进) * 4
            face_w <= (24 * current_step) << 2;
            face_h <= (24 * current_step) << 2;
            
            face_valid_reg <= 1'b1;
        end
    end

    // 将稳定的电平信号交给 HDMI 模块画框
    assign face_valid = face_valid_reg;

endmodule