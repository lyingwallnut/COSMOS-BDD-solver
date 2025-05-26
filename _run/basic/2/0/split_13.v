module split_13(var_30, x);
    input [9:0] var_30;
    output wire x;

    wire constraint_41;

    assign constraint_41 = |((!((var_30 << 10'h2))));
    assign x = constraint_41;
endmodule
