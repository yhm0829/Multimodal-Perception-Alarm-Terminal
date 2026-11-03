`timescale 1ns/1ps

// RC timing light sensor for one LDR and one 100 nF capacitor.
// Wiring: 3V3--LDR--SENSE; SENSE--100nF--GND; SENSE--1k--GPIO.
// A larger result means a darker environment.  The pin is only ever driven
// low, then released, so the FPGA never fights the 3.3 V rail.
module mm_ldr_rc_sensor #(
    parameter integer DISCHARGE_CYCLES=100000,
    parameter integer TIMEOUT_CYCLES=8000000,
    parameter integer PERIOD_CYCLES=5000000
)(
    input  wire       clk,
    input  wire       rst,
    inout  wire       light_rc,
    output reg  [7:0] darkness,
    output reg        sample_valid
);
    localparam [1:0] S_WAIT=0, S_DISCHARGE=1, S_CHARGE=2;

    reg [1:0] state;
    localparam integer WAIT_MAX=(DISCHARGE_CYCLES>PERIOD_CYCLES)?DISCHARGE_CYCLES:PERIOD_CYCLES;
    localparam integer COUNT_MAX=(WAIT_MAX>TIMEOUT_CYCLES)?WAIT_MAX:TIMEOUT_CYCLES;
    localparam integer COUNT_W=(COUNT_MAX>1)?$clog2(COUNT_MAX):1;
    reg [COUNT_W-1:0] count;
    wire [23:0] measurement_count=count; // Keep the original measurement scale.
    reg drive_low;
    reg rc_meta, rc_sync;
    assign light_rc = drive_low ? 1'b0 : 1'bz;

    always @(posedge clk or posedge rst) begin
        if (rst) begin rc_meta<=1'b0; rc_sync<=1'b0; end
        else begin rc_meta<=light_rc; rc_sync<=rc_meta; end
    end

    wire [7:0] measured=(|measurement_count[23:22])?8'd255:measurement_count[21:14];
    wire [8:0] rise_delta={1'b0,measured}-{1'b0,darkness};
    wire [8:0] fall_delta={1'b0,darkness}-{1'b0,measured};
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=S_DISCHARGE; count<=0; drive_low<=1'b1;
            darkness<=8'd0; sample_valid<=1'b0;
        end else begin
            case(state)
                S_WAIT: begin
                    drive_low<=1'b0;
                    if (count==PERIOD_CYCLES-1) begin count<=0; drive_low<=1'b1; state<=S_DISCHARGE; end
                    else count<=count+1'b1;
                end
                S_DISCHARGE: begin
                    drive_low<=1'b1;
                    if (count==DISCHARGE_CYCLES-1) begin count<=0; drive_low<=1'b0; state<=S_CHARGE; end
                    else count<=count+1'b1;
                end
                S_CHARGE: begin
                    drive_low<=1'b0;
                    if (rc_sync || count==TIMEOUT_CYCLES-1) begin
                        if (!rc_sync) sample_valid<=1'b0;
                        else begin
                        if (!sample_valid) darkness<=measured;
                        else if(measured>darkness) darkness<=darkness+((rise_delta+3)>>2);
                        else if(measured<darkness) darkness<=darkness-((fall_delta+3)>>2);
                        sample_valid<=1'b1;
                        end
                        count<=0; state<=S_WAIT;
                    end else count<=count+1'b1;
                end
                default: state<=S_DISCHARGE;
            endcase
        end
    end
endmodule
