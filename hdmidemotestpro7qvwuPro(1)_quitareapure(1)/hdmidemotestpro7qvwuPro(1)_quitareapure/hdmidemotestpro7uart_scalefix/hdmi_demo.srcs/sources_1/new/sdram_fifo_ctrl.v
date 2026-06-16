// sdram_fifo_ctrl.v — 完美同步版，消除两步翻转与花屏撕裂
module sdram_fifo_ctrl(
    input   wire    I_ref_clk,
    input   wire    I_rst_n,

    // 写端口: 外部-->FIFO
    input   wire    I_fifo_wr_clk,
    input   wire    I_fifo_wr_req,
    input   wire    [15:0]I_fifo_wr_data,
    input   wire    [23:0]I_wr_saddr,
    input   wire    [23:0]I_wr_eaddr,
    input   wire    [9:0]I_wr_brust,
    input   wire    I_fifo_wr_load,     

    // wr_fifo: FIFO(写)-->SDRAM(读)
    output  reg     O_sdram_wr_req,
    input   wire    I_sdram_wr_ack,
    output  reg     [23:0]O_sdram_wr_addr,
    output  wire    [15:0]O_sdram_wr_data,

    // rd_fifo: SDRAM(写)-->FIFO(读)
    output  reg     O_sdram_rd_req,
    input   wire    I_sdram_rd_ack,
    output  reg     [23:0]O_sdram_rd_addr,
    input   wire    [15:0]I_sdram_rd_data,

    // 读端口: FIFO-->外部
    input   wire    I_fifo_rd_clk,
    input   wire    I_fifo_rd_req,
    output  wire    [15:0]O_fifo_rd_data,
    input   wire    [23:0]I_rd_saddr,
    input   wire    [23:0]I_rd_eaddr,
    input   wire    [9:0]I_rd_brust,
    input   wire    I_fifo_rd_load,     

    // sdram
    input   wire    I_sdram_init_done,
    input   wire    I_sdram_rd_valid,
    input   wire    I_sdram_pingpang_en,
    
    input   wire    rot_180_en          
);

    reg fifo_wr_load_r1, fifo_wr_load_r2;
    reg fifo_rd_load_r1, fifo_rd_load_r2;
    reg sdram_wr_ack1, sdram_wr_ack2;
    reg sdram_rd_ack1, sdram_rd_ack2;
    reg sdram_rd_valid1, sdram_rd_valid2;

    wire fifo_wr_load_p = (~fifo_wr_load_r2) & fifo_wr_load_r1;  
    wire fifo_rd_load_p = (~fifo_rd_load_r2) & fifo_rd_load_r1;
    wire sdram_wr_ack_n = sdram_wr_ack2 & (~sdram_wr_ack1);       
    wire sdram_rd_ack_n = sdram_rd_ack2 & (~sdram_rd_ack1);
    wire [9:0] wr_fifo_use, rd_fifo_use;

    // Bank切换与时序同步
    reg bank_en, bank_flag;
    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            fifo_wr_load_r1 <= 0; fifo_wr_load_r2 <= 0;
            fifo_rd_load_r1 <= 0; fifo_rd_load_r2 <= 0;
            sdram_wr_ack1 <= 0; sdram_wr_ack2 <= 0;
            sdram_rd_ack1 <= 0; sdram_rd_ack2 <= 0;
            sdram_rd_valid1 <= 0; sdram_rd_valid2 <= 0;
        end else begin
            fifo_wr_load_r1 <= I_fifo_wr_load; fifo_wr_load_r2 <= fifo_wr_load_r1;
            fifo_rd_load_r1 <= I_fifo_rd_load; fifo_rd_load_r2 <= fifo_rd_load_r1;
            sdram_wr_ack1 <= I_sdram_wr_ack; sdram_wr_ack2 <= sdram_wr_ack1;
            sdram_rd_ack1 <= I_sdram_rd_ack; sdram_rd_ack2 <= sdram_rd_ack1;
            sdram_rd_valid1 <= I_sdram_rd_valid; sdram_rd_valid2 <= sdram_rd_valid1;
        end
    end

    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bank_en <= 1'b0; bank_flag <= 1'b0;
        end else if (sdram_wr_ack_n && I_sdram_pingpang_en) begin
            if (O_sdram_wr_addr[21:0] >= (I_wr_eaddr - I_wr_brust)) begin
                bank_flag <= ~bank_flag;
                bank_en   <= 1'b1;
            end
        end else if (bank_en) bank_en <= 1'b0;
    end

    // =========================================================
    // SDRAM 写地址管理 (正向写入)
    // =========================================================
    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) O_sdram_wr_addr <= 24'd0;
        else if (fifo_wr_load_p) O_sdram_wr_addr <= I_wr_saddr;
        else if (sdram_wr_ack_n) begin   
            if (I_sdram_pingpang_en && O_sdram_wr_addr[21:0] < (I_wr_eaddr - I_wr_brust))
                O_sdram_wr_addr <= O_sdram_wr_addr + I_wr_brust;
            else if (O_sdram_wr_addr < (I_wr_eaddr - I_wr_brust))
                O_sdram_wr_addr <= O_sdram_wr_addr + I_wr_brust;
            else O_sdram_wr_addr <= I_wr_saddr;
        end else if (bank_en) begin      
            O_sdram_wr_addr <= bank_flag ? {2'b01, I_wr_saddr[21:0]} : {2'b00, I_wr_saddr[21:0]};
        end
    end

    // =========================================================
    // 核心引擎：读写双轨突发计数器 & Bank 翻转标签绑定
    // =========================================================
    reg [11:0] wr_burst_cnt;
    reg        rot_writing_state, rot_bank0_state, rot_bank1_state;

    // A. 追踪写入的翻转状态并贴标签
    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            wr_burst_cnt <= 12'd0; rot_writing_state <= 1'b0;
            rot_bank0_state <= 1'b0; rot_bank1_state <= 1'b0;
        end else if (fifo_wr_load_p) wr_burst_cnt <= 12'd0;
        else if (sdram_wr_ack_n) begin
            if (wr_burst_cnt == 12'd0) rot_writing_state <= rot_180_en; // 帧首锁存
            
            if (wr_burst_cnt == 12'd2399) begin
                wr_burst_cnt <= 12'd0;
                // 一帧写完，将该帧的翻转状态永久锁定给对应的 Bank！
                if (bank_flag == 1'b0) rot_bank0_state <= rot_writing_state;
                else                   rot_bank1_state <= rot_writing_state;
            end else wr_burst_cnt <= wr_burst_cnt + 1'b1;
        end
    end

    // B. 读取端查寻 Bank 标签进行精准 V-Flip
    reg [11:0] rd_burst_cnt;
    reg [2:0]  line_burst_cnt;
    reg        active_read_rot;

    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rd_burst_cnt <= 12'd0; line_burst_cnt <= 3'd0; active_read_rot <= 1'b0;
        end else if (fifo_rd_load_p) begin
            rd_burst_cnt <= 12'd0; line_burst_cnt <= 3'd0;
            active_read_rot <= bank_flag ? rot_bank0_state : rot_bank1_state;
        end else if (sdram_rd_ack_n) begin
            if (rd_burst_cnt == 12'd2399) begin
                rd_burst_cnt <= 12'd0;
                // 帧读完切换 Bank 时，查询下一帧的真实标签
                active_read_rot <= bank_flag ? rot_bank0_state : rot_bank1_state;
            end else rd_burst_cnt <= rd_burst_cnt + 1'b1;

            if (line_burst_cnt == 3'd4) line_burst_cnt <= 3'd0;
            else line_burst_cnt <= line_burst_cnt + 1'b1;
        end
    end

    // =========================================================
    // SDRAM 读地址管理 (V-Flip 坐标倒退机制)
    // =========================================================
    wire next_rot = bank_flag ? rot_bank0_state : rot_bank1_state;

    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) O_sdram_rd_addr <= 24'd0;
        else if (fifo_rd_load_p) begin 
            O_sdram_rd_addr <= next_rot ? (I_rd_saddr + 24'd306560) : I_rd_saddr;
        end else if (sdram_rd_ack_n) begin
            if (rd_burst_cnt == 12'd2399) begin 
                if (I_sdram_pingpang_en) begin
                    if (bank_flag == 1'b0) O_sdram_rd_addr <= {2'b01, (next_rot ? I_rd_saddr[21:0] + 22'd306560 : I_rd_saddr[21:0])};
                    else                   O_sdram_rd_addr <= {2'b00, (next_rot ? I_rd_saddr[21:0] + 22'd306560 : I_rd_saddr[21:0])};
                end else O_sdram_rd_addr <= next_rot ? (I_rd_saddr + 24'd306560) : I_rd_saddr;
            end else begin
                if (active_read_rot && line_burst_cnt == 3'd4) begin
                    O_sdram_rd_addr <= O_sdram_rd_addr - 24'd1152; // V-Flip: 行末倒退到上一行首
                end else begin
                    O_sdram_rd_addr <= O_sdram_rd_addr + I_rd_brust;
                end
            end
        end
    end

    // =========================================================
    // 读写请求仲裁 — 写优先
    // =========================================================
    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_sdram_wr_req <= 1'b0; O_sdram_rd_req <= 1'b0;
        end else if (I_sdram_init_done) begin
            if (wr_fifo_use >= I_wr_brust) begin
                O_sdram_wr_req <= 1'b1; O_sdram_rd_req <= 1'b0;
            end else if (rd_fifo_use < I_rd_brust && sdram_rd_valid2) begin
                O_sdram_wr_req <= 1'b0; O_sdram_rd_req <= 1'b1;
            end else begin
                O_sdram_wr_req <= 1'b0; O_sdram_rd_req <= 1'b0;
            end
        end else begin
            O_sdram_wr_req <= 1'b0; O_sdram_rd_req <= 1'b0;
        end
    end

    // =========================================================
    // FIFO 实例化
    // =========================================================
    sdram_wr_fifo sdram_wr_fifo_inst(
        .wrclk   (I_fifo_wr_clk), .wrreq   (I_fifo_wr_req), .data    (I_fifo_wr_data),
        .rdclk   (I_ref_clk),     .rdreq   (I_sdram_wr_ack),.q       (O_sdram_wr_data),
        .aclr    (~I_rst_n | fifo_wr_load_p), .rdusedw (wr_fifo_use)
    );

    sdram_rd_fifo sdram_rd_fifo_inst(
        .wrclk   (I_ref_clk),     .wrreq   (I_sdram_rd_ack),.data    (I_sdram_rd_data),
        .rdclk   (I_fifo_rd_clk), .rdreq   (I_fifo_rd_req), .q       (O_fifo_rd_data),
        .aclr    (~I_rst_n | fifo_rd_load_p), .wrusedw (rd_fifo_use)
    );

endmodule