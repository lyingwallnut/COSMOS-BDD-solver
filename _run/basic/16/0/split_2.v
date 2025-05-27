module split_2(var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9, x);
    input [35:0] var_0;
    input [50:0] var_1;
    input [56:0] var_2;
    input [53:0] var_3;
    input [59:0] var_4;
    input [48:0] var_5;
    input [38:0] var_6;
    input [56:0] var_7;
    input [56:0] var_8;
    input [45:0] var_9;
    output wire x;

    wire constraint_12;

    assign constraint_12 = |((var_4 >> 60'h39));
    assign x = constraint_12;
endmodule
