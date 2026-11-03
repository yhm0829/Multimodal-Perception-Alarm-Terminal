


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define SDR_CLK_HZ (125000000)
`define SDR_CLK_PERIOD (1000000000/(`SDR_CLK_HZ))
// EM638325: 4096 refreshes/64 ms; request every 12 us with scheduling headroom.
// The vendor counter includes zero, so the terminal count is cycles minus one.
`define SELF_REFRESH_INTERVAL (((`SDR_CLK_HZ/1000000)*12)-1)

