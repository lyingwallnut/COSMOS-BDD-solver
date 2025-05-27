module split_15(var_33, var_48, x);
    input [14:0] var_33;
    input [4:0] var_48;
    output wire x;

    wire constraint_46;

    assign constraint_46 = |((var_48 && var_33));
    assign x = constraint_46;
endmodule
