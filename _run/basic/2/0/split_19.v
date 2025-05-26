module split_19(var_41, x);
    input [8:0] var_41;
    output wire x;

    wire constraint_22;

    assign constraint_22 = |((var_41 ^ 9'hf9));
    assign x = constraint_22;
endmodule
