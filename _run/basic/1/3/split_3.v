module split_3(var_9, x);
        input [10:0] var_9;
    output wire x;

    wire constraint_7;

    assign constraint_7 = |((var_9 << 11'h4));
    assign x = constraint_7;
endmodule
