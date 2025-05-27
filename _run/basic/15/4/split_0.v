module split_0(var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9, x);
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

    wire constraint_0, constraint_3, constraint_5, constraint_6, constraint_7, constraint_10;

    assign constraint_0 = |((~((var_2 << 4'h0))));
    assign constraint_3 = |(((~(var_2)) * var_2));
    assign constraint_5 = |((var_2 || var_6));
    assign constraint_6 = |((~((var_0 && var_6))));
    assign constraint_7 = |((var_2 / 4'h4));
    assign constraint_10 = |(4'h4);
    assign x = constraint_0 & constraint_3 & constraint_5 & constraint_6 & constraint_7 & constraint_10;
endmodule
