module split_4(var_12, var_14, var_23, x);
        input [9:0] var_12;
        input [12:0] var_14;
        input [13:0] var_23;
    output wire x;

    wire constraint_12, constraint_14, constraint_17;

    assign constraint_12 = |((var_12 || var_14));
    assign constraint_14 = |((var_14 - 16'h160));
    assign constraint_17 = |(((!(var_14)) || var_23));
    assign x = constraint_12 & constraint_14 & constraint_17;
endmodule
