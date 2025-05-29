module split_0(var_0, var_1, var_2, var_3, var_4, x);
    input [12:0] var_0;
    input [12:0] var_1;
    input [13:0] var_2;
    input [13:0] var_3;
    input [7:0] var_4;
    output wire x;

    wire constraint_0, constraint_4, constraint_6, constraint_8;

    assign constraint_0 = |((~((var_3 << 14'h9))));
    assign constraint_4 = |(((!(var_0)) >> 1'h0));
    assign constraint_6 = |(((!(var_0)) && var_3));
    assign constraint_8 = |(8'h3);
    assign x = constraint_6 & constraint_4 & constraint_0 & constraint_8;
endmodule
