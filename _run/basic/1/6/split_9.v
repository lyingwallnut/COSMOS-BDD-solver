module split_9(var_26, x);
        input [12:0] var_26;
    output wire x;

    wire constraint_10;

    assign constraint_10 = |(((!(var_26)) + 16'h1));
    assign x = constraint_10;
endmodule
