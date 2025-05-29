#!/usr/bin/env python3
"""
reorder_aag_single_output_bdd.py

Specialized variable ordering algorithms for single-output BDD optimization:
1. Depth-First Search ordering - Based on circuit depth
2. Mincut-based ordering - Minimize BDD cut width
3. Variable lifetime ordering - Minimize variable span
4. Cofactor balance ordering - Balance positive/negative cofactors

Usage:
    python3 reorder_aag_single_output_bdd.py input.aag output_reordered.aag [--method dfs|mincut|lifetime|cofactor]
"""

import sys
import time
import argparse
from collections import defaultdict, deque
import math

def parse_aag(path):
    with open(path, 'r') as f:
        lines = [line.rstrip('\n') for line in f]

    if not lines or not lines[0].startswith('aag '):
        raise ValueError("Not a valid AAG file (missing 'aag ' header).")

    parts = lines[0].split()
    if len(parts) < 6:
        raise ValueError("Invalid AAG header.")
    _, M, I, L, O, A = parts[:6]
    M, I, L, O, A = map(int, (M, I, L, O, A))

    idx = 1
    in_lits = lines[idx: idx + I]
    idx += I

    latch_lines = lines[idx: idx + L]
    idx += L

    output_lines = lines[idx: idx + O]
    idx += O

    and_lines = lines[idx: idx + A]
    idx += A

    symbol_lines = []
    while idx < len(lines) and not lines[idx].startswith('c'):
        symbol_lines.append(lines[idx])
        idx += 1

    comment_lines = lines[idx:] if idx < len(lines) else []

    return {
        'M': M, 'I': I, 'L': L, 'O': O, 'A': A,
        'in_lits': in_lits,
        'latch_lines': latch_lines,
        'output_lines': output_lines,
        'and_lines': and_lines,
        'symbol_lines': symbol_lines,
        'comment_lines': comment_lines
    }

class SingleOutputBDDAnalyzer:
    """单输出BDD专用分析器"""
    
    def __init__(self, parsed_aag):
        self.parsed_aag = parsed_aag
        self.n_vars = parsed_aag['I']
        self.lit_to_idx = self._build_literal_map()
        self.circuit_graph = self._build_circuit_graph()
        self.var_info = self._extract_single_output_info()
        
    def _build_literal_map(self):
        """构建literal映射"""
        lit_map = {}
        for i, lit_str in enumerate(self.parsed_aag['in_lits']):
            try:
                val = int(lit_str)
                if val % 2 != 0:
                    val -= 1
                lit_map[val] = i
            except ValueError:
                continue
        return lit_map
    
    def _build_circuit_graph(self):
        """构建电路图 - 专为单输出优化"""
        graph = {
            'forward': defaultdict(list),   # node -> [children]
            'backward': defaultdict(list),  # node -> [parents]
            'gate_info': {}                # gate -> (input1, input2)
        }
        
        # 构建AND门图
        for and_line in self.parsed_aag['and_lines']:
            parts = and_line.split()
            if len(parts) == 3:
                try:
                    out_lit = int(parts[0])
                    in1, in2 = int(parts[1]), int(parts[2])
                    
                    graph['gate_info'][out_lit] = (in1, in2)
                    graph['forward'][in1].append(out_lit)
                    graph['forward'][in2].append(out_lit)
                    graph['backward'][out_lit].extend([in1, in2])
                    
                except ValueError:
                    continue
        
        return graph
    
    def _extract_single_output_info(self):
        """提取单输出BDD专用信息"""
        var_info = {}
        
        for i in range(self.n_vars):
            var_info[i] = {
                'depth_from_input': 0,      # 从输入到该变量的深度
                'depth_to_output': 0,       # 从该变量到输出的深度
                'first_use_level': float('inf'),  # 第一次使用的层级
                'last_use_level': -1,       # 最后使用的层级
                'variable_span': 0,         # 变量活跃跨度
                'fanout_count': 0,          # 扇出数
                'cofactor_weight': 0.0,     # 余因子权重
                'cut_contribution': 0.0,    # 对最小割的贡献
                'bitwidth': 1,
                'bit_position': 0,
                'var_name': f"var_{i}",
                'structural_importance': 0.0
            }
        
        # 计算深度信息
        self._calculate_depths(var_info)
        
        # 计算变量使用跨度
        self._calculate_variable_spans(var_info)
        
        # 计算余因子权重
        self._calculate_cofactor_weights(var_info)
        
        # 提取位宽信息
        self._extract_datapath_structure(var_info)
        
        # 计算结构重要性
        self._calculate_structural_importance(var_info)
        
        return var_info
    
    def _calculate_depths(self, var_info):
        """计算深度信息 - 关键用于DFS排序"""
        # 计算从输入到输出的深度
        depth_map = {}
        
        # 初始化输入深度
        for i, lit_str in enumerate(self.parsed_aag['in_lits']):
            try:
                lit = int(lit_str)
                if lit % 2 != 0:
                    lit -= 1
                depth_map[lit] = 0
            except ValueError:
                continue
        
        # 拓扑排序计算深度
        changed = True
        max_iterations = len(self.parsed_aag['and_lines']) + 1
        iteration = 0
        
        while changed and iteration < max_iterations:
            changed = False
            iteration += 1
            
            for and_line in self.parsed_aag['and_lines']:
                parts = and_line.split()
                if len(parts) == 3:
                    try:
                        out_lit = int(parts[0])
                        in1, in2 = int(parts[1]), int(parts[2])
                        
                        # 计算输入深度
                        if in1 % 2 != 0: in1 -= 1
                        if in2 % 2 != 0: in2 -= 1
                        
                        depth1 = depth_map.get(in1, float('inf'))
                        depth2 = depth_map.get(in2, float('inf'))
                        
                        if depth1 != float('inf') and depth2 != float('inf'):
                            new_depth = max(depth1, depth2) + 1
                            if out_lit not in depth_map or depth_map[out_lit] > new_depth:
                                depth_map[out_lit] = new_depth
                                changed = True
                                
                    except ValueError:
                        continue
        
        # 更新变量深度信息
        for i in range(self.n_vars):
            input_lit = int(self.parsed_aag['in_lits'][i])
            if input_lit % 2 != 0:
                input_lit -= 1
            var_info[i]['depth_from_input'] = depth_map.get(input_lit, 0)
    
    def _calculate_variable_spans(self, var_info):
        """计算变量活跃跨度 - 关键用于lifetime排序"""
        # 模拟电路层级结构
        levels = defaultdict(set)  # level -> {variables_used_at_this_level}
        
        # 为每个AND门分配层级
        gate_levels = {}
        
        for and_line in self.parsed_aag['and_lines']:
            parts = and_line.split()
            if len(parts) == 3:
                try:
                    out_lit = int(parts[0])
                    in1, in2 = int(parts[1]), int(parts[2])
                    
                    # 计算门的层级（基于输入的最大深度）
                    level1 = level2 = 0
                    
                    if in1 % 2 != 0: in1 -= 1
                    if in2 % 2 != 0: in2 -= 1
                    
                    if in1 in self.lit_to_idx:
                        var_idx1 = self.lit_to_idx[in1]
                        level1 = var_info[var_idx1]['depth_from_input']
                    if in2 in self.lit_to_idx:
                        var_idx2 = self.lit_to_idx[in2]
                        level2 = var_info[var_idx2]['depth_from_input']
                    
                    gate_level = max(level1, level2) + 1
                    gate_levels[out_lit] = gate_level
                    
                    # 记录变量在这个层级的使用
                    if in1 in self.lit_to_idx:
                        var_idx = self.lit_to_idx[in1]
                        levels[gate_level].add(var_idx)
                        var_info[var_idx]['first_use_level'] = min(var_info[var_idx]['first_use_level'], gate_level)
                        var_info[var_idx]['last_use_level'] = max(var_info[var_idx]['last_use_level'], gate_level)
                    
                    if in2 in self.lit_to_idx:
                        var_idx = self.lit_to_idx[in2]
                        levels[gate_level].add(var_idx)
                        var_info[var_idx]['first_use_level'] = min(var_info[var_idx]['first_use_level'], gate_level)
                        var_info[var_idx]['last_use_level'] = max(var_info[var_idx]['last_use_level'], gate_level)
                        
                except ValueError:
                    continue
        
        # 计算变量跨度
        for i in range(self.n_vars):
            if var_info[i]['first_use_level'] != float('inf'):
                var_info[i]['variable_span'] = var_info[i]['last_use_level'] - var_info[i]['first_use_level'] + 1
            else:
                var_info[i]['variable_span'] = 0
    
    def _calculate_cofactor_weights(self, var_info):
        """计算余因子权重 - 用于cofactor平衡排序"""
        for i in range(self.n_vars):
            input_lit = int(self.parsed_aag['in_lits'][i])
            
            positive_uses = 0  # 正literal使用次数
            negative_uses = 0  # 负literal使用次数
            
            for and_line in self.parsed_aag['and_lines']:
                parts = and_line.split()
                if len(parts) == 3:
                    try:
                        in1, in2 = int(parts[1]), int(parts[2])
                        
                        for inp in [in1, in2]:
                            if inp == input_lit:
                                positive_uses += 1
                            elif inp == input_lit + 1:
                                negative_uses += 1
                                
                    except ValueError:
                        continue
            
            total_uses = positive_uses + negative_uses
            if total_uses > 0:
                # 余因子平衡度：越接近0.5越好
                pos_ratio = positive_uses / total_uses
                balance = 1.0 - abs(pos_ratio - 0.5) * 2
                var_info[i]['cofactor_weight'] = balance * total_uses
            else:
                var_info[i]['cofactor_weight'] = 0.0
    
    def _extract_datapath_structure(self, var_info):
        """提取数据路径结构"""
        var_groups = defaultdict(list)
        
        for sym_line in self.parsed_aag['symbol_lines']:
            if sym_line.startswith('i'):
                parts = sym_line.split(None, 1)
                if len(parts) == 2:
                    try:
                        input_idx = int(parts[0][1:])
                        name_part = parts[1]
                        
                        if '[' in name_part and ']' in name_part:
                            var_name = name_part[:name_part.find('[')]
                            bit_str = name_part[name_part.find('[')+1:name_part.find(']')]
                            try:
                                bit_pos = int(bit_str)
                            except ValueError:
                                bit_pos = 0
                        else:
                            var_name = name_part
                            bit_pos = 0
                        
                        if input_idx < self.n_vars:
                            var_info[input_idx]['var_name'] = var_name
                            var_info[input_idx]['bit_position'] = bit_pos
                            var_groups[var_name].append((bit_pos, input_idx))
                    except ValueError:
                        continue
        
        # 设置位宽
        for var_name, bit_list in var_groups.items():
            bitwidth = len(bit_list)
            for bit_pos, var_idx in bit_list:
                var_info[var_idx]['bitwidth'] = bitwidth
    
    def _calculate_structural_importance(self, var_info):
        """计算结构重要性"""
        for i in range(self.n_vars):
            # 综合多个因素
            depth_score = var_info[i]['depth_from_input'] / max(1, max(var_info[j]['depth_from_input'] for j in range(self.n_vars)))
            span_score = 1.0 / max(1, var_info[i]['variable_span'])  # 跨度小的更重要
            cofactor_score = var_info[i]['cofactor_weight'] / max(1, max(var_info[j]['cofactor_weight'] for j in range(self.n_vars)))
            bitwidth_score = var_info[i]['bitwidth'] / max(1, max(var_info[j]['bitwidth'] for j in range(self.n_vars)))
            
            var_info[i]['structural_importance'] = (depth_score * 0.3 + 
                                                  span_score * 0.3 + 
                                                  cofactor_score * 0.2 + 
                                                  bitwidth_score * 0.2)

class SingleOutputBDDAlgorithms:
    """单输出BDD专用算法"""
    
    def __init__(self, analyzer):
        self.analyzer = analyzer
        self.var_info = analyzer.var_info
        self.n_vars = analyzer.n_vars
        self.circuit_graph = analyzer.circuit_graph
    
    def depth_first_order(self):
        """深度优先排序 - 按电路深度排序"""
        if self.n_vars == 0:
            return []
        
        print("使用深度优先排序算法...")
        
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            self.var_info[x]['depth_from_input'],     # 深度小的在前
            -self.var_info[x]['bitwidth'],            # 位宽大的在前
            -self.var_info[x]['bit_position'],        # 高位在前
            x
        ))
        
        return order
    
    def mincut_based_order(self):
        """基于最小割的排序 - 最小化BDD宽度"""
        if self.n_vars == 0:
            return []
        
        print("使用最小割排序算法...")
        
        # 计算每个变量对BDD宽度的贡献
        cut_contributions = {}
        
        for i in range(self.n_vars):
            # 估算移除该变量对cut的影响
            contribution = 0
            
            # 计算该变量的"切割权重"
            span = self.var_info[i]['variable_span']
            cofactor_balance = self.var_info[i]['cofactor_weight']
            depth = self.var_info[i]['depth_from_input']
            
            # 权重函数：跨度大、不平衡的变量贡献大
            contribution = span * (1.0 + 1.0 / max(0.1, cofactor_balance))
            cut_contributions[i] = contribution
        
        # 按贡献排序：贡献小的在前（减少BDD宽度）
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            cut_contributions[x],                     # 割贡献小的在前
            self.var_info[x]['variable_span'],        # 跨度小的在前
            -self.var_info[x]['structural_importance'], # 重要性高的在前
            x
        ))
        
        return order
    
    def lifetime_order(self):
        """变量生命周期排序 - 最小化活跃变量数"""
        if self.n_vars == 0:
            return []
        
        print("使用变量生命周期排序算法...")
        
        # 按变量的活跃跨度和首次使用时间排序
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            self.var_info[x]['first_use_level'],      # 首次使用早的在前
            self.var_info[x]['variable_span'],        # 跨度小的在前
            -self.var_info[x]['bitwidth'],            # 位宽大的在前
            x
        ))
        
        return order
    
    def cofactor_balance_order(self):
        """余因子平衡排序 - 优化BDD节点数"""
        if self.n_vars == 0:
            return []
        
        print("使用余因子平衡排序算法...")
        
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            -self.var_info[x]['cofactor_weight'],     # 平衡度高的在前
            self.var_info[x]['variable_span'],        # 跨度小的在前
            -self.var_info[x]['structural_importance'], # 重要性高的在前
            x
        ))
        
        return order
    
    def hybrid_single_output_order(self):
        """混合单输出优化排序"""
        if self.n_vars == 0:
            return []
        
        print("使用混合单输出优化排序...")
        
        # 分阶段排序策略
        
        # 第1阶段：按重要性分组
        critical_vars = []    # 关键变量
        normal_vars = []      # 普通变量
        
        importance_threshold = 0.5
        
        for i in range(self.n_vars):
            if self.var_info[i]['structural_importance'] >= importance_threshold:
                critical_vars.append(i)
            else:
                normal_vars.append(i)
        
        # 第2阶段：对关键变量使用cofactor平衡排序
        critical_vars.sort(key=lambda x: (
            -self.var_info[x]['cofactor_weight'],
            self.var_info[x]['depth_from_input'],
            -self.var_info[x]['bitwidth']
        ))
        
        # 第3阶段：对普通变量使用lifetime排序
        normal_vars.sort(key=lambda x: (
            self.var_info[x]['first_use_level'],
            self.var_info[x]['variable_span'],
            -self.var_info[x]['bitwidth']
        ))
        
        # 第4阶段：智能合并
        final_order = []
        
        # 交替放置关键变量和相关普通变量
        for crit_var in critical_vars:
            final_order.append(crit_var)
            
            # 查找与关键变量同名的普通变量
            crit_name = self.var_info[crit_var]['var_name']
            related_normal = [v for v in normal_vars 
                            if self.var_info[v]['var_name'] == crit_name]
            
            if related_normal:
                # 选择位位置最接近的
                best_related = min(related_normal, 
                                 key=lambda x: abs(self.var_info[x]['bit_position'] - 
                                                  self.var_info[crit_var]['bit_position']))
                final_order.append(best_related)
                normal_vars.remove(best_related)
        
        # 添加剩余普通变量
        final_order.extend(normal_vars)
        
        return final_order

def single_output_bdd_reorder(parsed_aag, method='mincut'):
    """单输出BDD重排序主函数"""
    start_time = time.time()
    
    analyzer = SingleOutputBDDAnalyzer(parsed_aag)
    algorithms = SingleOutputBDDAlgorithms(analyzer)
    
    if method == 'dfs':
        order = algorithms.depth_first_order()
    elif method == 'mincut':
        order = algorithms.mincut_based_order()
    elif method == 'lifetime':
        order = algorithms.lifetime_order()
    elif method == 'cofactor':
        order = algorithms.cofactor_balance_order()
    elif method == 'hybrid':
        order = algorithms.hybrid_single_output_order()
    else:
        print(f"未知方法 {method}，使用最小割方法")
        order = algorithms.mincut_based_order()
    
    end_time = time.time()
    print(f"单输出BDD排序计算时间: {end_time - start_time:.3f} 秒")
    
    return order

def reorder_aag(parsed, order, output_path):
    """重新排序AAG文件"""
    M, I, L, O, A = parsed['M'], parsed['I'], parsed['L'], parsed['O'], parsed['A']
    in_lits = parsed['in_lits']
    latch_lines = parsed['latch_lines']
    output_lines = parsed['output_lines']
    and_lines = parsed['and_lines']
    symbol_lines = parsed['symbol_lines']
    comment_lines = parsed['comment_lines']

    if not order or len(order) != I:
        print("Warning: Invalid order, using default order.")
        order = list(range(I))

    old2new = {old: new for new, old in enumerate(order)}
    new_in_lits = [in_lits[old] for old in order]

    new_symbol_lines = []
    for sym in symbol_lines:
        if sym.startswith('i'):
            parts = sym.split(None, 1)
            if len(parts) == 2:
                try:
                    old_i = int(parts[0][1:])
                    name = parts[1]
                    new_i = old2new.get(old_i, None)
                    if new_i is not None:
                        new_symbol_lines.append(f"i{new_i} {name}")
                    else:
                        new_symbol_lines.append(sym)
                except ValueError:
                    new_symbol_lines.append(sym)
            else:
                new_symbol_lines.append(sym)
        else:
            new_symbol_lines.append(sym)

    with open(output_path, 'w') as f:
        f.write(f"aag {M} {I} {L} {O} {A}\n")
        for lit in new_in_lits:
            f.write(lit + "\n")
        for line in latch_lines:
            f.write(line + "\n")
        for line in output_lines:
            f.write(line + "\n")
        for line in and_lines:
            f.write(line + "\n")
        for sym in new_symbol_lines:
            f.write(sym + "\n")
        for line in comment_lines:
            f.write(line + "\n")

    print(f"单输出BDD优化AAG文件已保存到: {output_path}")

def main():
    parser = argparse.ArgumentParser(description='单输出BDD专用变量排序算法')
    parser.add_argument('input_file', help='输入AAG文件')
    parser.add_argument('output_file', help='输出AAG文件')
    parser.add_argument('--method', 
                       choices=['dfs', 'mincut', 'lifetime', 'cofactor', 'hybrid'],
                       default='mincut',
                       help='单输出BDD算法 (默认: mincut)')
    
    args = parser.parse_args()
    
    try:
        parsed = parse_aag(args.input_file)
    except Exception as e:
        print(f"解析AAG文件错误: {e}")
        sys.exit(1)
    
    I = parsed['I']
    if I == 0:
        print("没有输入变量需要重排序，直接复制文件。")
        import shutil
        shutil.copy(args.input_file, args.output_file)
        sys.exit(0)
    
    # 使用单输出BDD专用算法
    order = single_output_bdd_reorder(parsed, args.method)
    
    if not order:
        print("单输出BDD排序失败，使用默认排序。")
        order = list(range(I))
    
    reorder_aag(parsed, order, args.output_file)

if __name__ == "__main__":
    main()