// =============================================================================
// Тестбенч:    tb_uart
// Що перевіряє:
//   Тест 1 (loopback): вихід txd з'єднано з входом rxd. Передаємо набір байтів
//                      і перевіряємо, що приймач отримав ті самі байти.
//   Тест 2 (зовнішній пристрій): лінію rxd керує задача send_byte, що
//                      імітує інший UART-пристрій (окремо від нашого Tx).
//   Тест 3 (помилка кадру): надсилаємо кадр зі стоп-бітом = 0,
//                      очікуємо frame_err.
// =============================================================================
`timescale 1ns/1ps

module tb_uart;
    // ---- Параметри ----
    localparam integer CLK_FREQ  = 50_000_000;          // 50 МГц
    localparam integer BAUD_RATE = 115_200;
    localparam real    CLK_PER   = 1e9 / CLK_FREQ;      // 20 нс
    // Тривалість біта = 16 * DIVISOR тактів (як у baud_gen)
    localparam integer DIVISOR   = (CLK_FREQ + (BAUD_RATE*16)/2) / (BAUD_RATE*16);
    localparam real    BIT_PER   = 16.0 * DIVISOR * CLK_PER; // ~8.64 мкс

    // ---- Сигнали ----
    reg        clk = 0, rst = 1;
    reg        tx_start = 0;
    reg  [7:0] tx_data  = 8'h00;
    wire       txd, tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_valid, frame_err;

    reg        loopback = 1;   // 1: rxd = txd; 0: rxd керує тестбенч
    reg        ext_rxd  = 1;   // Лінія "зовнішнього пристрою"
    wire       rxd = loopback ? txd : ext_rxd;

    integer errors = 0, received = 0;

    // ---- Тестований модуль (DUT) ----
    uart_top #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .txd(txd), .tx_busy(tx_busy), .tx_done(tx_done),
        .rxd(rxd), .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err)
    );

    // ---- Генерація такту ----
    always #(CLK_PER/2) clk = ~clk;

    // ---- Дамп осцилограм для GTKWave ----
    initial begin
        $timeformat(-6, 2, " us", 10);
        $dumpfile("tb_uart.vcd");
        $dumpvars(0, tb_uart);
    end

    // ---- Монітор прийому ----
    always @(posedge clk) begin
        if (rx_valid) begin
            received = received + 1;
            $display("[%t] RX: 0x%02h", $time, rx_data);
        end
        if (frame_err)
            $display("[%t] RX: FRAME ERROR", $time);
    end

    // ---- Задача: передати байт через наш Tx ----
    task tx_byte(input [7:0] b);
        begin
            @(posedge clk);
            tx_data  <= b;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;
            @(posedge tx_done);
            $display("[%t] TX: 0x%02h", $time, b);
        end
    endtask

    // ---- Задача: імітація зовнішнього пристрою (bit-banging) ----
    task send_byte(input [7:0] b, input stop_bit);
        integer i;
        begin
            ext_rxd = 1'b0; #(BIT_PER);              // Старт-біт
            for (i = 0; i < 8; i = i + 1) begin
                ext_rxd = b[i]; #(BIT_PER);           // Дані, LSB першим
            end
            ext_rxd = stop_bit; #(BIT_PER);           // Стоп-біт
            ext_rxd = 1'b1; #(BIT_PER);               // Пауза
        end
    endtask

    // ---- Перевірка прийнятого байта ----
    task expect_rx(input [7:0] exp);
        begin
            @(posedge rx_valid or posedge frame_err);
            #1;
            if (frame_err || rx_data !== exp) begin
                $display("  ПОМИЛКА: очікували 0x%02h, отримали 0x%02h", exp, rx_data);
                errors = errors + 1;
            end else
                $display("  OK: 0x%02h", exp);
        end
    endtask

    // ---- Основний сценарій ----
    reg [7:0] test_vec [0:4];
    integer k;
    initial begin
        test_vec[0] = 8'h55; test_vec[1] = 8'hA3; test_vec[2] = 8'h00;
        test_vec[3] = 8'hFF; test_vec[4] = 8'h3C;

        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // Тест 1: loopback
        $display("=== Тест 1: loopback Tx -> Rx ===");
        loopback = 1;
        for (k = 0; k < 5; k = k + 1) begin
            fork
                tx_byte(test_vec[k]);
                expect_rx(test_vec[k]);
            join
        end

        // Тест 2: дані від зовнішнього пристрою
        $display("=== Тест 2: прийом від зовнішнього пристрою ===");
        loopback = 0;
        #(BIT_PER);
        fork
            send_byte(8'h4B, 1'b1);   // 'K'
            expect_rx(8'h4B);
        join
        fork
            send_byte(8'h96, 1'b1);
            expect_rx(8'h96);
        join

        // Тест 3: помилка кадру
        $display("=== Тест 3: невірний стоп-біт ===");
        fork
            send_byte(8'hE7, 1'b0);
            begin
                @(posedge frame_err or posedge rx_valid);
                #1;
                if (frame_err) $display("  OK: frame_err виставлено");
                else begin $display("  ПОМИЛКА: frame_err не спрацював"); errors = errors + 1; end
            end
        join

        #(BIT_PER * 2);
        $display("==============================================");
        if (errors == 0) $display("ВСІ ТЕСТИ ПРОЙДЕНО (прийнято байтів: %0d)", received);
        else             $display("ТЕСТИ НЕ ПРОЙДЕНО: помилок %0d", errors);
        $display("==============================================");
        $finish;
    end
endmodule
