module split_7(var_20, x);
        input [15:0] var_20;
    output wire x;

    wire constraint_20;

    assign constraint_20 = |((var_20 << 16'hd));
    assign x = constraint_20;
endmodule
