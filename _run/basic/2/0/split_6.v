module split_6(var_14, var_35, x);
    input [15:0] var_14;
    input [13:0] var_35;
    output wire x;

    wire constraint_23;

    assign constraint_23 = |(((var_35 - 16'h3254) != var_14));
    assign x = constraint_23;
endmodule
