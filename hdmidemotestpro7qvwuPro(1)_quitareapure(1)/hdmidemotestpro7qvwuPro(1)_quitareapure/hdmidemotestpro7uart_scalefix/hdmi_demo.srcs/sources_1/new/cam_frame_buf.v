// cam_frame_buf.v — 跨时钟域安全翻转(Toggle)版本
module cam_frame_buf(
    input  wire        wr_clk,      // cam_pclk (约48MHz)
    input  wire        wr_en,       // pixel_valid
    input  wire [23:0] wr_data,
    input  wire        frame_start, // 帧起始，复位写地址和bank
    input  wire        href_fall,   // 行结束脉冲(由外部提供)

    input  wire        rd_clk,      // video_clk (25.175MHz)
    input  wire        rd_en,       // data_req
    output reg  [23:0] rd_data,
    input  wire        vs_start,    // 场起始，复位读地址

    output wire        buf_ready
);

parameter LINE_W = 640;

(* ramstyle = "block" *) reg [23:0] bank0 [0:LINE_W-1];
(* ramstyle = "block" *) reg [23:0] bank1 [0:LINE_W-1];

// ---- 写端 (wr_clk) ----
reg [9:0] wr_addr;
reg       wr_bank;
reg       line_toggle;  
reg       buf_ready_wr = 1'b0; // 初始化为0即可

always @(posedge wr_clk) begin
    if (frame_start) begin
        wr_addr      <= 10'd0;
        wr_bank      <= 1'b0;
        line_toggle  <= 1'b0;
        // buf_ready_wr <= 1'b0;   <==== 必须删掉这行！绝对不能在帧起始清零它！
    end else begin
        if (wr_en) begin
            if (wr_bank == 1'b0)
                bank0[wr_addr] <= wr_data;
            else
                bank1[wr_addr] <= wr_data;
            wr_addr <= (wr_addr == LINE_W-1) ? 10'd0 : wr_addr + 10'd1;
        end
        if (href_fall) begin
            wr_bank      <= ~wr_bank;
            wr_addr      <= 10'd0;
            line_toggle  <= ~line_toggle; 
            buf_ready_wr <= 1'b1;         // 第一行写完后，永远保持为1
        end
    end
end

// ---- 跨时钟域同步 (wr_clk -> rd_clk) ----
reg [2:0] lt_sync;
reg [1:0] br_sync;
always @(posedge rd_clk) begin
    lt_sync <= {lt_sync[1:0], line_toggle};
    br_sync <= {br_sync[0], buf_ready_wr};
end

// 检测翻转（无论是0变1还是1变0，都说明新的一行准备好了）
wire new_line_rdy = (lt_sync[2] ^ lt_sync[1]); 
assign buf_ready = br_sync[1];

// ---- 读端 (rd_clk) ----
reg [9:0] rd_addr;
reg       rd_bank;
reg       rd_en_d;
reg       pending_bank_switch;

always @(posedge rd_clk) begin
    rd_en_d <= rd_en; // 延迟一拍，用于边缘检测

    // 只要有新行写完，记录一个“待切换”标志
    if (new_line_rdy) begin
        pending_bank_switch <= 1'b1;
    end

    if (vs_start) begin
        rd_addr <= 10'd0;
        rd_bank <= ~wr_bank;
        pending_bank_switch <= 1'b0;
    end else begin
        // 当 rd_en 从 0 变 1 时，代表 HDMI 开始画新的一行
        if (rd_en && !rd_en_d) begin 
            rd_addr <= 10'd0; // 每行开头必须严格清零地址
            // 只有在每行开头，才允许切换画面 Bank
            if (pending_bank_switch) begin
                rd_bank <= ~wr_bank;
                pending_bank_switch <= 1'b0;
            end
        end 
        // 正在画线期间，只累加地址，绝不强行切换
        else if (rd_en && buf_ready) begin
            if (rd_bank == 1'b0)
                rd_data <= bank0[rd_addr];
            else
                rd_data <= bank1[rd_addr];
                
            rd_addr <= (rd_addr == LINE_W-1) ? 10'd0 : rd_addr + 10'd1;
        end
    end
end

endmodule