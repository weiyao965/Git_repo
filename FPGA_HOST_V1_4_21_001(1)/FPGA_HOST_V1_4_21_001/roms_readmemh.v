// Copyright (c) 2018  LulinChen, All Rights Reserved
// AUTHOR : 	LulinChen
// AUTHOR'S EMAIL : lulinchen@aliyun.com 
// Release history
// VERSION Date AUTHOR DESCRIPTION

module rect0_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[19:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [19:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("rect0_rom.txt", rom);
	end
endmodule


module rect1_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[19:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [19:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("rect1_rom.txt", rom);
	end
endmodule

module rect2_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[19:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [19:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("rect2_rom.txt", rom);
	end
endmodule

module rect0_wieght_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[14:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [14:0] rom [4095:0];
	//always @(posedge clk) q <= rom[addr];
	always @(posedge clk) q <= -4096;

endmodule

module rect1_wieght_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[14:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [14:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("rect1_wieght_rom.txt", rom);
	end
endmodule
module rect2_wieght_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[14:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [14:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("rect2_wieght_rom.txt", rom);
	end
endmodule

module weak_thresh_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[12:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [12:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("weak_thresh_rom.txt", rom);
	end
endmodule

module left_tree_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[13:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [13:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("left_tree_rom.txt", rom);
	end
endmodule

module right_tree_rom(
	input 				clk,
	input		[11:0]	addr,
	output reg	[13:0]	q    // x y w h 5bit*4
	);
	(* ramstyle = "block" *) reg [13:0] rom [4095:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("right_tree_rom.txt", rom);
	end
endmodule

module strong_thresh_rom(
	input 				clk,
	input		[4:0]	addr,
	output	reg	[11:0]	q
	);
	
	(* ramstyle = "block" *) reg [11:0] rom [31:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("strong_thresh_rom.txt", rom);
	end

endmodule


module weak_stages_rom(
	input 				clk,
	input		[4:0]	addr,
	output reg	[7:0]	q
	);
	
	(* ramstyle = "block" *) reg [7:0] rom [31:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("weak_stages_rom.txt", rom);
	end
endmodule


module weak_stages_acc_rom(
	input 				clk,
	input		[4:0]	addr,
	output reg	[11:0]	q
	);
	
	(* ramstyle = "block" *) reg [11:0] rom [31:0];
	always @(posedge clk) q <= rom[addr];
	initial begin
		$readmemh("weak_stages_acc_rom.txt", rom);
	end
endmodule