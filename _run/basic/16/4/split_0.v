module split_0(var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9, x);
    input [35:0] var_0;
    input [50:0] var_1;
    input [56:0] var_2;
    input [53:0] var_3;
    input [59:0] var_4;
    input [48:0] var_5;
    input [38:0] var_6;
    input [56:0] var_7;
    input [56:0] var_8;
    input [45:0] var_9;
    output wire x;

    wire constraint_0, constraint_1, constraint_2, constraint_3, constraint_4, constraint_5, constraint_6, constraint_7, constraint_8, constraint_10, constraint_11, constraint_13, constraint_14;

    assign constraint_0 = |((!((!((var_7 & var_3))))));
    assign constraint_1 = |(((var_0 && var_7) != var_9));
    assign constraint_2 = |((!((~((var_0 ^ 36'he755720a5))))));
    assign constraint_3 = |((var_9 << 46'h11));
    assign constraint_4 = |(((var_7 >> 57'h1f) ^ 57'hb899e50540b2ef));
    assign constraint_5 = |((!((~(var_0)) != 0) || (var_0 != 0)));
    assign constraint_6 = |((!(var_2 != 0) || (var_5 != 0)));
    assign constraint_7 = |(((~(var_8)) || var_5));
    assign constraint_8 = |(((!(var_7 != 0) || (57'h25d36a26c0e034 != 0)) >> 1'h0));
    assign constraint_10 = |((var_8 ^ var_2));
    assign constraint_11 = |(((var_7 << 57'h32) & var_8));
    assign constraint_13 = |((!(var_5 != 0) || (49'hd1d336499cea != 0)));
    assign constraint_14 = |(((~(var_2)) ^ var_2));
    assign x = constraint_5 & constraint_2 & constraint_3 & constraint_1 & constraint_13 & constraint_7 & constraint_6 & constraint_0 & constraint_10 & constraint_11 & constraint_8 & constraint_14 & constraint_4;
endmodule
