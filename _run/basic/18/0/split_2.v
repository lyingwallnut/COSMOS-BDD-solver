module split_2(var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9, x);
    input [15:0] var_0;
    input [21:0] var_1;
    input [3:0] var_2;
    input [27:0] var_3;
    input [18:0] var_4;
    input [17:0] var_5;
    input [18:0] var_6;
    input [13:0] var_7;
    input [15:0] var_8;
    input [28:0] var_9;
    output wire x;

    wire constraint_2, constraint_4, constraint_8, constraint_9;

    assign constraint_2 = |((var_5 && var_2));
    assign constraint_4 = |(((~(var_2)) / 4'h8));
    assign constraint_8 = |(((var_2 & 4'h7) * 8'hb));
    assign constraint_9 = |((var_2 != var_8));
    assign x = constraint_2 & constraint_8 & constraint_9 & constraint_4;
endmodule
