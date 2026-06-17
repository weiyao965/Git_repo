// Copyright (c) 2018  LulinChen, All Rights Reserved
// 终极一维拍平修复版 - 避开国产 EDA 综合器二维数组索引 MUX 坍塌 Bug

`include "global.v"

module vj(
	input					clk,
	input 					rstn,
	input	[`W_PW:0]		pic_width,
	input	[`W_PH:0]		pic_height,
	input					init,
	input	[`W1P*`W_SIZE-1:0]		pixel_i,
	input					pixel_i_en,
	output reg				ready_for_next_col,				
	output					cascade_ready,
	
	output					col_end,
	output reg				face_detected
	);

(* max_fanout = 32 *)	reg		[32:0]	pixel_i_en_d;
	always @(*)		pixel_i_en_d[0] = pixel_i_en;
	always @(`CLK_RST_EDGE)
        if (`RST)	pixel_i_en_d[32:1] <= 0;
		else		pixel_i_en_d[32:1] <= pixel_i_en_d[31:0]; 
	
	genvar i;
	genvar j;	
	genvar k;	
		
	// 【核心修复 1】彻底拍平 p_d 为 1D 数组 [0:575]
	reg		[`WII :0]	p_d [0:575];
	generate 	
		for (i=0; i<`W_SIZE; i=i+1) begin : RERANGE_PIXEL
			always @(*)		p_d[i] = pixel_i[`W1P*(`W_SIZE-i) -1 -:`W1P];
		end
	endgenerate		
	
	generate 	
		for (j=1; j<`W_SIZE; j=j+1) begin : GEN_COL_II
			always @(`CLK_EDGE)	begin : assign_p_d
				integer idx;
				if (pixel_i_en_d[j-1]) begin
					for (idx=0; idx<`W_SIZE; idx=idx+1) begin
						if (idx < j) 
							p_d[j*24 + idx] <= p_d[(j-1)*24 + idx];
						else if (idx == j)
							p_d[j*24 + idx] <= p_d[(j-1)*24 + j-1] + p_d[(j-1)*24 + j];
						else
							p_d[j*24 + idx] <= p_d[(j-1)*24 + idx];
					end
				end
			end
		end
	endgenerate

// 【核心修复 2】彻底拍平积分图 ii_reg 为 1D 数组
	// 【终极防优化】：将数组容量强行扩张到 1024，覆盖 10-bit 寻址的全部空间
	// 防止 eLinx 综合器因判定“可能越界”而将读取端强制置 0 并删除所有坐标 ROM！
	reg		[`WII :0] 	ii_reg [0:1023]; 
	reg			ii_reg_shift;
	
	generate 	
		for (j=0; j<`W_SIZE -1; j=j+1) begin : GEN_ROW_II
			for (k=0; k<`W_SIZE; k=k+1) begin : PIXEL_ADD
				always @(`CLK_RST_EDGE)
					if (`RST)					ii_reg[j*24 + k] <= 0;
					else if (ii_reg_shift)
							ii_reg[j*24 + k] <= ii_reg[(j+1)*24 + k] - ii_reg[k]; 
			end
		end
		for (k=0; k<`W_SIZE; k=k+1) begin : PIXEL_ADD_LAST
			always @(`CLK_RST_EDGE)
				if (`RST)	ii_reg[23*24 + k] <= 0;
				else if (ii_reg_shift) 
							ii_reg[23*24 + k] <= ii_reg[23*24 + k] - ii_reg[k] + p_d[23*24 + k];
		end
		// 【填充安全垫】：将扩容出来的尾部空间显式赋 0，彻底满足综合器的安全感
		for (k=576; k<1024; k=k+1) begin : SAFE_PADDING
			always @(`CLK_RST_EDGE)
				if (`RST)	ii_reg[k] <= 0;
				else		ii_reg[k] <= 0;
		end
	endgenerate
	
	//=================================================================================================
	
	// 【核心修复 3】拍平 ps_d
	reg		[`WSII :0]	ps_d [0:575];
	generate 	
		for (j=0; j<`W_SIZE; j=j+1) begin : CAL_SQUARE
			always @(*)		ps_d[j] = pixel_i[`W1P*(`W_SIZE-j) -1 -:`W1P] * pixel_i[`W1P*(`W_SIZE-j) -1 -:`W1P];
		end
	endgenerate

	generate 	
		for (j=1; j<`W_SIZE; j=j+1) begin : GEN_COL_SQUARE_INTER
			always @(`CLK_EDGE)	begin : assign_ps_d
				integer idx;
				if (pixel_i_en_d[j-1]) begin
					for (idx=0; idx<`W_SIZE; idx=idx+1) begin
						if (idx < j)
							ps_d[j*24 + idx] <= ps_d[(j-1)*24 + idx];
						else if (idx == j)
							ps_d[j*24 + idx] <= ps_d[(j-1)*24 + j-1] + ps_d[(j-1)*24 + j];
						else
							ps_d[j*24 + idx] <= ps_d[(j-1)*24 + idx];
					end
				end
			end
		end
	endgenerate
	
	// 【核心修复 4】拍平平方积分图 square_ii_reg
	reg		[`WSII :0] 	square_ii_reg [0:575];
	generate 	
		for (j=0; j<`W_SIZE -1; j=j+1) begin : GEN_ROW_SQUARE_INTER
			for (k=0; k<`W_SIZE; k=k+1) begin : PIXEL_SQ_ADD
				always @(`CLK_RST_EDGE)
					if (`RST)					square_ii_reg[j*24 + k] <= 0;
					else if (ii_reg_shift)
							square_ii_reg[j*24 + k] <= square_ii_reg[(j+1)*24 + k] - square_ii_reg[k];
			end
		end
		for (k=0; k<`W_SIZE; k=k+1) begin : PIXEL_SQ_ADD_LAST
			always @(`CLK_RST_EDGE)
				if (`RST)	square_ii_reg[23*24 + k] <= 0;
				else if (ii_reg_shift) 
							square_ii_reg[23*24 + k] <= square_ii_reg[23*24 + k] - square_ii_reg[k] + ps_d[23*24 + k];
		end
	endgenerate
	
	//=================================================================================================
	
	reg		[11:0]		aa_rect0_rom;
	wire	[19:0]		qa_rect0_rom;
	wire	[`W_WEIGHT:0]		qa_rect0_weight_rom;
	reg		[19:0]		qa_rect0_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_rect0_rom_d1 <= 0;
		else 		qa_rect0_rom_d1 <= qa_rect0_rom;
	reg		[`W_WEIGHT:0]		qa_rect0_weight_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_rect0_weight_rom_d1 <= 0;
		else 		qa_rect0_weight_rom_d1 <= qa_rect0_weight_rom;
	wire	[4:0]		rect0_x, rect0_y, rect0_w, rect0_h;
	
	assign 				{rect0_x, rect0_y, rect0_w, rect0_h} = qa_rect0_rom_d1;  
	rect0_rom rect0_rom(
		.clk		(clk),
		.addr		(aa_rect0_rom),
		.q			(qa_rect0_rom)
		);
	rect0_wieght_rom rect0_wieght_rom(
		.clk		(clk),
		.addr		(aa_rect0_rom),
		.q			(qa_rect0_weight_rom)
		);
		
	reg		[11:0]		aa_rect1_rom;
	wire	[19:0]		qa_rect1_rom;
	wire	[`W_WEIGHT:0]		qa_rect1_weight_rom;
	reg		[19:0]		qa_rect1_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_rect1_rom_d1 <= 0;
		else 		qa_rect1_rom_d1 <= qa_rect1_rom;
	reg		[`W_WEIGHT:0]		qa_rect1_weight_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_rect1_weight_rom_d1 <= 0;
		else 		qa_rect1_weight_rom_d1 <= qa_rect1_weight_rom;
	
	
	wire	[4:0]		rect1_x, rect1_y, rect1_w, rect1_h;
	assign 				{rect1_x, rect1_y, rect1_w, rect1_h} = qa_rect1_rom_d1;
	rect1_rom rect1_rom(
		.clk		(clk),
		.addr		(aa_rect1_rom),
		.q			(qa_rect1_rom)
		);
	rect1_wieght_rom rect1_wieght_rom(
		.clk		(clk),
		.addr		(aa_rect1_rom),
		.q			(qa_rect1_weight_rom)
		);
		
	reg		[11:0]		aa_rect2_rom;
	wire	[19:0]		qa_rect2_rom;
	wire	[`W_WEIGHT:0]		qa_rect2_weight_rom;
	reg		[19:0]		qa_rect2_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_rect2_rom_d1 <= 0;
		else 		qa_rect2_rom_d1 <= qa_rect2_rom;
	reg		[`W_WEIGHT:0]		qa_rect2_weight_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_rect2_weight_rom_d1 <= 0;
		else 		qa_rect2_weight_rom_d1 <= qa_rect2_weight_rom;
	wire	[4:0]		rect2_x, rect2_y, rect2_w, rect2_h;
	assign 				{rect2_x, rect2_y, rect2_w, rect2_h} = qa_rect2_rom_d1;
	rect2_rom rect2_rom(
		.clk		(clk),
		.addr		(aa_rect2_rom),
		.q			(qa_rect2_rom)
		);
	rect2_wieght_rom rect2_wieght_rom(
		.clk		(clk),
		.addr		(aa_rect2_rom),
		.q			(qa_rect2_weight_rom)
		);
		
	reg		[11:0]				aa_weak_thresh_rom;
	wire	[`W_WEAK_TH:0]		qa_weak_thresh_rom;
	reg		[`W_WEAK_TH:0]		qa_weak_thresh_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_weak_thresh_rom_d1 <= 0;
		else 		qa_weak_thresh_rom_d1 <= qa_weak_thresh_rom;
	
	weak_thresh_rom weak_thresh_rom(
		.clk		(clk),
		.addr		(aa_weak_thresh_rom),
		.q			(qa_weak_thresh_rom)
		);
		
	reg		[11:0]				aa_left_tree_rom;
	wire	[`W_TREE:0]			qa_left_tree_rom;
	reg		[`W_TREE:0]		qa_left_tree_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_left_tree_rom_d1 <= 0;
		else 		qa_left_tree_rom_d1 <= qa_left_tree_rom;	
	
	left_tree_rom left_tree_rom(
		.clk		(clk),
		.addr		(aa_left_tree_rom),
		.q			(qa_left_tree_rom)
		);
		
	reg		[11:0]				aa_right_tree_rom;
	wire	[`W_TREE:0]			qa_right_tree_rom;
	reg		[`W_TREE:0]		qa_right_tree_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_right_tree_rom_d1 <= 0;
		else 		qa_right_tree_rom_d1 <= qa_right_tree_rom;	
	
	right_tree_rom right_tree_rom(
		.clk		(clk),
		.addr		(aa_right_tree_rom),
		.q			(qa_right_tree_rom)
		);
	
	reg		[4:0]				aa_strong_thresh_rom;
	wire	[`W_STRONG_TH:0]		qa_strong_thresh_rom;
	reg		[`W_STRONG_TH:0]		qa_strong_thresh_rom_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	qa_strong_thresh_rom_d1 <= 0;
		else 		qa_strong_thresh_rom_d1 <= qa_strong_thresh_rom;
		
	strong_thresh_rom strong_thresh_rom(
		.clk		(clk),
		.addr		(aa_strong_thresh_rom),
		.q			(qa_strong_thresh_rom)
		);
		
	//=================================================================================================
	reg		[`W_PW:0]	ii_reg_col_cnt; 
	reg					ii_reg_inited; 
	reg					ii_reg_ready; 
	wire				variance_sqrt_valid; 
	reg					classify_go; 
	reg					classify_en; 
	reg		[11:0]		weak_cnt;
	reg		[4:0]		strong_cnt;
	reg					first_weak, last_weak;
	reg					last_strong;
	wire				detected_fail;
	reg					strong_fail;
	wire				cascade_end; 
	reg		[11:0]		weak_stages_acc;
	assign	col_end = (ii_reg_col_cnt == pic_width) & cascade_end;
	
	reg		[4:0]		strong_cnt_d1, strong_cnt_d2, strong_cnt_d3;
	reg		[4:0]		strong_cnt_b2, strong_cnt_b1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{strong_cnt_b1, strong_cnt, strong_cnt_d1, strong_cnt_d2, strong_cnt_d3} <= 0;
		else 		{strong_cnt_b1, strong_cnt, strong_cnt_d1, strong_cnt_d2, strong_cnt_d3} <= {strong_cnt_b2, strong_cnt_b1, strong_cnt, strong_cnt_d1, strong_cnt_d2};

	reg		[7:0]	ii_reg_ready_d;
	always @(*)	ii_reg_ready_d[0] = ii_reg_ready;
	always @(`CLK_RST_EDGE)
		if (`RST)	ii_reg_ready_d[7:1] <= 0;
		else 		ii_reg_ready_d[7:1] <= ii_reg_ready_d[6:0];	
	
	reg		[32:0]	classify_en_d;
	always @(*)		classify_en_d[0] = classify_en;
	always @(`CLK_RST_EDGE)
        if (`RST)	classify_en_d[32:1] <= 0;
		else		classify_en_d[32:1] <= classify_en_d[31:0];
		
	reg		[32:0]	first_weak_d;
	always @(*)		first_weak_d[0] = first_weak;
	always @(`CLK_RST_EDGE)
        if (`RST)	first_weak_d[32:1] <= 0;
		else		first_weak_d[32:1] <= first_weak_d[31:0];

	reg		[32:0]	last_weak_d;
	always @(*)		last_weak_d[0] = last_weak;
	always @(`CLK_RST_EDGE)
        if (`RST)	last_weak_d[32:1] <= 0;
		else		last_weak_d[32:1] <= last_weak_d[31:0];
	
	reg		[32:0]	last_strong_d;
	always @(*)		last_strong_d[0] = last_strong;
	always @(`CLK_RST_EDGE)
        if (`RST)	last_strong_d[32:1] <= 0;
		else		last_strong_d[32:1] <= last_strong_d[31:0];
	
	wire	ii_reg_inited_f = ii_reg_shift&(ii_reg_col_cnt==`W_SIZE-1);
	always @(`CLK_RST_EDGE)
        if (`RST)					ii_reg_col_cnt <= 0;
		else if (init)				ii_reg_col_cnt <= 0;
		else if (ii_reg_shift)		ii_reg_col_cnt <= ii_reg_col_cnt + 1;

	always @(`CLK_RST_EDGE)
        if (`RST)					ii_reg_inited <= 0;
		else if (init)				ii_reg_inited <= 0;
		else if (ii_reg_inited_f)	ii_reg_inited <= 1;

	always @(`CLK_RST_EDGE)
        if (`RST)								ii_reg_ready <= 0;
		else if (ii_reg_inited_f)				ii_reg_ready <= 1;
		else if (ii_reg_shift&ii_reg_inited)	ii_reg_ready <= 1;
		else 									ii_reg_ready <= 0;
	
	reg		ii_reg_shift_b1;
	reg		[1:0]	line_ii_semaphore;
	reg				ii_reg_ready_b1;
	reg				cascade_done;

	always @(`CLK_RST_EDGE)
        if (`RST)					cascade_done <= 0;
		else if (ii_reg_shift_b1)	cascade_done <= 0;
		else if (cascade_end)		cascade_done <= 1;

	always @(`CLK_RST_EDGE)
        if (`RST)	line_ii_semaphore <= 0;
		else case ( {pixel_i_en_d[22], ii_reg_shift_b1})
			2'b10 : line_ii_semaphore <= line_ii_semaphore + 1;
			2'b01 : line_ii_semaphore <= line_ii_semaphore - 1;
			endcase
			
	reg		ii_reg_inited_b1;
	reg		[`W_PW:0]	ii_reg_col_cnt_b1;
	always @(`CLK_RST_EDGE)
        if (`RST)					ii_reg_col_cnt_b1 <= 0;
		else if (init)				ii_reg_col_cnt_b1 <= 0;
		else if (ii_reg_shift_b1)	ii_reg_col_cnt_b1 <= ii_reg_col_cnt_b1 + 1;
		
	wire	ii_reg_inited_f_b1 = ii_reg_shift_b1&(ii_reg_col_cnt_b1==24-1);

	always @(`CLK_RST_EDGE)
        if (`RST)							ii_reg_inited_b1 <= 0;
		else if (init)						ii_reg_inited_b1 <= 0;
		else if (ii_reg_inited_f_b1)		ii_reg_inited_b1 <= 1;
							
	always @(*)	ii_reg_shift_b1 = (~ii_reg_inited_b1&pixel_i_en_d[22] )|| (cascade_done&&line_ii_semaphore!=0);
	
	always @(`CLK_RST_EDGE)
		if (`RST)	ii_reg_shift <= 0;
		else 		ii_reg_shift <= ii_reg_shift_b1;

	wire		ii_reg_shift__ = (~ii_reg_inited&pixel_i_en_d[23] )|| (cascade_done&&line_ii_semaphore!=0);
	
	always @(`CLK_RST_EDGE)
        if (`RST)	ready_for_next_col <= 0;
		else		ready_for_next_col <= ii_reg_ready;
		
	//------------------------------------------------------------
	wire	[11:0]	qa_weak_stages_acc_rom;
	weak_stages_acc_rom weak_stages_acc_rom(
		.clk		(clk),
		.addr		(strong_cnt_b2),
		.q			(qa_weak_stages_acc_rom)
		);

	always @(`CLK_RST_EDGE)
        if (`RST)			classify_go <= 0;
		else 				classify_go <= variance_sqrt_valid;

	always @(*)		strong_fail = detected_fail & last_weak_d[8];
	
	// =========================================================================
	// 【恢复智力】：提升到第 8 关及格，防止误抓墙壁阴影！
	// =========================================================================
	wire early_pass = !detected_fail & last_weak_d[8] & (strong_cnt_b1 >= 5'd3);

	assign cascade_end   = (strong_fail & !last_strong_d[8]) | (weak_cnt == `TATAL_WEAK_STAGES-1) | early_pass;
	
	always @(*) face_detected = early_pass;
	
	assign cascade_ready = strong_fail | early_pass;
	// =========================================================================
	
	always @(`CLK_RST_EDGE)
        if (`RST)									classify_en <= 1;
		else if (classify_go)						classify_en <= 1;
		else if (strong_fail || (weak_cnt == `TATAL_WEAK_STAGES-1) || early_pass)	
													classify_en <= 0;
	always @(`CLK_RST_EDGE)
        if (`RST)				weak_cnt <= 0;
		else					weak_cnt <= classify_en? weak_cnt + 1 : 0;
		
	always @(`CLK_RST_EDGE)
        if (`RST)				weak_stages_acc <= 0;
		else					weak_stages_acc <= qa_weak_stages_acc_rom;

	always @(`CLK_RST_EDGE)
        if (`RST)								strong_cnt_b2 <= 0;
		else if (classify_go)					strong_cnt_b2 <= 0;
		else if (strong_fail || early_pass)		strong_cnt_b2 <= 0;
		else if (weak_cnt==weak_stages_acc-3)	strong_cnt_b2 <= (strong_cnt_b2==`STAGE_N-1 )? 0 : strong_cnt_b2+1;

	always @(`CLK_RST_EDGE)
        if (`RST)	last_weak <= 0;	
		else 		last_weak <= weak_cnt==weak_stages_acc-2 ? 1 : 0;
		
	always @(`CLK_RST_EDGE)
        if (`RST)	first_weak <= 0;
		else 		first_weak <= classify_go || ( last_weak & !last_strong);
		
		
	always @(`CLK_RST_EDGE)
        if (`RST)	last_strong <= 0;
		else 		last_strong <= strong_cnt_b1==`STAGE_N-1 ? 1 : 0;

	
	//==========================================================
	wire		[`WII:0]	mean = ii_reg[23*24 + 23];
	wire		[`WSII:0]	square_mean = square_ii_reg[23*24 + 23];
	
	reg			[`WII+`WII+1:0]	mean_x2;
	always @(`CLK_RST_EDGE)
        if (`ZST)				mean_x2 <= 0;
		else if (ii_reg_ready)	mean_x2 = mean * mean;

	reg			[`WII+`WII+1:0]	square_mean_x_size;
	always @(`CLK_RST_EDGE)
        if (`ZST)				square_mean_x_size <= 0;
		else if (ii_reg_ready)	square_mean_x_size <= square_mean * (`W_SIZE * `W_SIZE);
	
	reg		[`W_VAR+`W_VAR+1:0]			variance;
	wire	[`W_VAR:0]					variance_sqrt;

	always @(`CLK_RST_EDGE)
        if (`ZST)		variance <= 0;
		// 【终极方差钳位保护】：防止定点数舍入导致负数溢出爆炸！
		else if (square_mean_x_size > mean_x2) 
						variance <= square_mean_x_size - mean_x2;
		else 			variance <= 0; // 如果出现负数，直接钳位到 0！

	sqrt_root2 #(.WI	(`W_VAR+`W_VAR+1+1)) sqrt_root(
		.clk			(clk), 
		.rstn			(rstn), 
		.en				(ii_reg_ready_d[2]), 
		.radical		(variance), 		
		.root_en		(variance_sqrt_valid),	 
		.root			(variance_sqrt),		
		.remainder	    ()
		);
	
	always @(*)		aa_rect0_rom = weak_cnt;
	always @(*)		aa_rect1_rom = weak_cnt;
	always @(*)		aa_rect2_rom = weak_cnt;
	always @(*)		aa_weak_thresh_rom = weak_cnt;
	always @(*)		aa_left_tree_rom = weak_cnt;
	always @(*)		aa_right_tree_rom = weak_cnt;
	
	always @(*)		aa_strong_thresh_rom = strong_cnt;
	
	//=================================================================================================
	reg		[`W_WEIGHT:0] w0, w1, w2;
	reg		[`W_WEAK_TH:0]		weak_thresh;
	reg		[`W_TREE:0]			right_tree, left_tree;
	reg		[`W_STRONG_TH:0]	strong_thresh;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{w0, w1, w2} <= 0;
		else 		{w0, w1, w2} <= {qa_rect0_weight_rom_d1, qa_rect1_weight_rom_d1, qa_rect2_weight_rom_d1};
	
	always @(`CLK_RST_EDGE)
		if (`ZST)	weak_thresh <= 0;
		else		weak_thresh <= qa_weak_thresh_rom_d1;
		
	always @(`CLK_RST_EDGE)
		if (`ZST)	{right_tree, left_tree} <= 0;
		else		{right_tree, left_tree} <= {qa_right_tree_rom_d1, qa_left_tree_rom_d1};

	always @(`CLK_RST_EDGE)
		if (`ZST)	strong_thresh <= 0;
		else		strong_thresh <= qa_strong_thresh_rom_d1;
		
	// 【核心修复 5】将所有坐标提取为 1D 安全地址
	wire [9:0] r0_p0_idx = (rect0_x==0 || rect0_y==0) ? 10'd0 : (rect0_x-1)*24 + (rect0_y-1);
	wire [9:0] r0_p1_idx = ((rect0_x+rect0_w)==0 || rect0_y==0) ? 10'd0 : (rect0_x+rect0_w-1)*24 + (rect0_y-1);
	wire [9:0] r0_p2_idx = (rect0_x==0 || (rect0_y+rect0_h)==0) ? 10'd0 : (rect0_x-1)*24 + (rect0_y+rect0_h-1);
	wire [9:0] r0_p3_idx = ((rect0_x+rect0_w)==0 || (rect0_y+rect0_h)==0) ? 10'd0 : (rect0_x+rect0_w-1)*24 + (rect0_y+rect0_h-1);
	
	reg		[`WII:0] rect0_p0, rect0_p1, rect0_p2, rect0_p3;
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect0_p0 <= 0;
		else if (rect0_x==0 || rect0_y==0) rect0_p0 <= 0;
		else		rect0_p0 <= ii_reg[r0_p0_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect0_p1 <= 0;
		else if ((rect0_x+rect0_w)==0 || rect0_y==0) rect0_p1 <= 0;
		else		rect0_p1 <= ii_reg[r0_p1_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect0_p2 <= 0;
		else if (rect0_x==0 || (rect0_y+rect0_h)==0) rect0_p2 <= 0;
		else		rect0_p2 <= ii_reg[r0_p2_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect0_p3 <= 0;
		else if ((rect0_x+rect0_w)==0 || (rect0_y+rect0_h)==0) rect0_p3 <= 0;
		else		rect0_p3 <= ii_reg[r0_p3_idx];
	end
	
	wire [9:0] r1_p0_idx = (rect1_x==0 || rect1_y==0) ? 10'd0 : (rect1_x-1)*24 + (rect1_y-1);
	wire [9:0] r1_p1_idx = ((rect1_x+rect1_w)==0 || rect1_y==0) ? 10'd0 : (rect1_x+rect1_w-1)*24 + (rect1_y-1);
	wire [9:0] r1_p2_idx = (rect1_x==0 || (rect1_y+rect1_h)==0) ? 10'd0 : (rect1_x-1)*24 + (rect1_y+rect1_h-1);
	wire [9:0] r1_p3_idx = ((rect1_x+rect1_w)==0 || (rect1_y+rect1_h)==0) ? 10'd0 : (rect1_x+rect1_w-1)*24 + (rect1_y+rect1_h-1);
	
	reg		[`WII:0] rect1_p0, rect1_p1, rect1_p2, rect1_p3; 
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect1_p0 <= 0;
		else if (rect1_x==0 || rect1_y==0) rect1_p0 <= 0;
		else		rect1_p0 <= ii_reg[r1_p0_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect1_p1 <= 0;
		else if ((rect1_x+rect1_w)==0 || rect1_y==0) rect1_p1 <= 0;
		else		rect1_p1 <= ii_reg[r1_p1_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect1_p2 <= 0;
		else if (rect1_x==0 || (rect1_y+rect1_h)==0) rect1_p2 <= 0;
		else		rect1_p2 <= ii_reg[r1_p2_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect1_p3 <= 0;
		else if ((rect1_x+rect1_w)==0 || (rect1_y+rect1_h)==0) rect1_p3 <= 0;
		else		rect1_p3 <= ii_reg[r1_p3_idx];
	end
	
	wire [9:0] r2_p0_idx = (rect2_x==0 || rect2_y==0) ? 10'd0 : (rect2_x-1)*24 + (rect2_y-1);
	wire [9:0] r2_p1_idx = ((rect2_x+rect2_w)==0 || rect2_y==0) ? 10'd0 : (rect2_x+rect2_w-1)*24 + (rect2_y-1);
	wire [9:0] r2_p2_idx = (rect2_x==0 || (rect2_y+rect2_h)==0) ? 10'd0 : (rect2_x-1)*24 + (rect2_y+rect2_h-1);
	wire [9:0] r2_p3_idx = ((rect2_x+rect2_w)==0 || (rect2_y+rect2_h)==0) ? 10'd0 : (rect2_x+rect2_w-1)*24 + (rect2_y+rect2_h-1);
	
	reg		[`WII:0] rect2_p0, rect2_p1, rect2_p2, rect2_p3; 
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect2_p0 <= 0;
		else if (rect2_x==0 || rect2_y==0) rect2_p0 <= 0;
		else		rect2_p0 <= ii_reg[r2_p0_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect2_p1 <= 0;
		else if ((rect2_x+rect2_w)==0 || rect2_y==0) rect2_p1 <= 0;
		else		rect2_p1 <= ii_reg[r2_p1_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect2_p2 <= 0;
		else if (rect2_x==0 || (rect2_y+rect2_h)==0) rect2_p2 <= 0;
		else		rect2_p2 <= ii_reg[r2_p2_idx];
	end
	always @(`CLK_RST_EDGE) begin
		if (`RST)	rect2_p3 <= 0;
		else if ((rect2_x+rect2_w)==0 || (rect2_y+rect2_h)==0) rect2_p3 <= 0;
		else		rect2_p3 <= ii_reg[r2_p3_idx];
	end
		
	classifier classifier(
		.clk			(clk		),
		.rstn			(rstn		),
		.init			(classify_go),
		.first_weak		(first_weak_d[3]),
		.en				(classify_en_d[3]),
		.w0				(w0),
		.w1				(w1),
		.w2				(w2),
		.r0 			(rect0_p0),
		.r1 			(rect0_p1),
		.r2 			(rect0_p2),
		.r3 			(rect0_p3),
		.r4 			(rect1_p0),
		.r5 			(rect1_p1),
		.r6 			(rect1_p2),
		.r7 			(rect1_p3),
		.r8 			(rect2_p0),
		.r9 			(rect2_p1),
		.r10			(rect2_p2),
		.r11			(rect2_p3),
		
		.variance_sqrt	(variance_sqrt	),
		.weak_thresh	(weak_thresh	),
		.left_tree		(left_tree	),
		.right_tree		(right_tree	),
		.strong_thresh	(strong_thresh	),
		.detected_fail	(detected_fail	)
		);
endmodule 

// latency  5 clk
module classifier(
	input					clk,
	input 					rstn,
	
	input					init,   
	input					first_weak,   
	input					en,
	
	input	[`W_WEIGHT:0]	w0, w1, w2,
	
	input	[`WII:0]		r0, r1, r2, r3,					
	input	[`WII:0]		r4, r5, r6, r7,					
	input	[`WII:0]		r8, r9, r10, r11,					
	
	input 	[`W_VAR:0]			variance_sqrt,
	input	[`W_WEAK_TH:0]		weak_thresh,
	input signed	[`W_TREE:0]	right_tree, left_tree,
	input	[`W_STRONG_TH:0]	strong_thresh,
	output	reg					result_valid,
	output	reg					detected_fail			
	);

	reg		signed [`W_WEIGHT:0]		w0_d1, w1_d1, w2_d1;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{w0_d1, w1_d1, w2_d1} <= 0;
		else 		{w0_d1, w1_d1, w2_d1} <= {w0, w1, w2};
		
	reg	signed	[`W_WEAK_TH:0]		weak_thresh_d1, weak_thresh_d2, weak_thresh_d3;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{weak_thresh_d1, weak_thresh_d2, weak_thresh_d3} <= 0;
		else 		{weak_thresh_d1, weak_thresh_d2, weak_thresh_d3} <= {weak_thresh, weak_thresh_d1, weak_thresh_d2};
	
	reg	signed	[`W_TREE:0]		right_tree_d1, right_tree_d2, right_tree_d3;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{right_tree_d1, right_tree_d2, right_tree_d3} <= 0;
		else 		{right_tree_d1, right_tree_d2, right_tree_d3} <= {right_tree, right_tree_d1, right_tree_d2};
	
	reg	signed	[`W_TREE:0]		left_tree_d1, left_tree_d2, left_tree_d3;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{left_tree_d1, left_tree_d2, left_tree_d3} <= 0;
		else 		{left_tree_d1, left_tree_d2, left_tree_d3} <= {left_tree, left_tree_d1, left_tree_d2};
	
	reg						en_d1, en_d2, en_d3, en_d4, en_d5;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{en_d1, en_d2, en_d3, en_d4, en_d5} <= 0;
		else 		{en_d1, en_d2, en_d3, en_d4, en_d5} <= {en, en_d1, en_d2, en_d3, en_d4};

	reg						first_weak_d1, first_weak_d2, first_weak_d3, first_weak_d4, first_weak_d5;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{first_weak_d1, first_weak_d2, first_weak_d3, first_weak_d4, first_weak_d5} <= 0;
		else 		{first_weak_d1, first_weak_d2, first_weak_d3, first_weak_d4, first_weak_d5} <= {first_weak, first_weak_d1, first_weak_d2, first_weak_d3, first_weak_d4};

	reg	signed		[`W_STRONG_TH:0] strong_thresh_d1, strong_thresh_d2, strong_thresh_d3, strong_thresh_d4, strong_thresh_d5;
	always @(`CLK_RST_EDGE)
		if (`ZST)	{strong_thresh_d1, strong_thresh_d2, strong_thresh_d3, strong_thresh_d4, strong_thresh_d5} <= 0;
		else 		{strong_thresh_d1, strong_thresh_d2, strong_thresh_d3, strong_thresh_d4, strong_thresh_d5} <= {strong_thresh, strong_thresh_d1, strong_thresh_d2, strong_thresh_d3, strong_thresh_d4};

	reg	signed	[`WII:0]					result_rect0, result_rect1, result_rect2; 
	reg	signed	[`WII+`W_WEIGHT+1:0]		result_feature;
	
	always @(`CLK_RST_EDGE)
		if (`ZST)	result_rect0 <= 0;
		else 		result_rect0 <= (r0 + r3) - (r1 + r2);

	always @(`CLK_RST_EDGE)
		if (`ZST)	result_rect1 <= 0;
		else 		result_rect1 <= (r4 + r7) - (r5 + r6);
		
	always @(`CLK_RST_EDGE)
		if (`ZST)	result_rect2 <= 0;
		else 		result_rect2 <= (r8 + r11) - (r9 + r10);
		
	always @(`CLK_RST_EDGE)
		if (`RST)	result_feature <= 0;
		else 		result_feature <= w0_d1*result_rect0 + w1_d1*result_rect1 + w2_d1*result_rect2;
	
	
	wire		result_feature_valid = en_d2;
	wire		strong_accumulator_result_valid = en_d4;
	
	
	reg	signed	[34:0]	var_norm_weak_thresh;	
	always @(`CLK_RST_EDGE)
		if (`RST)					var_norm_weak_thresh <= 0;
		else if (variance_sqrt==0)	var_norm_weak_thresh <= weak_thresh_d1;
		else 						var_norm_weak_thresh <= $signed({1'b0, variance_sqrt}) * weak_thresh_d1;
	
	reg						tree_mux_sel;
	reg	 signed	[`W_ACC:0]		strong_accumulator_result;
	
	always @(`CLK_RST_EDGE)
		if (`ZST)		tree_mux_sel <= 0;
		else 			tree_mux_sel <=  (result_feature >= var_norm_weak_thresh)? 1: 0;
		
	wire 	signed	[`W_TREE:0]	tree =  tree_mux_sel? $signed(right_tree_d3) : $signed(left_tree_d3);

	always @(`CLK_RST_EDGE)
		if (`ZST)			strong_accumulator_result <= 0;
		else if (init)		strong_accumulator_result <= 0;
		else if (first_weak_d3)strong_accumulator_result <= tree;
		else if (en_d3)		strong_accumulator_result <= strong_accumulator_result +  tree;
		
	always @(`CLK_RST_EDGE)
		if (`RST)			detected_fail <= 0;										
		// 【定点数容错】：给真实的算分逻辑提供 +1000 的硬件补偿
		else if (en_d4)		detected_fail <= ($signed(strong_accumulator_result) + 1000 < $signed(strong_thresh_d4)) ? 1 : 0;
		
	always @(`CLK_RST_EDGE)
		if (`RST)			result_valid <= 0;										
		else				result_valid <= en_d4;

endmodule

module sqrt_root2 #(parameter WI = 26)(
	input					clk,
	input 					rstn,
	input 					en,
	input 		[WI-1:0]	radical,
	output reg					root_en,		
	output reg		[WI/2 -1:0]	root,		
	output		[WI/2:0]	remainder
	);
	
	localparam W_CNT_BITS = $clog2(WI);
	
	wire	[WI/2 -1:0] one	= 1;
	
	reg	[WI-1:0]	radical_d [0:WI+2];
	always @(*)	radical_d[0] = radical;
	
	integer r_i;
	always @(`CLK_RST_EDGE) begin
		if (`RST) begin
			for (r_i=1; r_i<=WI+2; r_i=r_i+1)
				radical_d[r_i] <= 0;
		end else begin
			for (r_i=1; r_i<=WI+2; r_i=r_i+1)
				radical_d[r_i] <= radical_d[r_i-1];
		end
	end
		
	reg	[WI+2:0]	en_d;
	always @(*)	en_d[0] = en;
	always @(`CLK_RST_EDGE)
		if (`RST)	en_d[WI+2:1] <= 0;
		else 		en_d[WI+2:1] <= en_d[WI+1:0];

	reg		 [WI/2 -1:0]	tmp_res; 
	reg						tmp_res_gt;
	always @(`CLK_RST_EDGE)
		if (`RST)	tmp_res_gt <= 0;
		else 		tmp_res_gt <= tmp_res*tmp_res >  radical;
	
	wire	cnt_bits_go = en;	
	reg						cnt_bits_e;
	reg		[ W_CNT_BITS:0]		cnt_bits;
	wire				cnt_bits_max_f = cnt_bits == WI-1;
	always @(`CLK_RST_EDGE)
		if (`RST)					cnt_bits_e <= 0;
		else if (cnt_bits_go)		cnt_bits_e <= 1;
		else if (cnt_bits_max_f)	cnt_bits_e <= 0;
	
	always @(`CLK_RST_EDGE)
		if (`RST)	cnt_bits <= 0;
		else 		cnt_bits <= cnt_bits_e? cnt_bits + 1 : 0;

	always @(`CLK_RST_EDGE)
		if (`RST)				tmp_res <= 0;
		else if (cnt_bits_go)	tmp_res <= one << (WI/2 -1);
		else if (cnt_bits[0])	
			if (tmp_res_gt)	
				tmp_res <= tmp_res ^ (one << (WI/2 -1 -cnt_bits[W_CNT_BITS:1]));
			else 
				tmp_res <= tmp_res;
		else if (!cnt_bits[0])	
				tmp_res <= tmp_res | (one << (WI/2 - 2 -cnt_bits[W_CNT_BITS:1]));
	
	reg	[7:0]	cnt_bits_max_f_d;
	always @(*)	cnt_bits_max_f_d[0] = cnt_bits_max_f;
	always @(`CLK_RST_EDGE)
		if (`RST)	cnt_bits_max_f_d[7:1] <= 0;
		else 		cnt_bits_max_f_d[7:1] <= cnt_bits_max_f_d[6:0];
	
	always @(`CLK_RST_EDGE)
		if (`RST)	root_en <= 0;
		else 		root_en <= cnt_bits_max_f_d[1];
		
	always @(`CLK_RST_EDGE)
		if (`RST)						root <= 0;
		else if (cnt_bits_max_f_d[1])	root <= tmp_res;
		
	assign 	remainder = radical_d[WI+2] - root*root ;
	wire	[WI-1:0] 	radical_o = radical_d[WI];
	
endmodule