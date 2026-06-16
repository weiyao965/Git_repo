`timescale 1ns / 1ps

module video_scaler_nn (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [12:0] scale_step, // 来自上位机/按键的步进参数 (100MHz 异步域)

    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [15:0] cam_data_in,
    input  wire        cam_data_valid,

    output reg  [15:0] scaler_data_out,
    output reg         scaler_valid_out,
    
    input  wire        rot_180_en
);

    // =========================================================
    // 0. 步调器 (Pacing Generator) 
    // 原汁原味保留：限制最高输出速率为 12MHz，防止撑爆 FIFO
    // =========================================================
    reg pace_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pace_en <= 1'b0;
        else        pace_en <= ~pace_en; 
    end

    // =========================================================
    // 1. 【核心修复 1】跨时钟域两级同步器 (CDC Synchronizer)
    // 彻底消除拖拽滑块时的总线亚稳态毛刺
    // =========================================================
    reg [12:0] scale_step_sync1;
    reg [12:0] scale_step_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scale_step_sync1 <= 13'd256;
            scale_step_sync2 <= 13'd256;
        end else begin
            scale_step_sync1 <= scale_step;       // 第一拍跨域缓冲
            scale_step_sync2 <= scale_step_sync1; // 第二拍消除亚稳态
        end
    end

    // 绝对帧同步锁存 (使用同步后的干净数据)
    reg [12:0] safe_step;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) safe_step <= 13'd256;
        else if (cam_vsync) safe_step <= scale_step_sync2; // 【修复】改为采样 sync2
    end

    // 2. 乒乓 BRAM 缓存两行源图数据 (完全原版)
    (* ramstyle = "block" *) reg [15:0] bank0 [0:639];
    (* ramstyle = "block" *) reg [15:0] bank1 [0:639];

    reg [10:0] x_src, y_src;
    reg wr_bank;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            x_src <= 11'd0; y_src <= 11'd0; wr_bank <= 1'b0; 
        end
        else if (cam_vsync) begin 
            x_src <= 11'd0; y_src <= 11'd0; wr_bank <= 1'b0; 
        end
        else if (cam_data_valid) begin
            if (wr_bank == 1'b0) bank0[x_src] <= cam_data_in;
            else                 bank1[x_src] <= cam_data_in;
            
            if (x_src == 11'd639) begin
                x_src <= 11'd0;
                y_src <= y_src + 1'b1;
                wr_bank <= ~wr_bank;
            end else begin
                x_src <= x_src + 1'b1;
            end
        end
    end

    // =========================================================
    // 3. 目标坐标系严谨的有符号数映射 (修复符号位丢失Bug)
    // =========================================================
    reg [10:0] x_dst, y_dst;
    
    wire signed [13:0] s_step = {1'b0, safe_step};

    // --- Y 坐标映射 ---
    wire signed [13:0] s_y_dst = {3'b000, y_dst};
    wire signed [13:0] y_dst_offset = s_y_dst - 14'sd240;
    wire signed [27:0] y_src_scaled = y_dst_offset * s_step;
    // 用 [27:8] 手动截断取代 >>> 8，并强制声明为有符号数，绝杀正负反转
    wire signed [13:0] y_src_mapped = 14'sd240 + $signed(y_src_scaled[27:8]);
    
    wire y_is_black = (y_src_mapped < 0 || y_src_mapped > 479);
    wire [10:0] y_req = (y_src_mapped < 0) ? 11'd0 : y_src_mapped[10:0];

    // --- X 坐标映射 ---
    wire signed [13:0] s_x_dst = {3'b000, x_dst};
    wire signed [13:0] x_dst_offset = s_x_dst - 14'sd320;
    wire signed [27:0] x_src_scaled = x_dst_offset * s_step;
    // 同理保护 X 方向坐标
    wire signed [13:0] x_src_mapped = 14'sd320 + $signed(x_src_scaled[27:8]);
    
    wire x_is_black = (x_src_mapped < 0 || x_src_mapped > 639);
    wire [9:0] x_req = (x_src_mapped < 0) ? 10'd0 :
                       (x_src_mapped > 639) ? 10'd639 : x_src_mapped[9:0];

    // =========================================================
    // 4. 状态机 
    // 加入 Flush 救砖补齐，拒绝中途太监
    // =========================================================
    localparam S_IDLE  = 2'd0;
    localparam S_CHECK = 2'd1;
    localparam S_BURST = 2'd2;
    reg [1:0] state;

    // 标志旗：VSYNC来了，但我们还没输出完 480 行，拉起红灯！
    reg flush_mode;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) flush_mode <= 1'b0;
        else if (cam_vsync && y_dst > 0 && y_dst < 11'd480) flush_mode <= 1'b1;
        else if (y_dst == 11'd480) flush_mode <= 1'b0; // 补齐完成，降下红灯
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            y_dst <= 11'd0;
            x_dst <= 11'd0;
        end 
        // 只有当 (VSYNC 高电平) 且 (没在补齐) 且 (已经完美归零)，才乖乖趴在原地等新帧
        else if (cam_vsync && !flush_mode && y_dst == 11'd0) begin
            state <= S_CHECK;
            y_dst <= 11'd0;
            x_dst <= 11'd0;
        end 
        else begin
            case(state)
                S_CHECK: begin
                    if (y_dst == 11'd480) begin
                        state <= S_IDLE;
                        y_dst <= 11'd0; // 发满 480 行后，自动重置回 0
                    end else if (y_is_black || y_src > y_req || flush_mode) begin
                        state <= S_BURST; 
                    end
                end
                
                S_BURST: begin
                    // 正常情况用 12MHz 限速。如果是救砖补齐(flush_mode)，以 24MHz 全速狂飙！
                    if (pace_en || flush_mode) begin 
                        if (x_dst == 11'd639) begin
                            x_dst <= 11'd0;
                            y_dst <= y_dst + 1'b1;
                            state <= S_CHECK;
                        end else begin
                            x_dst <= x_dst + 1'b1;
                        end
                    end
                end
                
                S_IDLE: state <= S_IDLE;

                // ====================================================
                // 【核心修复 2】状态机致命死锁救砖：添加 default
                // 防止亚稳态或硬件杂讯导致状态跳入 2'b11 永远卡死的情况
                // ====================================================
                default: begin
                    state <= S_IDLE;
                    y_dst <= 11'd0;
                    x_dst <= 11'd0;
                end
            endcase
        end
    end

    // =========================================================
    // 5. 数据对齐与黑边渲染流水线
    // =========================================================
    reg        valid_p1;
    reg        is_black_p1;
    reg        bank_sel_p1;
    reg [15:0] b_data_0, b_data_1;
    
    // 帧锁存器：确保水平翻转只在帧首生效，绝不中途撕裂画面！
    reg rot_180_latched;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rot_180_latched <= 1'b0;
        else if (cam_vsync) rot_180_latched <= rot_180_en;
    end
    
    // 水平翻转算法：严格使用锁存后的 rot_180_latched，保证整帧状态一致！
    wire [9:0] actual_x_req = rot_180_latched ? (10'd639 - x_req) : x_req;
    
    always @(posedge clk) begin
        b_data_0 <= bank0[actual_x_req]; 
        b_data_1 <= bank1[actual_x_req]; 
        
        valid_p1 <= (state == S_BURST) && (pace_en || flush_mode); 
        
        // 在强制补齐期间，统统输出纯黑像素，不读内存，防错乱！
        is_black_p1 <= y_is_black || x_is_black || flush_mode;
        bank_sel_p1 <= y_req[0]; 
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scaler_valid_out <= 1'b0;
            scaler_data_out  <= 16'd0;
        end else begin
            scaler_valid_out <= valid_p1;
            if (is_black_p1) 
                scaler_data_out <= 16'h0000;
            else 
                scaler_data_out <= bank_sel_p1 ? b_data_1 : b_data_0;
        end
    end

endmodule