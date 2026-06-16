// Copyright (c) 2018  LulinChen, All Rights Reserved
// 终极时序完美对齐版 - 专为国产 FPGA 纯同步 BRAM 优化
// 彻底解决图像撕裂、消除 1 周期时序偏差的 3 拍流水线版本

`include "global.v"

module vj_fetch(
	input							clk,
	input							rstn,
	input	[`W_PW:0]				pic_width,
	input	[`W_PH:0]				pic_height,
	input	[4:0]					step,
	
	input							vj_fetch_go,
	output reg	[`W1P*`W_SIZE-1:0]	pixels,
	output reg						pixels_en,
	output reg						vj_row_init,
	input							ready_for_next_col,				
	input							cascade_end,
	input							col_end,
	output reg		[`W_PW:0]		vj_col,
	output reg		[`W_PH:0]		vj_row,
	output reg						vj_frame_ready,
	
	// 【终极修复 1】：将地址端口由 reg 改为 wire，消除打拍造成的 1 周期延迟
	output wire 	[`W_AFRAMEBUF:0]	aa_frame_buf,
	output reg							cena_frame_buf,
	input		[`W1:0]					qa_frame_buf,
	
	input								face_detected
	);
	
	reg		[`W_PW:0]	pic_width_r;
	reg		[`W_PH:0]	pic_height_r;
	always @(`CLK_RST_EDGE)
		if (`RST)	{ pic_width_r, pic_height_r} <= -1;
		else if (vj_fetch_go) begin
			pic_width_r <= pic_width;
			pic_height_r <= pic_height;
		end
	
	reg		[`W_PW:0]		read_col;
	reg		[`W_PH:0]		read_row;
		
	wire	coloum_ready;
	wire	row_init_ready;

	reg		vj_row_ready;
	wire	row_init_go = vj_fetch_go | vj_row_ready&(vj_row != pic_height_r-`W_SIZE);
	always@* vj_row_init = row_init_go;
	reg		coloum_fetch_go;
	always @(`CLK_RST_EDGE)
		if (`RST)	vj_row_ready <= 0;
		else 		vj_row_ready <= cascade_end & (vj_col == pic_width_r-`W_SIZE);
	always @(`CLK_RST_EDGE)
		if (`RST)	vj_frame_ready <= 0;
		else 		vj_frame_ready <= vj_row_ready & (vj_row == pic_height_r-`W_SIZE);
	
	always @(`CLK_RST_EDGE)
		if (`RST)					vj_col <= 0;
		else if (row_init_go)		vj_col <= 0;
		else if (cascade_end)		vj_col <= vj_col + 1;
		
	always @(`CLK_RST_EDGE)
		if (`RST)					vj_row <= 0;
		else if (vj_fetch_go) 		vj_row <= 0;	
		else if (row_init_go)		vj_row <= vj_row + 1;	

	reg					cnt_row_init_e;
	reg		[ 4 :0]		cnt_row_init;
	wire				cnt_row_init_max_f = cnt_row_init == `W_SIZE -1;
	always @(`CLK_RST_EDGE)
		if (`RST)						cnt_row_init_e <= 0;
		else if (row_init_go)			cnt_row_init_e <= 1;
		else if (cnt_row_init_max_f&coloum_ready)	cnt_row_init_e <= 0;
	
	always @(`CLK_RST_EDGE)
		if (`RST)					cnt_row_init <= 0;
		else if(cnt_row_init_e)		cnt_row_init <= cnt_row_init + coloum_ready;
		else 						cnt_row_init <= 0;
	assign row_init_ready = cnt_row_init_max_f&coloum_ready;
	
	always @(`CLK_RST_EDGE)
		if (`RST)														coloum_fetch_go <= 0;
		else if (row_init_go)											coloum_fetch_go <= 1;
		else if (cnt_row_init_e & coloum_ready &!cnt_row_init_max_f) 	coloum_fetch_go <= 1; 
		else if (ready_for_next_col && read_col < pic_width_r)			coloum_fetch_go <= 1;
		else 															coloum_fetch_go <= 0;

	reg [8:1] coloum_fetch_go_r;
	wire [8:0] coloum_fetch_go_d;
	assign coloum_fetch_go_d[0] = coloum_fetch_go;
	assign coloum_fetch_go_d[8:1] = coloum_fetch_go_r;
	always @(`CLK_RST_EDGE) begin
		if (`RST) coloum_fetch_go_r <= 8'd0;
		else      coloum_fetch_go_r <= {coloum_fetch_go_r[7:1], coloum_fetch_go_d[0]};
	end
		
	reg					cnt_fetch_e;
	reg		[ 4 :0]		cnt_fetch;
	wire				cnt_fetch_max_f = cnt_fetch == `W_SIZE-1;
	always @(`CLK_RST_EDGE)
		if (`RST)					cnt_fetch_e <= 0;
		else if (coloum_fetch_go)	cnt_fetch_e <= 1;
		else if (cnt_fetch_max_f)	cnt_fetch_e <= 0;
	
	always @(`CLK_RST_EDGE)
		if (`RST)	cnt_fetch <= 0;
		else if(cnt_fetch_e)		cnt_fetch <= cnt_fetch_max_f? 0: cnt_fetch + 1;

	// 保留足够的延迟线位宽
	reg [8:1] cnt_fetch_max_f_r;
	wire [8:0] cnt_fetch_max_f_d;
	assign cnt_fetch_max_f_d[0] = cnt_fetch_max_f;
	assign cnt_fetch_max_f_d[8:1] = cnt_fetch_max_f_r;
	always @(`CLK_RST_EDGE) begin
		if (`RST) cnt_fetch_max_f_r <= 8'd0;
		else      cnt_fetch_max_f_r <= {cnt_fetch_max_f_r[7:1], cnt_fetch_max_f_d[0]};
	end

	reg [8:1] cnt_fetch_e_r;
	wire [8:0] cnt_fetch_e_d;
	assign cnt_fetch_e_d[0] = cnt_fetch_e;
	assign cnt_fetch_e_d[8:1] = cnt_fetch_e_r;
	always @(`CLK_RST_EDGE) begin
		if (`RST) cnt_fetch_e_r <= 8'd0;
		else      cnt_fetch_e_r <= {cnt_fetch_e_r[7:1], cnt_fetch_e_d[0]};
	end

	reg [4:0] cnt_fetch_d0, cnt_fetch_d1, cnt_fetch_d2, cnt_fetch_d3, cnt_fetch_d4;
	always @(*) cnt_fetch_d0 = cnt_fetch;
	always @(`CLK_RST_EDGE) begin
		if (`RST) begin
			cnt_fetch_d1 <= 0; cnt_fetch_d2 <= 0; cnt_fetch_d3 <= 0; cnt_fetch_d4 <= 0;
		end else begin
			cnt_fetch_d1 <= cnt_fetch_d0;
			cnt_fetch_d2 <= cnt_fetch_d1;
			cnt_fetch_d3 <= cnt_fetch_d2;
			cnt_fetch_d4 <= cnt_fetch_d3;
		end
	end
		
	assign coloum_ready = cnt_fetch_max_f;
	
	always @(`CLK_RST_EDGE)
		if (`RST)						read_col <= 0;
		else if(row_init_go)			read_col <= 0;
		else if (cnt_fetch_max_f_d[1])	read_col <= read_col + 1;
		
	always @(`CLK_RST_EDGE)
		if (`RST)						read_row <= 0;
		else 							read_row <= vj_row + cnt_fetch;
	
	reg		[`W_FRAME_COL+1:0] 	read_col_addr;
	reg		[`W_FRAME_ROW+1:0] 	vj_row_addr;
	reg		[`W_FRAME_ROW+1:0] 	read_row_addr;
	reg		[`W_AFRAMEBUF:0] 	row_step;	
	always @(`CLK_RST_EDGE)
		if (`RST)	row_step <= 0;
		else		row_step <= step*`FRAME_BUF_LINE; 
	
	always @(`CLK_RST_EDGE)
		if (`RST)						read_col_addr <= 0;
		else if(row_init_go)			read_col_addr <= 0;	
		else if(cnt_fetch_max_f_d[1]) 	read_col_addr <= read_col_addr + step;	
	
	always @(`CLK_RST_EDGE)
		if (`RST)					vj_row_addr <= 0;
		else if (vj_fetch_go) 		vj_row_addr <= 0;	
		else if (row_init_go)		vj_row_addr <= vj_row_addr + step;	
	
	always @(`CLK_RST_EDGE)
		if (`RST)						read_row_addr <= 0;
		else if(coloum_fetch_go_d[1])	read_row_addr <= vj_row_addr;
		else if(cnt_fetch_e_d[1]) 		read_row_addr <= read_row_addr + step;	
		
	// -------------------------------------------------------------
	// 终极修复区：精准匹配 BRAM 的 1 周期读取延迟
	// -------------------------------------------------------------
	wire [8:0] true_row = read_row_addr[`W_FRAME_ROW+1:1];
	wire [8:0] true_col = read_col_addr[`W_FRAME_COL+1 : 1];
	
	// 计算地址并零延迟送出
	wire [16:0] linear_addr = (true_row << 7) + (true_row << 5) + true_col;
	assign aa_frame_buf = linear_addr;
	
	always @(`CLK_RST_EDGE)
		if (`RST)	cena_frame_buf <= 1;
		else 		cena_frame_buf <= ~cnt_fetch_e_d[1];
	
	reg	[`W1P*`W_SIZE-1:0]	pixels_alias;
	always @(`CLK_RST_EDGE) begin
		if (`RST) begin
			pixels_alias <= 0;
		end else if (cnt_fetch_e_d[2]) begin
			// 【绝杀修复】：在时钟沿 2 获取 BRAM 数据时，
			// 必须使用早已在沿 1 稳定的 d1 索引，才能精准放进正确的篮子！
			pixels_alias[(23 - cnt_fetch_d1)*8 +: 8] <= qa_frame_buf;
		end
	end

	always @(*)	pixels = pixels_alias;
	
	always @(`CLK_RST_EDGE)
		if (`RST)	pixels_en <= 0;
		else 		pixels_en <= cnt_fetch_max_f_d[2];

endmodule