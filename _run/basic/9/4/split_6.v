module split_6(var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9, var_10, var_11, var_12, var_13, var_14, var_15, var_16, var_17, var_18, var_19, x);
    input [47:0] var_0;
    input [53:0] var_1;
    input [20:0] var_2;
    input [5:0] var_3;
    input [5:0] var_4;
    input [16:0] var_5;
    input [63:0] var_6;
    input [5:0] var_7;
    input [38:0] var_8;
    input [54:0] var_9;
    input [57:0] var_10;
    input [53:0] var_11;
    input [31:0] var_12;
    input [61:0] var_13;
    input [46:0] var_14;
    input [36:0] var_15;
    input [42:0] var_16;
    input [37:0] var_17;
    input [27:0] var_18;
    input [63:0] var_19;
    output wire x;

    wire constraint_9, constraint_11, constraint_17;

    assign constraint_9 = |((~((var_7 * 8'hb))));
    assign constraint_11 = |((var_7 | 6'h14));
    assign constraint_17 = |(((var_7 + 8'h4) * 8'h7));
    assign x = constraint_11 & constraint_9 & constraint_17;
endmodule
