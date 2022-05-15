package eg_frames;

logic [31:0] eg_tx_data[$] = {
32'h07070707,
32'h07070707,
32'h555555fb,
32'hd5555555,
32'h77200008,
32'h8b0e3805,
32'h00000000,
32'h00450008,
32'h661c2800,
32'h061b0000,
32'h0000d79e,
32'h00004d59,
32'h2839d168,
32'h0000eb4a,
32'h00007730,
32'h12500c7a,
32'h8462d21e,
32'h00000000,
32'h00000000,
32'h79f7eb93,
32'h070707fd,
32'h07070707};

logic [3:0] eg_tx_ctl[$] = {
    4'b1111,
    4'b1111,
    4'b0001,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b0000,
    4'b1111,
    4'b1111
};


logic [63:0] eg_rx_data[$] = {
    64'h000000000000001e,
    64'hd555555555555578,
    64'h8b0e380577200008,
    64'h0045000800000000,
    64'h061b0000661c2800,
    64'h00004d590000d79e,
    64'h0000eb4a2839d168,
    64'h12500c7a00007730,
    64'h000000008462d21e,
    64'h79f7eb9300000000,
    64'h0000000000000087
};

logic [1:0] eg_rx_header[$] = {
    2'b01,
    2'b01,
    2'b10,
    2'b10,
    2'b10,
    2'b10,
    2'b10,
    2'b10,
    2'b10,
    2'b10,
    2'b01
};

endpackage