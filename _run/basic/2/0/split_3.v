module split_3(var_8, x);
    input [12:0] var_8;
    output wire x;

    wire constraint_27;

    assign constraint_27 = |((!((var_8 << 13'ha))));
    assign x = constraint_27;
endmodule
