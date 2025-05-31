module split_1(var_1, var_2, x);
        input [12:0] var_1;
        input [13:0] var_2;
    output wire x;

    wire constraint_1, constraint_2, constraint_5;

    assign constraint_1 = |(((var_2 - 16'h39dd) + 16'he8c3));
    assign constraint_2 = |(((!(var_1)) ^ 1'h1));
    assign constraint_5 = |(((var_2 >> 14'h1) ^ var_1));
    assign x = constraint_1 & constraint_2 & constraint_5;
endmodule
