#include <cstdio>
#include <cstddef>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <map>
#include <cassert>
#include <random>
#include <iomanip>
#include <regex>
#include <algorithm>
#include <set>
#include <quadmath.h>

#include "nlohmann/json.hpp"
#include "cudd.h"
#include "cuddInt.h"
using json = nlohmann::json;
using namespace std;

// procedure:
// 1. convert the AAG to BDD
//     (1) read the AAG file
//     (2) inputs: use Cudd_bddIthVar to create BDD variables
//     (3) ands: use Cudd_bddAnd to create BDD nodes
//     (4) outputs: there is only one output, no need to deal with it
//     (5) names: create a map to from BDD variable index to its name

// 2. generate random solutions
//    (1) calculate complement arc number of all nodes by dynamic programming
//    (2) generate random solutions using dfs:
//        entering the child node according to probability by the number of complement arcs
//        to make sure finally generate a route with odd complement arcs
//    (3) for don't care variables, randomly assign them

// 3. output the solutions: using nlohmann/json to output the solutions in certain format:
//        {
//        "assignment_list": [
//            // 第一组解
//            [
//            { "value": "2fd3d29"}, // id=0的变量赋值
//            { "value": "a0a1"}, // id=1的变量赋值
//            ...
//            ],
//            // 第二组解
//            [
//            ...
//            ]
//        ]
//        }

// 4. clean up

class BDD_Solver {
    public:
        string input_file;
        string output_file;
        int random_seed;
        int solution_num;

        DdManager *manager;
        DdNode *out_node;
        vector<DdNode*> nodes; // map from AAG index to BDD node

        // map from BDD index to its name
        // name format: var_x[y] -> so record int x and y is ok
        vector<pair<int, int>> idx_to_name;

        // aag config
        int max_idx, input_num, latch_num, output_num, and_num, ori_input_num;
        vector<int> idx_to_len;// the length of each original input variable

        // record path number from current node to 1-th node with odd or even complement arcs
        // 0: odd_cnt, 1: even_cnt
        map<DdNode*, pair<__float128, __float128>> dp;

        // random number generator
        std::mt19937 rng;

        // solution list
        vector<vector<bool>> solutions;
        vector<vector<vector<bool>>> reshaped_solutions;

        bool no_constraint;

        BDD_Solver(const string& input, const string& output, int seed, int num_solutions) 
            : input_file(input), output_file(output), random_seed(seed), solution_num(num_solutions) {
            
            rng = std::mt19937(random_seed);
            
            manager = Cudd_Init(0, 0, CUDD_UNIQUE_SLOTS, CUDD_CACHE_SLOTS, 0);
            if (!manager) {
                cerr << "Error: Failed to initialize CUDD manager" << endl;
                throw runtime_error("CUDD initialization failed");
            }

            
            max_idx = 0;
            input_num = 0;
            latch_num = 0;
            output_num = 0;
            and_num = 0;
            ori_input_num = 0;
            no_constraint = false;
        }
        
        ~BDD_Solver() {
            for (auto node : nodes) {
                if (node != nullptr) {
                    Cudd_RecursiveDeref(manager, node);
                }
            }
            nodes.clear();
            if (manager != nullptr) {
                Cudd_Quit(manager);
                manager = nullptr;
            }
        }

        int aag_to_BDD(){
            ifstream aag_file(input_file);
            if (!aag_file.is_open()) {
                cerr << "Error: Failed to open AAG file" << endl;
                return -1;
            }

            string line;
            aag_file >> line;
            if (line != "aag") {
                cerr << "Error: Invalid AAG file format" << endl;
                return -1;
            }

            aag_file >> max_idx >> input_num >> latch_num >> output_num >> and_num;
            if(and_num == 0){
                no_constraint = true; // if no ands, then no constraint
            }

            
            if(input_num > 100){
                Cudd_AutodynEnable(manager, CUDD_REORDER_SIFT);
            }
            
            // initialize 
            nodes.resize(max_idx);
            idx_to_name.resize(input_num);

            // inputs
            for(int i = 0 ; i < input_num ; i++){
                int idx;
                aag_file >> idx;
                DdNode* node = Cudd_bddIthVar(manager, i);
                Cudd_Ref(node);
                nodes[idx / 2 - 1] = node;// aag input first index is 2

                // store dp
                dp[node] = {(__float128)0.0, (__float128)1.0}; // 0: odd_cnt, 1: even_cnt
                dp[Cudd_Not(node)] = {(__float128)1.0, (__float128)0.0}; 
            }
            // for constant node
            dp[Cudd_ReadOne(manager)] = {(__float128)0.0, (__float128)1.0};
            dp[Cudd_ReadLogicZero(manager)] = {(__float128)0.0, (__float128)0.0};


            // outputs(only 1 output)
            int output_idx;
            aag_file >> output_idx;


            // ands
            for(int i = 0 ; i < and_num ; i++){
                int out, in1, in2;
                aag_file >> out >> in1 >> in2;
                DdNode *In1, *In2, *Out;

                if(in1 / 2 == 0){// constant
                     In1 = (in1 % 2 == 0) ? Cudd_ReadOne(manager) : Cudd_ReadLogicZero(manager);
                } else{
                    In1 = (in1 % 2 == 0) ? nodes[in1 / 2 - 1] : Cudd_Not(nodes[in1 / 2 - 1]);
                }

                if(in2 / 2 == 0){// constant
                     In2 = (in2 % 2 == 0) ? Cudd_ReadOne(manager) : Cudd_ReadLogicZero(manager);
                } else{
                    In2 = (in2 % 2 == 0) ? nodes[in2 / 2 - 1] : Cudd_Not(nodes[in2 / 2 - 1]);
                }

                Out = Cudd_bddAnd(manager, In1, In2);
                Cudd_Ref(Out);
                nodes[out / 2 - 1] = Out;
            }


            // if output is a odd, then an additional inverter is needed
            if(!no_constraint){
                out_node = output_idx % 2 == 0 ? nodes[output_idx / 2 - 1] : Cudd_Not(nodes[output_idx / 2 - 1]);
                Cudd_Ref(out_node);
            }
            else{
                out_node = Cudd_ReadOne(manager); // if no constraint, output is always true
            }



            // names
            for(int i = 0 ; i < input_num ; i++){
                string head, name;
                aag_file >> head >> name;

                regex p1("^i(\\d+)$");
                regex p2("^var_(\\d+)\\[(\\d+)\\]$");

                int idx = 0, x = 0, y = 0;
                smatch match;

                // i_idx
                if (regex_match(head, match, p1)) {
                   idx = stoi(match[1]);
                }
                
                // var_x[y]
                if (regex_match(name, match, p2)) {
                    x = stoi(match[1]);
                    y = stoi(match[2]);
                    ori_input_num = max(ori_input_num, x + 1);
                }

                idx_to_name[idx] = {x, y};
            }


            // for solution reshape in the last step
            ori_input_num = max(ori_input_num, 1);// original input number 
            idx_to_len.resize(ori_input_num, 0);// index to the length of each original input variable
            
            // calculate the length of each original input variable
            for (size_t i = 0; i < idx_to_name.size(); i++) {
                int x = idx_to_name[i].first;
                int y = idx_to_name[i].second;
                if (x < ori_input_num) {
                    idx_to_len[x] = max(idx_to_len[x], y + 1);
                }
            }


            // output names is not needed
            // done
            aag_file.close();   

            return 0;
        }

        pair<__float128, __float128> cal_dp(DdNode* node) {

            auto it = dp.find(node);
            if (it != dp.end()) {
                return it->second;
            }
            
            int idx = Cudd_NodeReadIndex(node);
            //cout << "Node "<< idx << " not found in dp, calculating..." << endl;

            DdNode* regular_node = Cudd_Regular(node);
            DdNode* T = Cudd_T(regular_node);
            DdNode* E = Cudd_E(regular_node);

            bool node_complemented = Cudd_IsComplement(node);
            
            pair<__float128, __float128> t_paths, e_paths;
            
            if (node_complemented) {
                T = Cudd_Not(T);
                E = Cudd_Not(E);
            }
            
            t_paths = cal_dp(T);
            e_paths = cal_dp(E);
            
            pair<__float128, __float128> result;
            
            result.first = t_paths.first + e_paths.first;   // odd
            result.second = t_paths.second + e_paths.second; // even
            
            // if complemented, swap the results
            if (node_complemented) {
                swap(result.first, result.second);
            }
            
            //char odd_buf[128], even_buf[128];
            //quadmath_snprintf(odd_buf, sizeof(odd_buf), "%.6Qg", result.first);
            //quadmath_snprintf(even_buf, sizeof(even_buf), "%.6Qg", result.second);
            //cout << "Calculating DP for node: " << idx;
            //cout << " Odd paths: " << odd_buf << ", Even paths: " << even_buf << endl;
            
            dp[node] = result;
            return result;
        }

        bool dfs_generate_solution(DdNode* node, bool odd, vector<bool>& solution) {
            if (Cudd_IsConstant(node)) {
                if ((odd && node == Cudd_ReadOne(manager)) || 
                    (!odd && node != Cudd_ReadOne(manager))) {
                    return true; 
                }
                return false; 
            }

            int var_index = Cudd_NodeReadIndex(node);
            DdNode* regular_node = Cudd_Regular(node);
            bool is_complemented = Cudd_IsComplement(node);

            DdNode* T = Cudd_T(regular_node);
            DdNode* E = Cudd_E(regular_node);

            if (is_complemented) {
                T = Cudd_Not(T);
                E = Cudd_Not(E);
                odd = !odd;
            }

            auto t_result = dp[T];
            auto e_result = dp[E];

            __float128 cnt_T = odd ? t_result.first : t_result.second;
            __float128 cnt_E = odd ? e_result.first : e_result.second;
            __float128 total_cnt = cnt_T + cnt_E;

            double prob = (total_cnt > 0) ? static_cast<double>(cnt_T) / static_cast<double>(total_cnt) : 0.5;
            double rand_val = std::uniform_real_distribution<double>(0.0, 1.0)(rng);

            bool success = false;
            if (rand_val < prob) {
                solution[var_index] = true;
                success = dfs_generate_solution(T, odd, solution);
            } else {
                solution[var_index] = false;
                success = dfs_generate_solution(E, odd, solution);
            }

            return success;
        }

        int generate_solutions(int num_solutions) {
            solutions.clear();
            solutions.resize(num_solutions);
            
            for(auto &solution : solutions){
                solution.resize(input_num, false);
            }

            if(no_constraint){
                // if no constraint, then all solutions are false
                for(int i = 0 ; i < num_solutions ; i++){
                    for(int j = 0 ; j < input_num ; j++){
                        solutions[i][j] = false;
                    }
                }
                return 0;
            }

            cal_dp(out_node);

            
            const int MAX_ATTEMPTS = 10;
            
            for(int i = 0; i < num_solutions; i++) {
                int attempts = 0;
                bool success = false;
                
                bool seek_odd = (dp[out_node].first > 0);
                while (attempts < MAX_ATTEMPTS && !success) {
                    attempts++;
                    success = dfs_generate_solution(out_node, seek_odd, solutions[i]);
                }
            }
            
            return 0;
        }

        int reshape_solutions() {
            // in solutions, each solution is a vector of bool
            // which represents the value of each input variable like var_0[1],var_2[1]...
            // so we need to reshape it to a reshaped_solutions
            // which is a vector of solutions,
            // each solution is a vector of vector of bool
            // each vector of bool represents the value of an original input variable
            // such as [12:0]var_0, [7:0]var_1, ...

            reshaped_solutions.clear();
            reshaped_solutions.resize(solution_num);
            for(int i = 0 ; i < solution_num; i++){
                reshaped_solutions[i].resize(ori_input_num);
                for(int j = 0 ; j < ori_input_num; j++){
                    reshaped_solutions[i][j].resize(idx_to_len[j], false);
                }
            }

            for(int i = 0 ; i< solution_num ; i++){
                for(int j = 0 ; j < input_num ; j++){
                    int x = idx_to_name[j].first;
                    int y = idx_to_name[j].second;
                    reshaped_solutions[i][x][idx_to_len[x] - 1 - y] = solutions[i][j];
                }
            }
            return 0;
        }

        vector<vector<vector<bool>>> get_solutions(){
            return reshaped_solutions;
        }
};

string binary_to_hex(const vector<bool>& binary) {
    if(binary.empty()) {
        return "0";
    }

    stringstream ss;
    // padding 0s to make the length a multiple of 4
    int len = binary.size();
    int fill = (4 - len % 4) % 4;

    vector<bool> new_binary = vector<bool>(fill, false);
    new_binary.insert(new_binary.end(), binary.begin(), binary.end());
    len += fill;

    // process 4 bits at a time
    for(int i = 0; i < len; i += 4) {
        int value = 0;
        for(int j = 0; j < 4 && i+j < len; j++) {
            value = (value << 1) | (new_binary[i+j] ? 1 : 0);
        }
        ss << std::hex << value;
    }
                
        string result = ss.str();

    // remove leading zeros but keep at least one zero
    size_t start = result.find_first_not_of('0');
    if (start == string::npos) {
        return "0"; 
    }
    return result.substr(start);
}

int output_solutions(vector<vector<vector<bool>>>& reshaped_solutions, 
                     const string& output_file, int ori_input_num) {
            
    json j;
    j["assignment_list"] = json::array();

    for (const auto& solution : reshaped_solutions) {
        json j_solution = json::array();
                
        // sort by the original input variable order
        for (int var_id = 0; var_id < ori_input_num; var_id++) {
            string hex_value = binary_to_hex(solution[var_id]);
            j_solution.push_back({{"value", hex_value}});
        }
                
        j["assignment_list"].push_back(j_solution);
    }

    ofstream out_file(output_file);
    if (!out_file.is_open()) {
        cerr << "Error: Failed to open output file: " << output_file << endl;
        return -1;
    }
            
    out_file << j.dump(4);
    out_file.close();
            
    return 0;
}

int main(int argc, char** argv) {
    if (argc != 6) {
        cerr << "Usage: " << argv[0] << "<input_dir> <random_seed> <solution_num> <output_file> <split_num>" << endl;
        return 1;
    }
    
    string input_dir = argv[1];
    int random_seed = stoi(argv[2]);
    int solution_num = stoi(argv[3]);
    string output_file = argv[4];
    int split_num = stoi(argv[5]);

    // process the input file to get some information
    vector<vector<vector<bool>>> final_solutions;
    int Input_num, Variable_num;
    string line;
    vector<int> Variable_len;
    ifstream infile(input_dir + "/json2verilog.v");

    if (!infile.is_open()) {
        cerr << "Error opening input file: " << input_dir  << "json2verilog.v"  << endl;
        return 1;
    }

    if(getline(infile, line)){
        int idx1 = line.rfind('_');
        int idx2 = line.rfind(',');
        Variable_num = stoi(line.substr(idx1 + 1, idx2 - idx1 - 1)) + 1;
    }
    Variable_len.resize(Variable_num, 0);

    for(int i = 0; i < Variable_num; i++) {
        if(getline(infile, line)) {
            int idx1 = line.find('[');
            int idx2 = line.find(':');
            Variable_len[i] = stoi(line.substr(idx1 + 1, idx2 - idx1 - 1)) + 1;
            Input_num += Variable_len[i];
        }
    }
    infile.close();

    final_solutions.resize(solution_num);
    for(int i = 0 ; i < solution_num ; i++){
        final_solutions[i].resize(Variable_num);
        for(int j = 0 ; j < Variable_num ; j++){
            final_solutions[i][j].resize(Variable_len[j], false);
        }
    }

    cout << "split_num: " << split_num << endl;
    // solve each split
    for(int q = 0 ; q < split_num ; q++){
        cout << "Processing split " << q << "..." << endl;
        BDD_Solver solver(input_dir + "/reordered_aags/reordered_" + to_string(q) + ".aag", 
                        input_dir + "/solution_" + to_string(q) + ".json", 
                        random_seed, solution_num);


        if (solver.aag_to_BDD() != 0) {
            cerr << "Error building BDD from AAG file" << endl;
            return 1;
        }

        
        if (solver.generate_solutions(solution_num) != 0) {
            cerr << "Error generating solutions" << endl;
            return 1;
        }


        if (solver.reshape_solutions() != 0) {
            cerr << "Error reshaping solutions" << endl;
            return 1;
        }

        auto solutions = solver.get_solutions();
        for(int i = 0 ; i < solution_num ; i++){
            for(int j = 0 ; j < Variable_num ; j++){
                for(int k = 0 ; k < Variable_len[j] ; k++){
                    final_solutions[i][j][k] = solutions[i][j][k] || final_solutions[i][j][k];
                }
            }
        }

        cout << "Split " << q << " processed successfully." << endl;
    }
    cout << "All splits processed successfully." << endl;
    // output the final solutions
    if (output_solutions(final_solutions, output_file, Variable_num) != 0) {
        cerr << "Error outputting solutions" << endl;
        return 1;
    }

    cout << "Solutions generated and saved to " << output_file << endl;
    return 0;
}