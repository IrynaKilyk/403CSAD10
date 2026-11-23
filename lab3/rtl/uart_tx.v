`timescale 1ns/1ps
// =============================================================================
// Модуль:      uart_tx
// Призначення: Передавач UART, формат кадру 8N1:
//              1 старт-біт (0), 8 біт даних (молодший біт першим),
//              без біта парності, 1 стоп-біт (1).
// FSM:         IDLE -> START -> DATA (x8) -> STOP -> IDLE
// =============================================================================
module uart_tx #(
    parameter integer OVERSAMPLE = 16       // Тиків baud_gen на один біт
)(
    input  wire       clk,       // Системний такт
    input  wire       rst,       // Синхронне скидання
    input  wire       tick,      // Строб від baud_gen (BAUD*OVERSAMPLE)
    input  wire       tx_start,  // Імпульс запуску передачі (1 такт)
    input  wire [7:0] tx_data,   // Байт для передачі
    output reg        txd,       // Послідовний вихід (лінія TX), у спокої = 1
    output wire       tx_busy,   // 1 - йде передача
    output reg        tx_done    // Імпульс 1 такт - кадр передано
);
    // ---- Кодування станів FSM ----
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0] state;
    reg [3:0] tick_cnt;   // Лічильник тиків усередині одного біта (0..15)
    reg [2:0] bit_idx;    // Номер поточного біта даних (0..7)
    reg [7:0] shreg;      // Зсувний регістр з даними, що передаються

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            txd      <= 1'b1;
            tick_cnt <= 0;
            bit_idx  <= 0;
            shreg    <= 8'h00;
            tx_done  <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                // Очікування команди. Лінія в стані "1" (mark).
                S_IDLE: begin
                    txd <= 1'b1;
                    if (tx_start) begin
                        shreg    <= tx_data;   // Захоплюємо байт
                        tick_cnt <= 0;
                        state    <= S_START;
                    end
                end
                // Старт-біт: лінія = 0 протягом одного біта
                S_START: begin
                    txd <= 1'b0;
                    if (tick) begin
                        if (tick_cnt == OVERSAMPLE-1) begin
                            tick_cnt <= 0;
                            bit_idx  <= 0;
                            state    <= S_DATA;
                        end else
                            tick_cnt <= tick_cnt + 1'b1;
                    end
                end
                // Біти даних, LSB першим
                S_DATA: begin
                    txd <= shreg[0];
                    if (tick) begin
                        if (tick_cnt == OVERSAMPLE-1) begin
                            tick_cnt <= 0;
                            shreg    <= {1'b0, shreg[7:1]}; // Зсув вправо
                            if (bit_idx == 3'd7)
                                state <= S_STOP;
                            else
                                bit_idx <= bit_idx + 1'b1;
                        end else
                            tick_cnt <= tick_cnt + 1'b1;
                    end
                end
                // Стоп-біт: лінія = 1
                S_STOP: begin
                    txd <= 1'b1;
                    if (tick) begin
                        if (tick_cnt == OVERSAMPLE-1) begin
                            tick_cnt <= 0;
                            tx_done  <= 1'b1;
                            state    <= S_IDLE;
                        end else
                            tick_cnt <= tick_cnt + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
