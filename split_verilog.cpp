#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
using namespace std;
/* input format:
    module generated_module(var_0, var_1, var_2, var_3, var_4, x);
        input [12:0] var_0;
        input [12:0] var_1;
        input [13:0] var_2;
        input [13:0] var_3;
        input [7:0] var_4;
        output wire x;

        wire constraint_0, constraint_1, constraint_2, constraint_3, constraint_4, constraint_5, constraint_6, constraint_7, constraint_8;

        assign constraint_0 = |((~((var_3 << 14'h9))));
        assign constraint_1 = |(((var_2 - 16'h39dd) + 16'he8c3));
        assign constraint_2 = |(((!(var_1)) ^ 1'h1));
        assign constraint_3 = |(((~(var_4)) / 8'h3));
        assign constraint_4 = |(((!(var_0)) >> 1'h0));
        assign constraint_5 = |(((var_2 >> 14'h1) ^ var_1));
        assign constraint_6 = |(((!(var_0)) && var_3));
        assign constraint_7 = |((~(((~(var_4)) * var_4))));
        assign constraint_8 = |(8'h3);

        assign x = constraint_6 & constraint_4 & constraint_7 & constraint_0 & constraint_1 & constraint_2 & constraint_5 & constraint_3 & constraint_8;
    endmodule
*/

class UnionFind {
private:
    vector<int> parent;
    vector<int> rank;

public:
    UnionFind(int n) {
        parent.resize(n);
        rank.resize(n, 0);
        for (int i = 0; i < n; i++) {
            parent[i] = i;
        }
    }

    int find(int x) {
        if (parent[x] != x) {
            parent[x] = find(parent[x]);
        }
        return parent[x];
    }

    void unite(int x, int y) {
        int root_x = find(x);
        int root_y = find(y);
        
        if (root_x == root_y) return;
        
        if (rank[root_x] < rank[root_y]) {
            parent[root_x] = root_y;
        } else if (rank[root_x] > rank[root_y]) {
            parent[root_y] = root_x;
        } else {
            parent[root_y] = root_x;
            rank[root_x]++;
        }
    }
    
    int count_sets() {
        int count = 0;
        for (int i = 0; i < parent.size(); i++) {
            if (parent[i] == i) {
                count++;
            }
        }
        return count;
    }
    
};

class VerilogSplitter {
public:
    string input_file;
    string output_dir;
    string line;

    int total_constraints = 0;
    int total_variables = 0;

    vector<string> constraints;
    vector<string> variables;
    vector<int> constraint_order;

    UnionFind uf;
    vector<int> variable_to_set;
    vector<int> constraint_to_variable;
    vector<int> constraint_to_set;
    int set_cnt = 0;

    VerilogSplitter(const string& input_file, const string& output_dir)
        : input_file(input_file), output_dir(output_dir), uf(0) {};
    
    ~VerilogSplitter() {
    }

    void read_input_file() {
        ifstream infile(input_file);
        if (!infile.is_open()) {
            cerr << "Error opening input file: " << input_file << endl;
            return;
        }

        if(getline(infile, line)){
            int idx1 = line.rfind('_');
            int idx2 = line.rfind(',');
            total_variables = stoi(line.substr(idx1 + 1, idx2 - idx1 - 1)) + 1;
        }

        for(int i = 0; i < total_variables; i++) {
            if(getline(infile, line)) {
                variables.push_back(line);
            }
        }

        getline(infile, line); // Skip the output line
        getline(infile, line);

        if(getline(infile, line)) {
            int idx1 = line.rfind('_');
            int idx2 = line.rfind(';');
            total_constraints = stoi(line.substr(idx1 + 1, idx2 - idx1 - 1)) + 1;
        }

        getline(infile, line);

        for(int i = 0; i < total_constraints; i++) {
            if(getline(infile, line)) {
                constraints.push_back(line);
            }
        }

        getline(infile, line);

        if(getline(infile, line)) {
            for(int i = 0 ; i < line.size() ; i++){
                if(line[i] == '_'){
                    string t;
                    for(int j = i + 1 ; j < line.size() ; j++){
                        if(line[j] >= '0' && line[j] <= '9'){
                            t += line[j];
                        } else {
                            break;
                        }
                    }
                    constraint_order.push_back(stoi(t));
                }
            }
        }
    }

    void find_relativity(){
        uf = UnionFind(total_variables);
        variable_to_set.resize(total_variables);
        constraint_to_variable.resize(total_constraints);
        constraint_to_set.resize(total_constraints);

        for(int l = 0 ; l < total_constraints ; l++){
            line = constraints[l];
            int constraint_idx = 0;
            vector<int> variable_idxs;
            for(int i = 0 ; i < line.size() ; i++){
                if(line[i] == 'o'){
                    string t;
                    for(int j = i + 10; j < line.size(); j++){
                        if(line[j] >= '0' && line[j] <= '9'){
                            t += line[j];
                        } else {
                            i = j;
                            break;
                        }
                    }
                    constraint_idx = stoi(t);
                }
                if(line[i] == 'v'){
                    string t;
                    for(int j = i + 4; j < line.size(); j++){
                        if(line[j] >= '0' && line[j] <= '9'){
                            t += line[j];
                        } else {
                            i = j;
                            break;
                        }
                    }
                    int variable_idx = stoi(t);
                    variable_idxs.push_back(variable_idx);
                }
            }
            if(variable_idxs.empty()){
                constraint_to_set[constraint_idx] = 0;
                continue;
            }
            if(variable_idxs.size() > 1) {
                for(int i = 1; i < variable_idxs.size(); i++) {
                    uf.unite(variable_idxs[0], variable_idxs[i]);
                }
            }
            constraint_to_variable[constraint_idx] = variable_idxs[0];
        }
        map<int, int> set_id_map;
        int new_id = 0;
        for(int x = 0 ; x < total_variables ; x++){
            int set_id = uf.find(x);
            if(set_id_map.find(set_id) == set_id_map.end()) {
                set_id_map[set_id] = new_id++;
            }
            variable_to_set[x] = set_id_map[set_id];
        }
        for(int i = 0 ; i < total_constraints ; i++){
            constraint_to_set[i] = variable_to_set[constraint_to_variable[i]];
        }
        set_cnt = new_id;
    }

    void write_output_files() {
        for(int s = 0 ; s < set_cnt ; s++){
            string output_file = output_dir + "/split_" + to_string(s) + ".v";
            ofstream outfile(output_file);
            if (!outfile.is_open()) {
                cerr << "Error opening output file: " << output_file << endl;
                continue;
            }

            line = "module split_" + to_string(s) + "(";
            for(int i = 0 ; i < total_variables ; i++){
                if(variable_to_set[i] == s){
                    line += "var_" + to_string(i) + ", ";
                }
            }
            line += "x);\n";
            outfile << line;

            for(int i = 0 ; i < total_variables ; i++){
                if(variable_to_set[i] == s){
                    line = variables[i] + "\n";
                    outfile << line;
                }
            }

            line = "    output wire x;\n\n";
            outfile << line;


            int constraint_count = 0;
            line = "    wire ";
            for(int i = 0 ; i < total_constraints ; i++){
                if(constraint_to_set[i] == s){
                    line += "constraint_" + to_string(i) + ", ";
                    constraint_count++;
                }
            }

            if(constraint_count != 0){
                line = line.substr(0, line.size() - 2) + ";\n\n";
                outfile << line;
            }
            

            for(int i = 0 ; i < total_constraints ; i++){
                if(constraint_to_set[i] == s){
                    line = constraints[i] + "\n";
                    outfile << line;
                }
            }

            line = "    assign x = ";
            if(constraint_count != 0){
                vector<int> constraint_idxs;
                for(int i = 0 ; i < total_constraints ; i++){
                    if(constraint_to_set[i] == s){
                        constraint_idxs.push_back(i);
                    }
                }
                for(int i = 0 ; i < constraint_order.size() ; i++){
                    for(int j = 0 ; j < constraint_idxs.size() ; j++){
                        if(constraint_order[i] == constraint_idxs[j]){
                            line += "constraint_" + to_string(constraint_idxs[j]) + " & ";
                            break;
                        }
                    }
                }
                line = line.substr(0, line.size() - 3) + ";\n";
                outfile << line;
                outfile << "endmodule\n";
                outfile.close();
            }
            else{
                line = "    assign x = 1 || ";
                for(int i = 0 ; i < total_variables ; i++){
                    if(variable_to_set[i] == s){
                        line += "var_" + to_string(i) + " || ";
                    }
                }
                line = line.substr(0, line.size() - 4) + ";\n";
                outfile << line;
                outfile << "endmodule\n";
                outfile.close();
            }
        }
    }
};

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <input_file> <output_directory>" << endl;
        return 1;
    }

    string input_file = argv[1];
    string output_dir = argv[2];

    VerilogSplitter splitter(input_file, output_dir);
    splitter.read_input_file();
    splitter.find_relativity();
    splitter.write_output_files();

    cout << "Verilog module successfully split into " << splitter.set_cnt << " separate modules." << endl;
    
    return 0;
}