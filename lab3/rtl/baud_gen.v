`timescale 1ns/1ps
// =============================================================================
// Модуль:      baud_gen
// Призначення: Дільник тактової частоти для UART.
//              Генерує однотактові імпульси tick з частотою BAUD * OVERSAMPLE.
//              Передавач використовує кожен 16-й tick (1 біт),
//              приймач - кожен tick (16 вибірок на біт) для точного прийому.
// =============================================================================
module baud_gen #(
    parameter integer CLK_FREQ   = 50_000_000, // Частота системного такту, Гц
    parameter integer BAUD_RATE  = 115_200,    // Баудова швидкість, біт/с
    parameter integer OVERSAMPLE = 16          // Коефіцієнт передискретизації
)(
    input  wire clk,    // Системний тактовий сигнал
    input  wire rst,    // Синхронне скидання (активний 1)
    output reg  tick    // Строб: 1 такт тривалістю, частота BAUD*OVERSAMPLE
);
    // Кількість тактів clk між двома tick (з округленням)
    localparam integer DIVISOR = (CLK_FREQ + (BAUD_RATE*OVERSAMPLE)/2)
                                 / (BAUD_RATE*OVERSAMPLE);
    localparam integer CNT_W   = $clog2(DIVISOR);

    reg [CNT_W-1:0] cnt;   // Лічильник тактів

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= 0;
            tick <= 1'b0;
        end else if (cnt == DIVISOR-1) begin
            cnt  <= 0;
            tick <= 1'b1;          // Видаємо строб
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end
endmodule
