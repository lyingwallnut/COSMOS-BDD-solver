module split_3(var_9, x);
    input [31:0] var_9;
    output wire x;

    wire constraint_16, constraint_27;

    assign constraint_16 = |((!(var_9 != 0) || (32'h6fbe9481 != 0)));
    assign constraint_27 = |((var_9 ^ 32'h6839a06f));
    assign x = constraint_16 & constraint_27;
endmodule
