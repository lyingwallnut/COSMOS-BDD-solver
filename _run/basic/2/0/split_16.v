module split_16(var_37, x);
    input [12:0] var_37;
    output wire x;

    wire constraint_33;

    assign constraint_33 = |((~((var_37 + 16'h7bc))));
    assign x = constraint_33;
endmodule
