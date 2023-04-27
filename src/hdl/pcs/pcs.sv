`timescale 1ns/1ps
`default_nettype none
`include "code_defs_pkg.svh"

module pcs #(
    parameter SCRAMBLER_BYPASS = 0,
    parameter EXTERNAL_GEARBOX = 0,
    localparam DATA_WIDTH = 32,

    localparam DATA_NBYTES = DATA_WIDTH / 8
) (

    // Clocks
    input wire xver_rx_clk,
    input wire xver_tx_clk,
    
    // Reset logic
    input wire tx_reset,
    input wire rx_reset,

    // Rx from tranceiver
    input wire [DATA_WIDTH-1:0] xver_rx_data,
    input wire [1:0] xver_rx_header,
    input wire xver_rx_data_valid,
    input wire xver_rx_header_valid,
    output wire xver_rx_gearbox_slip,

    // Rx XGMII
    output logic [DATA_WIDTH-1:0] xgmii_rx_data,
    output logic [DATA_NBYTES-1:0] xgmii_rx_ctl,
    output logic xgmii_rx_valid, // Non standard XGMII - required for no CDC
    output logic [DATA_NBYTES-1:0] term_loc,
    
    // Tx XGMII
    input wire[DATA_WIDTH-1:0] xgmii_tx_data,
    input wire[DATA_NBYTES-1:0] xgmii_tx_ctl,
    output wire xgmii_tx_ready, // Non standard XGMII - required for no CDC

    // TX Interface out
    output wire [DATA_WIDTH-1:0] xver_tx_data,
    output wire [1:0] xver_tx_header,
    output wire [5:0] xver_tx_gearbox_sequence
);

    import code_defs_pkg::*;

    // ************* TX DATAPATH ************* //
    wire [DATA_WIDTH-1:0] tx_encoded_data, tx_scrambled_data;
    wire [1:0] tx_header;
    wire tx_gearbox_pause;
    wire [DATA_WIDTH-1:0] rx_decoded_data;
    wire [DATA_NBYTES-1:0] rx_decoded_ctl;
    wire rx_data_valid, rx_header_valid;
    wire enc_frame_word;

    // Encoder
    encoder u_encoder (
        .i_reset(tx_reset),
        .i_init_done(!tx_reset),
        .i_txc(xver_tx_clk),
        .i_txd(xgmii_tx_data),
        .i_txctl(xgmii_tx_ctl),
        .i_tx_pause(tx_gearbox_pause),
        .i_frame_word(enc_frame_word),
        .o_txd(tx_encoded_data),
        .o_tx_header(tx_header)
    );
    
    // Scrambler
    generate
        if(SCRAMBLER_BYPASS) begin
            assign tx_scrambled_data = tx_encoded_data;
        end else begin

            // Delay the scrambler reset if 32-bit interface
            // TODO this only helps with tb?
            logic scram_reset;
            always @ (posedge xver_tx_clk)
                scram_reset <= tx_reset;

            scrambler #(
            ) u_scrambler(
                .clk(xver_tx_clk),
                .reset(scram_reset),
                .init_done(!tx_reset),
                .pause(tx_gearbox_pause),
                .idata(tx_encoded_data),
                .odata(tx_scrambled_data)
            );
        end
    endgenerate

    // Gearbox
    generate
        if (EXTERNAL_GEARBOX) begin

            assign xver_tx_data = tx_scrambled_data;
            assign xver_tx_header = tx_header;

            // This assumes gearbox counter counting every other TXUSRCLK when 
            //      TX_DATAWIDTH == TX_INT_DATAWIDTH == 32 ref UG578 v1.3.1 pg 120 on
            gearbox_seq #(.WIDTH(6), .MAX_VAL(32), .PAUSE_VAL(32), .HALF_STEP(1)) 
            u_tx_gearbox_seq (
                .clk(xver_tx_clk),
                .reset(tx_reset),
                .slip(1'b0),
                .count(xver_tx_gearbox_sequence),
                .pause(tx_gearbox_pause)
            );
            
            assign enc_frame_word = xver_tx_gearbox_sequence[0];

        end else begin

            wire [5:0] int_tx_gearbox_seq;

            gearbox_seq #(.WIDTH(6), .MAX_VAL(32), .PAUSE_VAL(32), .HALF_STEP(0)) 
            u_tx_gearbox_seq (
                .clk(xver_tx_clk),
                .reset(tx_reset),
                .slip(1'b0),
                .count(int_tx_gearbox_seq),
                .pause(tx_gearbox_pause)
            );

            tx_gearbox u_tx_gearbox (
                .i_clk(xver_tx_clk),
                .i_reset(tx_reset),
                .i_data(tx_scrambled_data),
                .i_header(tx_header),
                .i_gearbox_seq(int_tx_gearbox_seq), 
                .i_pause(tx_gearbox_pause),
                .o_frame_word(enc_frame_word),
                .o_data(xver_tx_data)
            );

            assign xver_tx_gearbox_sequence = '0;
            assign xver_tx_header = '0;
            
        end 
    endgenerate

    assign xgmii_tx_ready = !tx_gearbox_pause;

    /// ************* RX DATAPATH ************* //
    wire [DATA_WIDTH-1:0] rx_gearbox_data_out, rx_descrambled_data;
    wire [1:0] rx_header;
    wire rx_gearbox_slip;

    generate
        if (EXTERNAL_GEARBOX) begin

            assign xver_rx_gearbox_slip = rx_gearbox_slip;
            assign rx_gearbox_data_out = xver_rx_data;
            assign rx_header = xver_rx_header;
            assign rx_data_valid = xver_rx_data_valid;
            assign rx_header_valid = xver_rx_header_valid;

        end else begin
            wire [5:0] int_rx_gearbox_seq;
            wire rx_gearbox_pause;

            rx_gearbox #(.REGISTER_OUTPUT(1)) 
            u_rx_gearbox (
                .i_clk(xver_rx_clk),
                .i_reset(tx_reset),
                .i_data(xver_rx_data),
                .i_slip(rx_gearbox_slip),
                .o_data(rx_gearbox_data_out),
                .o_header(rx_header),
                .o_data_valid(rx_data_valid),
                .o_header_valid(rx_header_valid)
            );

            assign xver_rx_gearbox_slip = 1'b0;
            
        end
    endgenerate

    // Lock state machine
    lock_state u_lock_state(
        .i_clk(xver_rx_clk),
        .i_reset(rx_reset),
        .i_header(rx_header),
        .i_valid(rx_header_valid),
        .o_slip(rx_gearbox_slip)
    );

    // Descrambler
    generate
        if(SCRAMBLER_BYPASS) begin
            assign rx_descrambled_data = rx_gearbox_data_out;
        end else begin
            scrambler #(
                .DESCRAMBLE(1)
            ) u_descrambler(
                .clk(xver_rx_clk),
                .reset(rx_reset),
                .init_done(!rx_reset),
                .pause(!rx_data_valid),
                .idata(rx_gearbox_data_out),
                .odata(rx_descrambled_data)
            );
        end
    endgenerate

    // Decoder
    decoder #(
    ) u_decoder(
        .i_reset(rx_reset),
        .i_init_done(!rx_reset),
        .i_rxc(xver_rx_clk),
        .i_rxd(rx_descrambled_data),
        .i_rx_header(rx_header),
        .i_rx_data_valid(rx_data_valid),
        .i_rx_header_valid(rx_header_valid),
        .o_rxd(rx_decoded_data),
        .o_rxctl(rx_decoded_ctl)
    );

    // Calulate the term location here to help with timing in the MAC
    wire [DATA_NBYTES-1:0] early_term_loc;
    genvar gi;
    generate for (gi = 0; gi < DATA_NBYTES; gi++) begin
        assign early_term_loc[gi] = rx_data_valid && rx_decoded_data[gi*8 +: 8] == RS_TERM && rx_decoded_ctl[gi];
    end endgenerate

    always @(posedge xver_rx_clk)
    if (rx_reset) begin
        xgmii_rx_data <= '0;
        xgmii_rx_ctl <= '0;
        xgmii_rx_valid <= '0;
        term_loc <= '0;
    end else begin
        xgmii_rx_data <= rx_decoded_data;
        xgmii_rx_ctl <= rx_decoded_ctl;
        xgmii_rx_valid <= rx_data_valid;
        term_loc <= early_term_loc;
    end

endmodule