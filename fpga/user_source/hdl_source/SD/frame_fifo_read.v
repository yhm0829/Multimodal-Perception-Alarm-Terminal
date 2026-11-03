`timescale 1ns/1ps
// SDRAM帧读取与ROI重采样模块。
// read_addr_index选择显示缓冲；zoom_mode选择100%/75%/125%/150%；roi_position选择九宫格位置。
// 75%和100%读取完整视野；125%和150%按九宫格计算起始地址，再用整数相位完成最近邻重采样。
// 多位控制总线跨入mem_clk后需连续九拍稳定，并且只在帧开始锁存，防止一帧内地址规则改变。
// 调试记录：突发完成不能用固定等待拍数判断，必须同时满足返回字数和控制器finish；
// 否则刷新或写突发插入时可能提前结束读事务，表现为横向缺行或FIFO读空。
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter FIFO_DEPTH             = 512,
	parameter BURST_SIZE             = 128,
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
)               
(
	input                            rst,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
    input							 Sdr_rd_en,
	input							 App_wr_busy,
    output							 O_rd_busy,
	/*
    output reg                       rd_burst_req,               // to external memory controller,send out a burst read request  
	output reg[BURST_BITS - 1:0]     rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes 
	output reg[ADDR_BITS - 1:0]      rd_burst_addr,              // to external memory controller,base address of the burst read request
	input                            rd_burst_data_valid,        // from external memory controller,read request data valid    
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output 							 App_rd_en,
	output  [ADDR_BITS - 1:0]		 App_rd_addr,
	
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output reg                       read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[1:0]                       read_addr_index,            // select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
	output wire [1:0]                active_zoom,
	input [3:0] roi_position,
	input[1:0]                       zoom_mode,                  // 0=100%, 1=75%, 2=125%, 3=150%
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[9:0]                      wrusedw                     // from fifo write used words

);
localparam ONE                       = 256'd1;                   //256 bit '1'   you can use ONE[n-1:0] for n bit '1'
localparam ZERO                      = 256'd0;                   //256 bit '0'
//read state machine code
localparam S_IDLE                    = 0;                        //idle state,waiting for frame read
localparam S_ACK                     = 1;                        //read request response
localparam S_CHECK_FIFO              = 2;                        //check the FIFO status, ensure that there is enough space to burst read
localparam S_READ_BURST              = 3;                        //begin a burst read
localparam S_READ_BURST_END          = 4;                        //a burst read complete
localparam S_END                     = 5;                        //a frame of data is read to complete

reg                                  read_req_d0;                //asynchronous read request, synchronize to 'mem_clk' clock domain,first beat
reg                                  read_req_d1;                //second
reg                                  read_req_d2;                //third,Why do you need 3 ? Here's the design habit
reg[ADDR_BITS - 1:0]                 read_len_d0;                //asynchronous read_len(read data length), synchronize to 'mem_clk' clock domain first
reg[ADDR_BITS - 1:0]                 read_len_d1;                //second
reg[ADDR_BITS - 1:0]                 read_len_latch;             //lock read data length
reg[ADDR_BITS - 1:0]                 read_cnt;                   //read data counter
reg[3:0]                             state;                      //state machine
reg[1:0]                             read_addr_index_d0;         //synchronize to 'mem_clk' clock domain first
reg[1:0]                             read_addr_index_d1;         //synchronize to 'mem_clk' clock domain second
reg[1:0]                             read_addr_index_stable;
reg[1:0]                             read_addr_index_candidate;
reg[3:0]                             read_addr_index_qual;
reg [ADDR_BITS - 1:0]	 App_rd_addr_r;
reg[5:0]                             zoom_mode_d0;
reg[5:0]                             zoom_mode_d1;
reg[5:0]                             zoom_mode_stable;
reg[5:0]                             zoom_mode_candidate;
reg[3:0]                             zoom_mode_qual;
reg[1:0]                             zoom_mode_latch;
assign active_zoom = zoom_mode_latch; // Only the reader's frame-latched mode controls the cache.
reg[10:0]                            zoom_out_x;
reg[9:0]                             zoom_out_y;
reg                                  zoom_y_before_active;
reg                                  zoom_y_in_active;
reg[2:0]                             zoom_x_phase;
reg[2:0]                             zoom_y_phase;
reg[ADDR_BITS-1:0]                   zoom_row_addr;

reg [1:0] roi_zoom_pre;
always @(posedge mem_clk or posedge rst)
 if(rst) roi_zoom_pre<=0;
 else roi_zoom_pre<=zoom_mode_stable[1:0];
reg [20:0] roi_row_pre,roi_start_pre;
reg [8:0] roi_x_pre,roi_x_latch;
always @(posedge mem_clk or posedge rst)
 if(rst) begin roi_row_pre<=0;roi_start_pre<=0;roi_x_pre<=0;end
 else case(zoom_mode_stable)
6'd2: begin roi_row_pre<=21'd0;roi_start_pre<=21'd0;roi_x_pre<=9'd0;end
6'd6: begin roi_row_pre<=21'd0;roi_start_pre<=21'd64;roi_x_pre<=9'd64;end
6'd10: begin roi_row_pre<=21'd0;roi_start_pre<=21'd128;roi_x_pre<=9'd128;end
6'd14: begin roi_row_pre<=21'd30720;roi_start_pre<=21'd30720;roi_x_pre<=9'd0;end
6'd18: begin roi_row_pre<=21'd30720;roi_start_pre<=21'd30784;roi_x_pre<=9'd64;end
6'd22: begin roi_row_pre<=21'd30720;roi_start_pre<=21'd30848;roi_x_pre<=9'd128;end
6'd26: begin roi_row_pre<=21'd61440;roi_start_pre<=21'd61440;roi_x_pre<=9'd0;end
6'd30: begin roi_row_pre<=21'd61440;roi_start_pre<=21'd61504;roi_x_pre<=9'd64;end
6'd34: begin roi_row_pre<=21'd61440;roi_start_pre<=21'd61568;roi_x_pre<=9'd128;end
6'd3: begin roi_row_pre<=21'd0;roi_start_pre<=21'd0;roi_x_pre<=9'd0;end
6'd7: begin roi_row_pre<=21'd0;roi_start_pre<=21'd107;roi_x_pre<=9'd107;end
6'd11: begin roi_row_pre<=21'd0;roi_start_pre<=21'd213;roi_x_pre<=9'd213;end
6'd15: begin roi_row_pre<=21'd51200;roi_start_pre<=21'd51200;roi_x_pre<=9'd0;end
6'd19: begin roi_row_pre<=21'd51200;roi_start_pre<=21'd51307;roi_x_pre<=9'd107;end
6'd23: begin roi_row_pre<=21'd51200;roi_start_pre<=21'd51413;roi_x_pre<=9'd213;end
6'd27: begin roi_row_pre<=21'd102400;roi_start_pre<=21'd102400;roi_x_pre<=9'd0;end
6'd31: begin roi_row_pre<=21'd102400;roi_start_pre<=21'd102507;roi_x_pre<=9'd107;end
6'd35: begin roi_row_pre<=21'd102400;roi_start_pre<=21'd102613;roi_x_pre<=9'd213;end
 default:begin roi_row_pre<=0;roi_start_pre<=0;roi_x_pre<=0;end
 endcase

reg [BURST_BITS - 1:0]				burst_cnt;
wire								rd_burst_finish;
reg [BURST_BITS:0]                 rd_rsp_cnt;
reg App_rd_en_r;
reg App_rd_en_d0;

assign App_rd_addr = {App_rd_addr_r[ADDR_BITS - 1:0]};

assign O_rd_busy = (state == S_READ_BURST);//读指令期间
// Complete the burst only after every requested word has returned; ending
// early could let writes interleave and leave the video FIFO short.
assign rd_burst_finish = (burst_cnt >= BURST_SIZE) &&
                         ((rd_rsp_cnt + (Sdr_rd_en ? 1'b1 : 1'b0)) >= BURST_SIZE);
assign read_finish = (state == S_END) ? 1'b1 : 1'b0;             //read finish at state 'S_END'
// Retry the same address after refresh/busy instead of advancing past a
// command the SDRAM controller could not accept.
assign App_rd_en = App_rd_en_d0 && ~App_wr_busy &&
                   ~Sdr_busy && ~Sdr_init_ref_vld;
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d0 <= 0;
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d1 <= 0;
		read_addr_index_d0 <= 2'b00;
		read_addr_index_d1 <= 2'b00;
		read_addr_index_stable <= 2'b00;
		read_addr_index_candidate <= 2'b00;
		read_addr_index_qual <= 4'd0;
		zoom_mode_d0 <= 2'b00;
		zoom_mode_d1 <= 2'b00;
		zoom_mode_stable <= 2'b00;
		zoom_mode_candidate <= 2'b00;
		zoom_mode_qual <= 4'd0;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;     
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0; 
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;
		zoom_mode_d0 <= {roi_position,zoom_mode};
		zoom_mode_d1 <= zoom_mode_d0;
		// Multi-bit controls cross from unrelated clock domains.  Adopt a new
		// value only after the synchronized bus remains unchanged for nine
		// mem_clk cycles, preventing a mixed buffer/zoom value at frame start.
		if(read_addr_index_d1 == read_addr_index_stable) begin
			read_addr_index_qual <= 4'd0;
			read_addr_index_candidate <= read_addr_index_d1;
		end else if(read_addr_index_d1 != read_addr_index_candidate) begin
			read_addr_index_candidate <= read_addr_index_d1;
			read_addr_index_qual <= 4'd1;
		end else if(read_addr_index_qual == 4'd8) begin
			read_addr_index_stable <= read_addr_index_d1;
			read_addr_index_qual <= 4'd0;
		end else
			read_addr_index_qual <= read_addr_index_qual + 1'b1;

		if(zoom_mode_d1 == zoom_mode_stable) begin
			zoom_mode_qual <= 4'd0;
			zoom_mode_candidate <= zoom_mode_d1;
		end else if(zoom_mode_d1 != zoom_mode_candidate) begin
			zoom_mode_candidate <= zoom_mode_d1;
			zoom_mode_qual <= 4'd1;
		end else if(zoom_mode_qual == 4'd8) begin
			zoom_mode_stable <= zoom_mode_d1;
			zoom_mode_qual <= 4'd0;
		end else
			zoom_mode_qual <= zoom_mode_qual + 1'b1;
	end 
end

always @(posedge mem_clk or posedge rst)
begin
    if(rst)
        rd_rsp_cnt <= {(BURST_BITS+1){1'b0}};
    else if(state == S_CHECK_FIFO)
        rd_rsp_cnt <= {(BURST_BITS+1){1'b0}};
    else if((state == S_READ_BURST) && Sdr_rd_en)
        rd_rsp_cnt <= rd_rsp_cnt + 1'b1;
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_rd_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_rd_en_d0 <= 1'b0;
		zoom_mode_latch <= 2'd0;roi_x_latch<=0;
		zoom_out_x <= 11'd0;
		zoom_out_y <= 10'd0;
		zoom_y_before_active <= 1'b1;
		zoom_y_in_active <= 1'b0;
		zoom_x_phase <= 3'd0;
		zoom_y_phase <= 3'd0;
		zoom_row_addr <= {ADDR_BITS{1'b0}};
	end
	else begin
	
		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_rd_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;
		//
		if(state == S_ACK)
			begin
				zoom_mode_latch <= roi_zoom_pre;
                roi_x_latch <= roi_x_pre;
				zoom_out_x <= 11'd0;
				zoom_out_y <= 10'd0;
				zoom_y_before_active <= 1'b1;
				zoom_y_in_active <= 1'b0;
				zoom_x_phase <= 3'd0;
				zoom_y_phase <= 3'd0;
				if(read_addr_index_stable == 2'd0)
					begin
						zoom_row_addr <= read_addr_0 + roi_start_pre;
						App_rd_addr_r <= read_addr_0 + roi_start_pre;
					end
				else if(read_addr_index_stable == 2'd1)
					begin
						zoom_row_addr <= read_addr_1 + roi_start_pre;
						App_rd_addr_r <= read_addr_1 + roi_start_pre;
					end
				else if(read_addr_index_stable == 2'd2)
					begin
						zoom_row_addr <= read_addr_2 + roi_start_pre;
						App_rd_addr_r <= read_addr_2 + roi_start_pre;
					end
				else if(read_addr_index_stable == 2'd3)
					begin
						zoom_row_addr <= read_addr_3 + roi_start_pre;
						App_rd_addr_r <= read_addr_3 + roi_start_pre;
					end
			end
		else if(App_rd_en)
			begin
				// 保持原突发握手状态机，只重映射读地址序列；
				// 缓冲切换仍与缩放、手动/自动轮播相互独立。
				if(zoom_out_x == FRAME_WIDTH-1) begin
					zoom_out_x <= 11'd0;
					zoom_out_y <= zoom_out_y + 1'b1;
					zoom_y_before_active <= ((zoom_out_y + 1'b1) < 10'd60);
					zoom_y_in_active <= (((zoom_out_y + 1'b1) >= 10'd60) &&
					                     ((zoom_out_y + 1'b1) < 10'd419));
					zoom_x_phase <= 3'd0;
					case(zoom_mode_latch)
						2'd0: begin
							zoom_row_addr <= zoom_row_addr + FRAME_WIDTH;
							App_rd_addr_r <= zoom_row_addr + FRAME_WIDTH;
						end
						2'd1: begin
							if(zoom_y_before_active) begin
								App_rd_addr_r <= zoom_row_addr;
							end else if(zoom_y_in_active) begin
								if(zoom_y_phase==3'd2) begin
									zoom_y_phase<=0; zoom_row_addr<=zoom_row_addr+21'd1280;
									App_rd_addr_r<=zoom_row_addr+21'd1280;
								end else begin
									zoom_y_phase<=zoom_y_phase+1'b1; zoom_row_addr<=zoom_row_addr+21'd640;
									App_rd_addr_r<=zoom_row_addr+21'd640;
								end
							end else App_rd_addr_r <= zoom_row_addr;
						end
						2'd2: begin
							if(zoom_y_phase==0) zoom_y_phase<=3'd4;
							else begin zoom_y_phase<=zoom_y_phase-1'b1; zoom_row_addr<=zoom_row_addr+21'd640; end
							App_rd_addr_r <= ((zoom_y_phase==0)?zoom_row_addr:(zoom_row_addr+21'd640));
						end
						default: begin
							if(zoom_y_phase==0) zoom_y_phase<=3'd2;
							else begin zoom_y_phase<=zoom_y_phase-1'b1; zoom_row_addr<=zoom_row_addr+21'd640; end
							App_rd_addr_r <= ((zoom_y_phase==0)?zoom_row_addr:(zoom_row_addr+21'd640));
						end
					endcase
				end else begin
					zoom_out_x <= zoom_out_x + 1'b1;
					case(zoom_mode_latch)
						2'd0: App_rd_addr_r <= App_rd_addr_r + 1'b1;
						2'd1: begin
							if(zoom_out_x < 11'd80) App_rd_addr_r <= zoom_row_addr;
							else if(zoom_out_x < 11'd559) begin
								if(zoom_x_phase==3'd2) begin zoom_x_phase<=0; App_rd_addr_r<=App_rd_addr_r+2; end
								else begin zoom_x_phase<=zoom_x_phase+1'b1; App_rd_addr_r<=App_rd_addr_r+1'b1; end
							end
						end
						2'd2: begin
							if(zoom_x_phase==0) zoom_x_phase<=3'd4;
							else begin zoom_x_phase<=zoom_x_phase-1'b1; App_rd_addr_r<=App_rd_addr_r+1'b1; end
						end
						default: begin
							if(zoom_x_phase==0) zoom_x_phase<=3'd2;
							else begin zoom_x_phase<=zoom_x_phase-1'b1; App_rd_addr_r<=App_rd_addr_r+1'b1; end
						end
					endcase
				end
			end
		else
			App_rd_addr_r <= App_rd_addr_r;
		//
		if(App_rd_en_r && ((!App_rd_en && burst_cnt < BURST_SIZE) || (App_rd_en && burst_cnt + 1'b1 < BURST_SIZE)))
			App_rd_en_d0 <= 1'b1;
		else
			App_rd_en_d0 <= 1'b0;
	
	end		
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];
		
		//rd_burst_addr <= ZERO[ADDR_BITS - 1:0];
		//rd_burst_req <= 1'b0;
		App_rd_en_r <= 1'b0;
		
		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		//rd_burst_len <= ZERO[BURST_BITS - 1:0];
		read_req_ack <= 1'b0;
	end
	else
		case(state)
			//idle state,waiting for read, read_req_d2 == '1' goto the 'S_ACK'
			S_IDLE:
			begin
				if(read_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end
			//'S_ACK' state completes the read request response, the FIFO reset, the address latch, and the data length latch
			S_ACK:
			begin
				if(read_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin
					//read request response
					read_req_ack <= 1'b1;
					//FIFO reset
					fifo_aclr <= 1'b1;
					//select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
					/*
					if(read_addr_index_d1 == 2'd0)
						App_rd_addr <= read_addr_0;
					else if(read_addr_index_d1 == 2'd1)
						App_rd_addr <= read_addr_1;
					else if(read_addr_index_d1 == 2'd2)
						App_rd_addr <= read_addr_2;
					else if(read_addr_index_d1 == 2'd3)
						App_rd_addr <= read_addr_3;
					*/
					//latch data length
					read_len_latch <= read_len_d1;
				end
				//read data counter reset, read_cnt <= 0;
				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the FIFO space is a burst read request, goto burst read state
				else if(wrusedw < (FIFO_DEPTH - BURST_SIZE) && ~App_wr_busy &&
				        ~Sdr_busy && ~Sdr_init_ref_vld)
				begin
					state <= S_READ_BURST;
					//rd_burst_len <= BURST_SIZE[BURST_BITS - 1:0];
					//rd_burst_req <= 1'b1;
					App_rd_en_r <= 1'b1;
				end
			end
			
			S_READ_BURST:
			begin
				//burst finish  
				if(rd_burst_finish == 1'b1)
				begin
					App_rd_en_r <= 1'b0;
					state <= S_READ_BURST_END;
					//read counter + burst length
					read_cnt <= read_cnt + BURST_SIZE[ADDR_BITS - 1:0];
					//the next burst read address is generated
					//rd_burst_addr <= rd_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_READ_BURST_END:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the read counter value is less than the frame length, continue read,
				//otherwise the read is complete
				else if(read_cnt < read_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule
