module split_1(var_2, x);
    input [12:0] var_2;
    output wire x;

    wire constraint_2;

    assign constraint_2 = |((var_2 | 13'h19de));
    assign x = constraint_2;
endmodule
