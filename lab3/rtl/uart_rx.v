`timescale 1ns/1ps
// =============================================================================
// Модуль:      uart_rx
// Призначення: Приймач UART 8N1 з 16-кратною передискретизацією.
// Логіка:      1) Вхід rxd синхронізується двома тригерами (захист від
//                 метастабільності, бо сигнал асинхронний).
//              2) Спадаючий фронт у стані IDLE -> можливий старт-біт.
//              3) Через 8 тиків (середина біта) перевіряємо, що rxd ще 0;
//                 якщо ні - це завада, повертаємось в IDLE.
//              4) Далі кожні 16 тиків (середина кожного біта) зчитуємо біт.
//              5) У середині стоп-біта перевіряємо rxd == 1,
//                 інакше виставляємо frame_err.
// FSM:         IDLE -> START -> DATA (x8) -> STOP -> IDLE
// =============================================================================
module uart_rx #(
    parameter integer OVERSAMPLE = 16
)(
    input  wire       clk,       // Системний такт
    input  wire       rst,       // Синхронне скидання
    input  wire       tick,      // Строб від baud_gen (BAUD*OVERSAMPLE)
    input  wire       rxd,       // Послідовний вхід (лінія RX)
    output reg  [7:0] rx_data,   // Прийнятий байт
    output reg        rx_valid,  // Імпульс 1 такт - байт прийнято коректно
    output reg        frame_err  // Імпульс 1 такт - помилка стоп-біта
);
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    // ---- Двотригерний синхронізатор ----
    reg rxd_s1, rxd_s2;
    always @(posedge clk) begin
        if (rst) begin
            rxd_s1 <= 1'b1;
            rxd_s2 <= 1'b1;
        end else begin
            rxd_s1 <= rxd;
            rxd_s2 <= rxd_s1;
        end
    end

    reg [1:0] state;
    reg [3:0] tick_cnt;   // Лічильник тиків у межах біта
    reg [2:0] bit_idx;    // Номер біта даних
    reg [7:0] shreg;      // Зсувний регістр для збирання байта

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            tick_cnt  <= 0;
            bit_idx   <= 0;
            shreg     <= 8'h00;
            rx_data   <= 8'h00;
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
            case (state)
                S_IDLE: begin
                    tick_cnt <= 0;
                    if (rxd_s2 == 1'b0)       // Виявлено початок старт-біта
                        state <= S_START;
                end
                // Чекаємо середину старт-біта (OVERSAMPLE/2 тиків)
                S_START: if (tick) begin
                    if (tick_cnt == OVERSAMPLE/2 - 1) begin
                        tick_cnt <= 0;
                        if (rxd_s2 == 1'b0) begin   // Старт-біт підтверджено
                            bit_idx <= 0;
                            state   <= S_DATA;
                        end else
                            state <= S_IDLE;         // Це була завада
                    end else
                        tick_cnt <= tick_cnt + 1'b1;
                end
                // Зчитуємо біти даних у середині кожного біта
                S_DATA: if (tick) begin
                    if (tick_cnt == OVERSAMPLE-1) begin
                        tick_cnt <= 0;
                        shreg    <= {rxd_s2, shreg[7:1]}; // LSB приходить першим
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        tick_cnt <= tick_cnt + 1'b1;
                end
                // Перевірка стоп-біта
                S_STOP: if (tick) begin
                    if (tick_cnt == OVERSAMPLE-1) begin
                        tick_cnt <= 0;
                        if (rxd_s2 == 1'b1) begin
                            rx_data  <= shreg;
                            rx_valid <= 1'b1;
                        end else
                            frame_err <= 1'b1;
                        state <= S_IDLE;
                    end else
                        tick_cnt <= tick_cnt + 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
