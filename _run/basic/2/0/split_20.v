module split_20(var_43, x);
    input [13:0] var_43;
    output wire x;

    wire constraint_8;

    assign constraint_8 = |((~((!((~(var_43)) != 0) || (var_43 != 0)))));
    assign x = constraint_8;
endmodule
