module split_2(var_0, var_1, var_2, var_3, var_4, x);
    input [12:0] var_0;
    input [12:0] var_1;
    input [13:0] var_2;
    input [13:0] var_3;
    input [7:0] var_4;
    output wire x;

    wire constraint_3, constraint_7;

    assign constraint_3 = |(((~(var_4)) / 8'h3));
    assign constraint_7 = |((~(((~(var_4)) * var_4))));
    assign x = constraint_7 & constraint_3;
endmodule
