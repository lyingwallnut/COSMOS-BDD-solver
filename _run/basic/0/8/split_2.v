module split_2(var_4, x);
        input [7:0] var_4;
    output wire x;

    wire constraint_3, constraint_7;

    assign constraint_3 = |(((~(var_4)) / 8'h3));
    assign constraint_7 = |((~(((~(var_4)) * var_4))));
    assign x = constraint_7 & constraint_3;
endmodule
