module split_6(var_16, x);
        input [11:0] var_16;
    output wire x;

    wire constraint_24;

    assign constraint_24 = |(((!(var_16)) != 16'h1));
    assign x = constraint_24;
endmodule
