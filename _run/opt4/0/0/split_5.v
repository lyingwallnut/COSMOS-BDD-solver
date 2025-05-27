module split_5(var_11, x);
    input [20:0] var_11;
    output wire x;

    wire constraint_1;

    assign constraint_1 = |((~((var_11 + 32'h853b9))));
    assign x = constraint_1;
endmodule
