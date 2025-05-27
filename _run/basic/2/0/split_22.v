module split_22(var_49, x);
    input [15:0] var_49;
    output wire x;

    wire constraint_2;

    assign constraint_2 = |(((~(var_49)) >> 16'ha));
    assign x = constraint_2;
endmodule
