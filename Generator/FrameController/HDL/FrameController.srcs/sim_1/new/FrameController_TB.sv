//Com2DocHDL
/*
:Project
FPGA-Imaging-Library

:Design
FrameController

:Function
For controlling a BlockRAM from xilinx.
Give the first output after ram_read_latency cycles while the input enable.

:Module
Test bench

:Version
1.0

:Modified
2015-05-12

Copyright (C) 2015  Tianyu Dai (dtysky) <dtysky@outlook.com>

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

Homepage for this project:
	http://fil.dtysky.moe

Sources for this project:
	https://github.com/dtysky/FPGA-Imaging-Library

My e-mail:
	dtysky@outlook.com

My blog:
	http://dtysky.moe

*/

`timescale 1ns / 1ps
module CLOCK (
	output bit clk
	);
	
	always #(100ps) begin
		clk = ~clk;
	end

endmodule

interface TBInterface (input bit clk, input bit rst_n);
	parameter color_width = 8;
	parameter addr_width = 18;
	bit in_enable;
	bit[color_width - 1 : 0] in_data;
	bit out_ready;
	bit[color_width - 1 : 0] out_data;
	bit[addr_width - 1 : 0] ram_addr;
endinterface

module FrameController_TB();

	//For Frame
	//Can't be changed in this test
	parameter im_width = 512;
	parameter im_height = 512;
	parameter addr_width = 18;
	parameter ram_read_latency = 2;
	parameter color_width = 8;
	parameter row_init = 0;

	integer fi,fo;
	string fname[$];
	string ftmp, imconf;
	int fsize;
	bit now_start;
	int fst;

	bit clk,rst_n;
	TBInterface PipelineWrite(clk, rst_n);
	TBInterface PipelineRead(clk, rst_n);
	TBInterface ReqAckWrite(clk, rst_n);
	TBInterface ReqAckRead(clk, rst_n);

	CLOCK CLOCK1(clk);
	FrameController #(0, 0, color_width, im_width, im_height, addr_width, ram_read_latency)
		FramePipelineWrite(
			PipelineWrite.clk, PipelineWrite.rst_n, PipelineWrite.in_enable, PipelineWrite.in_data, 
			PipelineWrite.out_ready, PipelineWrite.out_data, PipelineWrite.ram_addr
			);
	FrameController #(0, 1, color_width, im_width, im_height, addr_width, ram_read_latency)
		FramePipelineRead(
			PipelineRead.clk, PipelineRead.rst_n, PipelineRead.in_enable, PipelineRead.in_data, 
			PipelineRead.out_ready, PipelineRead.out_data, PipelineRead.ram_addr
			);
	FrameController #(1, 0, color_width, im_width, im_height, addr_width, ram_read_latency)
		FrameReqAckWrite(
			ReqAckWrite.clk, ReqAckWrite.rst_n, ReqAckWrite.in_enable, ReqAckWrite.in_data, 
			ReqAckWrite.out_ready, ReqAckWrite.out_data, ReqAckWrite.ram_addr
			);
	FrameController #(1, 1, color_width, im_width, im_height, addr_width, ram_read_latency)
		FrameReqAckRead(
			ReqAckRead.clk, ReqAckRead.rst_n, ReqAckRead.in_enable, ReqAckRead.in_data, 
			ReqAckRead.out_ready, ReqAckRead.out_data, ReqAckRead.ram_addr
			);
	//Write clock must be in the middle of data and address !
	BRam8x512x512 PipelineBRam(
		~clk, PipelineWrite.out_ready, PipelineWrite.ram_addr, PipelineWrite.out_data, 
		~clk, PipelineRead.ram_addr, PipelineRead.in_data);
	BRam8x512x512 ReqAckBRam(
		~clk, ReqAckWrite.out_ready, ReqAckWrite.ram_addr, ReqAckWrite.out_data, 
		~clk, ReqAckRead.ram_addr, ReqAckRead.in_data);
	task init_file();
		//Keep conf
		fst = $fscanf(fi, "%s", imconf);
		$fwrite(fo, "%s\n", imconf);
		fst = $fscanf(fi, "%s", imconf);
		$fwrite(fo, "%s\n", imconf);
	endtask : init_file

	task init_signal();
		rst_n = 0;
		now_start = 0;
		PipelineWrite.in_enable = 0;
		PipelineRead.in_enable = 0;
		ReqAckWrite.in_enable = 0;
		ReqAckRead.in_enable = 0;
		repeat(10) @(posedge clk);
		rst_n = 1;
	endtask : init_signal

	task work_pipelineW();
		@(posedge clk);
		PipelineWrite.in_enable = 1;
		fst = $fscanf(fi, "%b", PipelineWrite.in_data);
		if(PipelineWrite.out_ready) begin
			if(~now_start)
				$display("%m: at time %0t ps , %s-pipeline writing start !", $time, ftmp);
			now_start = 1;
		end
	endtask : work_pipelineW

	task work_pipelineR();
		@(posedge clk);
		PipelineRead.in_enable = 1;
		if(PipelineRead.out_ready) begin
			$fwrite(fo, "%0d\n", PipelineRead.out_data);
			if(~now_start)
				$display("%m: at time %0t ps , %s-pipeline reading start !", $time, ftmp);
			now_start = 1;
		end
	endtask : work_pipelineR

	task work_regackW();
		@(posedge clk);
		ReqAckWrite.in_enable = 1;
		fst = $fscanf(fi, "%b", ReqAckWrite.in_data);
		while (~ReqAckWrite.out_ready)
			@(posedge clk);
		if(~now_start)
			$display("%m: at time %0t ps , %s-reqack writing start !", $time, ftmp);
		now_start = 1;
		ReqAckWrite.in_enable = 0;
	endtask : work_regackW

	task work_regackR();
		@(posedge clk);
		ReqAckRead.in_enable = 1;
		while (~ReqAckRead.out_ready)
			@(posedge clk);
		$fwrite(fo, "%0d\n", ReqAckRead.out_data);
		if(~now_start)
			$display("%m: at time %0t ps , %s-reqack reading start !", $time, ftmp);
		now_start = 1;
		ReqAckRead.in_enable = 0;
	endtask : work_regackR

	initial begin
		fi = $fopen("imgindex.dat","r");
		while (!$feof(fi)) begin
			fst = $fscanf(fi, "%s", ftmp);
			fname.push_front(ftmp);
		end
		$fclose(fi);
		fsize = fname.size();
		repeat(5000) @(posedge clk);
		for (int i = 0; i < fsize; i++) begin;
			ftmp = fname.pop_back();
			fi = $fopen({ftmp, ".dat"}, "r");
			fo = $fopen({ftmp, "-pipeline.res"}, "w");
			init_file();
			init_signal();
			while (!$feof(fi)) begin 
				work_pipelineW();
			end
			init_signal();
			for (int j = 0; j < im_width * im_height; j++) begin
				work_pipelineR();
			end
			$fclose(fi);
			$fclose(fo);
			fi = $fopen({ftmp, ".dat"}, "r");
			fo = $fopen({ftmp, "-reqack.res"}, "w");
			init_file();
			init_signal();
			while (!$feof(fi)) begin 
				work_regackW();
			end
			init_signal();
			for (int j = 0; j < im_width * im_height; j++) begin
				work_regackR();
			end
			$fclose(fi);
			$fclose(fo);
		end
		$finish;
	end

endmodule