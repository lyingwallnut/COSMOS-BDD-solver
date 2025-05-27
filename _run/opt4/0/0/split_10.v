module split_10(var_23, x);
    input [3:0] var_23;
    output wire x;

    wire constraint_14;

    assign constraint_14 = |(((~(var_23)) / 4'h7));
    assign x = constraint_14;
endmodule
