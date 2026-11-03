`timescale 1ns/1ps
// 独热状态机编码、状态内故障优先级，不改变数据通路延迟。
// 刷新服务串行化，数据通路保持原有控制器。
// 关闭原生自动刷新，全部刷新统一走 App_ref_req 请求。
// 周期暂停只能在一段完整的四字应用突发之后开始。
module mm_sdram_refresh_scheduler(
 input Sdr_clk, Sdr_clk_sft, Rst,
 output Sdr_init_done, Sdr_init_ref_vld, Sdr_busy,
 input App_wr_en, input [20:0] App_wr_addr,
 input [3:0] App_wr_dm, input [31:0] App_wr_din,
 input App_rd_en, input [20:0] App_rd_addr,
 output Sdr_rd_en, output [31:0] Sdr_rd_dout,
 output SDRAM_CLK, SDR_RAS, SDR_CAS, SDR_WE,
 output [1:0] SDR_BA, output [10:0] SDR_ADDR,
 output [3:0] SDR_DM, inout [31:0] SDR_DQ
);
 wire native_init_done /* synthesis keep=true */;
 wire native_ref_busy /* synthesis keep=true */;
 wire native_busy /* synthesis keep=true */;
 wire native_rd_en;
 wire [31:0] native_rd_dout;

 // Isolate the scheduler control reset from the encrypted controller's large
 // reset tree. Assertion remains asynchronous; release is one local clock
 // later, after the native controller has already left reset.
 (* async_reg="true" *) reg scheduler_rst = 1'b1;
 always @(posedge Sdr_clk or posedge Rst) begin
   if(Rst) scheduler_rst <= 1'b1;
   else scheduler_rst <= 1'b0;
 end

 localparam [8:0] WAIT_NATIVE=9'b000000001, WAIT_IDLE=9'b000000010,
                  REQUEST_REFRESH=9'b000000100, WAIT_REFRESH_RISE=9'b000001000,
                  WAIT_REFRESH_FALL=9'b000010000, RECOVER_REFRESH=9'b000100000,
                  RUN_APPLICATION=9'b001000000, DRAIN_APPLICATION=9'b010000000,
                  FAILED_CLOSED=9'b100000000;
 reg [8:0] scheduler_state /* synthesis keep=true */;
 reg [1:0] bootstrap_refreshes /* synthesis keep=true */;
 reg [2:0] recovery_remaining;
 reg [3:0] drain_remaining;
 reg runtime_started /* synthesis keep=true */;
 reg [10:0] period_count /* synthesis keep=true */;
 reg refresh_pending /* synthesis keep=true */;
 reg [1:0] accepted_mod4 /* synthesis keep=true */;
 reg burst_is_write /* synthesis keep=true */;
 reg scheduler_overdue /* synthesis keep=true */;
 reg scheduler_protocol_fault /* synthesis keep=true */;

 // Count0..1499 continuously after bootstrap: one tick every1500 cycles=12us.
 // Neither application busy nor an in-progress refresh resets this clock.
 // 提前一拍比较计数器，保持原有的节拍周期。
 reg period_tick_q;
 always @(posedge Sdr_clk) begin
   if(scheduler_rst || !native_init_done || !runtime_started) period_tick_q<=1'b0;
   else period_tick_q <= (period_count==11'd1498);
 end
 wire period_tick = runtime_started && period_tick_q;
 wire need_refresh = refresh_pending || period_tick;
 wire faulted = scheduler_overdue || scheduler_protocol_fault;
 wire public_ready = runtime_started && native_init_done && !scheduler_rst && !faulted;
 // Pending refresh stops new groups, but allows the remaining1..3 words of
 // an already accepted BL4 group. It never waits for a whole128-word block.
 wire application_window = public_ready &&
                           (scheduler_state[6]) &&
                           (!need_refresh || accepted_mod4!=2'd0);
 wire native_available = !native_busy && !native_ref_busy;
 wire wrong_direction = (accepted_mod4!=2'd0) &&
                        ((burst_is_write && App_rd_en) ||
                         (!burst_is_write && App_wr_en));
 wire protocol_violation = application_window && native_available &&
                           ((App_wr_en && App_rd_en) || wrong_direction);
 wire request_legal = !(App_wr_en && App_rd_en) && !wrong_direction;
 // These are exactly the accepted interface requests counted below. The
 // upstream must retain address/data while Sdr_busy or refresh-busy is high.
 wire accept_write = application_window && native_available &&
                     request_legal && App_wr_en;
 wire accept_read = application_window && native_available &&
                    request_legal && App_rd_en;
 wire accept_word = accept_write || accept_read;
 wire scheduler_ref_request /* synthesis keep=true */;
 assign scheduler_ref_request = (scheduler_state[2]) &&
                                native_init_done && !scheduler_rst && !faulted;

 assign Sdr_init_done = public_ready;
 assign Sdr_busy = native_busy || !application_window;
 assign Sdr_init_ref_vld = native_ref_busy;
 // These two paths have no new register, mux or valid retiming.
 assign Sdr_rd_en = native_rd_en;
 assign Sdr_rd_dout = native_rd_dout;

 // Preload the inactive drain counter. It is only consumed in DRAIN_APPLICATION.
 // Entering that state still exposes15, then16 complete drain intervals, exactly as before.
 // This removes the native/app request path from the counter load mux.
 always @(posedge Sdr_clk) begin
   if(scheduler_rst || !native_init_done) drain_remaining <= 4'd0;
   else if(!scheduler_state[7]) drain_remaining <= 4'd15;
   else if(!faulted && !(period_tick && refresh_pending) && drain_remaining!=0)
     drain_remaining <= drain_remaining - 4'd1;
 end

 always @(posedge Sdr_clk) begin
   if(scheduler_rst || !native_init_done) begin
     scheduler_state <= WAIT_NATIVE;
     bootstrap_refreshes <= 2'd0;
     recovery_remaining <= 3'd0;
     runtime_started <= 1'b0;
     period_count <= 11'd0;
     refresh_pending <= 1'b0;
     accepted_mod4 <= 2'd0;
     burst_is_write <= 1'b0;
     scheduler_overdue <= 1'b0;
     scheduler_protocol_fault <= 1'b0;
   end else begin
     if(runtime_started) begin
       if(period_tick) begin
         period_count <= 11'd0;
         refresh_pending <= 1'b1;
       end else period_count <= period_count + 11'd1;
       // Clear only when the one-cycle request is delivered, never on busy.
       // A coincident new periodic tick remains pending for a later service.
       if(scheduler_state[2])
         refresh_pending <= period_tick;
     end else begin
       period_count <= 11'd0;
       refresh_pending <= 1'b0;
     end

     if(accept_word) begin
       accepted_mod4 <= accepted_mod4 + 2'd1;
       if(accepted_mod4==2'd0) burst_is_write <= accept_write;
     end

     // A second tick with an unissued request is a missed-service fault,
     // not permission to merge periodic debts or release the application.
     // Device15.6us REF deadlines are separately checked at real SDRAM pins.
     if(protocol_violation) scheduler_protocol_fault <= 1'b1;
     if(faulted ||
        (period_tick && refresh_pending)) begin
       if(period_tick && refresh_pending) scheduler_overdue <= 1'b1;
       scheduler_state <= FAILED_CLOSED;
     end else begin
       case(scheduler_state)
         WAIT_NATIVE: scheduler_state <= WAIT_IDLE;
         WAIT_IDLE: begin
           if(native_available) scheduler_state <= REQUEST_REFRESH;
         end
         REQUEST_REFRESH: scheduler_state <= WAIT_REFRESH_RISE;
         WAIT_REFRESH_RISE: begin
           if(native_ref_busy) scheduler_state <= WAIT_REFRESH_FALL;
         end
         WAIT_REFRESH_FALL: begin
           if(!native_ref_busy) begin
             if(!runtime_started)
               bootstrap_refreshes <= bootstrap_refreshes + 2'd1;
             recovery_remaining <= 3'd7;
             scheduler_state <= RECOVER_REFRESH;
           end
         end
         RECOVER_REFRESH: begin
           // Load7 at the falling observation; eight subsequent complete
           // cycles7->6->...->0->advance provide64ns before re-enabling work.
           if(recovery_remaining!=3'd0)
             recovery_remaining <= recovery_remaining - 3'd1;
           else if(native_available) begin
             if(!runtime_started) begin
               if(bootstrap_refreshes==2'd2) begin
                 runtime_started <= 1'b1;
                 period_count <= 11'd0;
                 refresh_pending <= 1'b0;
                 scheduler_state <= RUN_APPLICATION;
               end else scheduler_state <= WAIT_IDLE;
             end else if(need_refresh) begin
               // No application word was released during service/recovery.
               // Retain the same conservative drain before queued service.
               scheduler_state <= DRAIN_APPLICATION;
             end else scheduler_state <= RUN_APPLICATION;
           end
         end
         RUN_APPLICATION: begin
           // protocol_violation is identically false outside RUN_APPLICATION.
           // Localize its priority mux without changing any accepted cycle.
           if(protocol_violation) scheduler_state <= FAILED_CLOSED;
           else if(need_refresh &&
              (accepted_mod4==2'd0 ||
               (application_window && native_available && (App_wr_en || App_rd_en) && accepted_mod4==2'd3))) begin
             // This edge either accepts the fourth word or accepts nothing
             // at an already complete boundary. All subsequent inputs stop.
             scheduler_state <= DRAIN_APPLICATION;
           end
         end
         DRAIN_APPLICATION: begin
           // Sixteen full intervals after the last accepted word: enough
           // for the unchanged10-cycle valid/11-cycle FIFO consume contract,
           // with extra command/precharge margin to be verified at the pins.
           if(drain_remaining==4'd0) scheduler_state <= WAIT_IDLE;
         end
         FAILED_CLOSED: scheduler_state <= FAILED_CLOSED;
         default: begin
           scheduler_protocol_fault <= 1'b1;
           scheduler_state <= FAILED_CLOSED;
         end
       endcase
     end
   end
 end

 sdr_as_ram #(.self_refresh_open(1'b0)) original_controller(
  .Sdr_clk(Sdr_clk), .Sdr_clk_sft(Sdr_clk_sft), .Rst(Rst),
  .Sdr_init_done(native_init_done), .Sdr_init_ref_vld(native_ref_busy),
  .Sdr_busy(native_busy), .App_ref_req(scheduler_ref_request),
  .App_wr_en(accept_write), .App_wr_addr(App_wr_addr),
  .App_wr_dm(App_wr_dm), .App_wr_din(App_wr_din),
  .App_rd_en(accept_read), .App_rd_addr(App_rd_addr),
  .Sdr_rd_en(native_rd_en), .Sdr_rd_dout(native_rd_dout),
  .SDRAM_CLK(SDRAM_CLK), .SDR_RAS(SDR_RAS), .SDR_CAS(SDR_CAS), .SDR_WE(SDR_WE),
  .SDR_BA(SDR_BA), .SDR_ADDR(SDR_ADDR), .SDR_DM(SDR_DM), .SDR_DQ(SDR_DQ)
 );
endmodule
