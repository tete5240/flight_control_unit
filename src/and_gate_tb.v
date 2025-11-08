`timescale 1ns/1ps
module testbench;
    reg a, b;
    wire y;

    // DUT (Device Under Test)
    and_gate uut (
        .a(a),
        .b(b),
        .y(y)
    );

    initial begin
        $dumpfile("and_test.vcd");
        $dumpvars(0, testbench);

        // 테스트 시퀀스
        a = 0; b = 0; #10;
        a = 0; b = 1; #10;
        a = 1; b = 0; #10;
        a = 1; b = 1; #10;

        $finish;
    end

    initial begin
        $monitor("t=%0t | a=%b b=%b -> y=%b", $time, a, b, y);
    end
endmodule
