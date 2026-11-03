
module seg_scan(
	input           clk,
	input           rst_n,
	output reg[5:0] seg_sel,      //digital led chip select
	output reg[7:0] seg_data,     //eight segment digital tube output,MSB is the decimal point
	input[7:0]      photo_seg,
	input[1:0]      photo_index,
	input           auto_active,
	input           load_busy
);
parameter PHASE_FREQ = 400;    //400 Hz phase rate: no visible flicker
parameter CLK_FREQ = 50000000; //clock frequency

parameter PHASE_COUNT = CLK_FREQ / PHASE_FREQ - 1;

reg[31:0] phase_timer;
reg[1:0]  phase;
reg[5:0]  load_blink_count;
reg[7:0]  led_red_status;

always@(posedge clk or negedge rst_n)
begin
	if(rst_n == 1'b0)
	begin
		phase_timer <= 32'd0;
		phase <= 2'd0;
		load_blink_count <= 6'd0;
	end
	else if(phase_timer >= PHASE_COUNT)
	begin
		phase_timer <= 32'd0;
		phase <= phase + 2'd1;
		if (phase == 2'd3)
			load_blink_count <= load_blink_count + 6'd1;
	end
	else
		phase_timer <= phase_timer + 32'd1;
end

// The digital-tube position switch SW6 selects the photo index 1..4.
// The red LED status bits share the same output slots and blink while loading.
always @(*)
begin
	led_red_status = 8'h00;
	if (load_busy && load_blink_count[5])
		led_red_status[5:2] = 4'b1111;
	else if (auto_active)
		led_red_status[5:2] = 4'b1111;
	else begin
		case (photo_index)
			2'd0: led_red_status[2] = 1'b1;
			2'd1: led_red_status[3] = 1'b1;
			2'd2: led_red_status[4] = 1'b1;
			default: led_red_status[5] = 1'b1;
		endcase
	end
end

always@(posedge clk or negedge rst_n)
begin
	if(!rst_n) begin
		seg_sel <= 6'b11_1111;
		seg_data <= 8'hff;
	end else if (phase == 2'd0) begin
		// SW6 in digital-tube position: rightmost digit shows photo 1..4.
		seg_sel <= 6'b01_1111;
		seg_data <= photo_seg;
	end else begin
		// These phases blank the digit positions and output the red LED status bits.
		seg_sel <= 6'b11_1111;
		seg_data <= led_red_status;
	end
end

endmodule
