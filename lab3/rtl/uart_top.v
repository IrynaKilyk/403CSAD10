`timescale 1ns/1ps
// =============================================================================
// Модуль:      uart_top
// Призначення: Верхній рівень: об'єднує дільник частоти, передавач і приймач.
//              Саме цей модуль синтезується для ПЛІС.
// =============================================================================
module uart_top #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    // Інтерфейс передавача
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire       txd,
    output wire       tx_busy,
    output wire       tx_done,
    // Інтерфейс приймача
    input  wire       rxd,
    output wire [7:0] rx_data,
    output wire       rx_valid,
    output wire       frame_err
);
    wire tick;

    baud_gen #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .OVERSAMPLE(16))
    u_baud (.clk(clk), .rst(rst), .tick(tick));

    uart_tx #(.OVERSAMPLE(16))
    u_tx (.clk(clk), .rst(rst), .tick(tick),
          .tx_start(tx_start), .tx_data(tx_data),
          .txd(txd), .tx_busy(tx_busy), .tx_done(tx_done));

    uart_rx #(.OVERSAMPLE(16))
    u_rx (.clk(clk), .rst(rst), .tick(tick), .rxd(rxd),
          .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err));
endmodule
