#!/usr/bin/env python3
"""
reorder_aag_bdd_specialized.py

Specialized BDD variable ordering algorithms proven effective in practice:
1. SIFT algorithm - Dynamic variable ordering during BDD construction
2. Window permutation - Local optimization
3. Interleaving heuristic - For data path circuits
4. Early quantification ordering - For constraint solving

Usage:
    python3 reorder_aag_bdd_specialized.py input.aag output_reordered.aag [--method sift|window|interleave|quant]
"""

import sys
import time
import argparse
from collections import defaultdict, deque
import random

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

class BDDSpecializedAnalyzer:
    """BDD专用分析器"""
    
    def __init__(self, parsed_aag):
        self.parsed_aag = parsed_aag
        self.n_vars = parsed_aag['I']
        self.lit_to_idx = self._build_literal_map()
        self.support_matrix = self._build_support_matrix()
        self.var_info = self._extract_bdd_specific_info()
        
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
    
    def _build_support_matrix(self):
        """构建支撑矩阵 - BDD宽度估算的关键"""
        # support_matrix[i][j] = 函数i是否依赖变量j
        num_outputs = len(self.parsed_aag['output_lines'])
        support_matrix = [[False for _ in range(self.n_vars)] for _ in range(num_outputs)]
        
        # 为每个输出构建支撑集
        for out_idx, out_line in enumerate(self.parsed_aag['output_lines']):
            try:
                out_lit = int(out_line)
                if out_lit % 2 != 0:
                    out_lit -= 1
                support_vars = self._get_support_recursive(out_lit, set())
                
                for var_idx in support_vars:
                    if 0 <= var_idx < self.n_vars:
                        support_matrix[out_idx][var_idx] = True
            except ValueError:
                continue
        
        return support_matrix
    
    def _get_support_recursive(self, lit, visited):
        """递归获取literal的支撑变量集"""
        if lit in visited:
            return set()
        visited.add(lit)
        
        if lit % 2 != 0:
            lit -= 1
        
        # 如果是输入变量
        if lit in self.lit_to_idx:
            return {self.lit_to_idx[lit]}
        
        # 如果是AND门输出
        support = set()
        for and_line in self.parsed_aag['and_lines']:
            parts = and_line.split()
            if len(parts) == 3:
                try:
                    out_lit = int(parts[0])
                    if out_lit == lit:
                        in1, in2 = int(parts[1]), int(parts[2])
                        support.update(self._get_support_recursive(in1, visited))
                        support.update(self._get_support_recursive(in2, visited))
                        break
                except ValueError:
                    continue
        
        return support
    
    def _extract_bdd_specific_info(self):
        """提取BDD专用信息"""
        var_info = {}
        
        for i in range(self.n_vars):
            var_info[i] = {
                'support_count': 0,      # 支撑多少个输出
                'symmetry_group': [],    # 对称变量组
                'quantification_level': 0, # 量化层级
                'interaction_count': 0,   # 与其他变量的交互次数
                'path_length': 0,        # 到输出的平均路径长度
                'bitwidth': 1,
                'bit_position': 0,
                'var_name': f"var_{i}",
                'early_quant_priority': 0.0
            }
        
        # 计算支撑计数
        for var_idx in range(self.n_vars):
            for out_idx in range(len(self.support_matrix)):
                if self.support_matrix[out_idx][var_idx]:
                    var_info[var_idx]['support_count'] += 1
        
        # 计算变量交互
        self._calculate_variable_interactions(var_info)
        
        # 提取位宽信息
        self._extract_datapath_structure(var_info)
        
        # 计算early quantification优先级
        self._calculate_early_quantification_priority(var_info)
        
        return var_info
    
    def _calculate_variable_interactions(self, var_info):
        """计算变量间交互"""
        interaction_matrix = [[0 for _ in range(self.n_vars)] for _ in range(self.n_vars)]
        
        # 在同一AND门中的变量有交互
        for and_line in self.parsed_aag['and_lines']:
            parts = and_line.split()
            if len(parts) == 3:
                try:
                    in1, in2 = int(parts[1]), int(parts[2])
                    
                    var1 = var2 = None
                    if in1 % 2 != 0: in1 -= 1
                    if in2 % 2 != 0: in2 -= 1
                    
                    if in1 in self.lit_to_idx: var1 = self.lit_to_idx[in1]
                    if in2 in self.lit_to_idx: var2 = self.lit_to_idx[in2]
                    
                    if var1 is not None and var2 is not None:
                        interaction_matrix[var1][var2] += 1
                        interaction_matrix[var2][var1] += 1
                        
                except ValueError:
                    continue
        
        # 更新交互计数
        for i in range(self.n_vars):
            var_info[i]['interaction_count'] = sum(interaction_matrix[i])
    
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
        
        # 设置位宽和对称组
        for var_name, bit_list in var_groups.items():
            bitwidth = len(bit_list)
            bit_list.sort()  # 按位位置排序
            
            for bit_pos, var_idx in bit_list:
                var_info[var_idx]['bitwidth'] = bitwidth
                var_info[var_idx]['symmetry_group'] = [idx for _, idx in bit_list]
    
    def _calculate_early_quantification_priority(self, var_info):
        """计算early quantification优先级"""
        for i in range(self.n_vars):
            # 支撑少数输出的变量优先量化
            support_score = 1.0 / max(1, var_info[i]['support_count'])
            
            # 交互少的变量优先量化
            interaction_score = 1.0 / max(1, var_info[i]['interaction_count'])
            
            # 综合得分
            var_info[i]['early_quant_priority'] = support_score * 0.6 + interaction_score * 0.4

class BDDSpecializedAlgorithms:
    """BDD专用算法实现"""
    
    def __init__(self, analyzer):
        self.analyzer = analyzer
        self.var_info = analyzer.var_info
        self.n_vars = analyzer.n_vars
        self.support_matrix = analyzer.support_matrix
    
    def sift_based_order(self):
        """基于SIFT算法的启发式排序"""
        if self.n_vars == 0:
            return []
        
        print("使用SIFT启发式算法...")
        
        # 初始排序：按支撑计数排序
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            -self.var_info[x]['support_count'],
            -self.var_info[x]['bitwidth'],
            x
        ))
        
        # SIFT-style局部优化
        improved = True
        iterations = 0
        max_iterations = min(20, self.n_vars)
        
        while improved and iterations < max_iterations:
            improved = False
            iterations += 1
            
            # 对每个变量尝试"sift"到更好位置
            for i in range(self.n_vars):
                var = order[i]
                best_pos = i
                best_cost = self._estimate_bdd_width(order, i, i)
                
                # 尝试向前移动
                for new_pos in range(max(0, i-3), i):
                    cost = self._estimate_bdd_width(order, i, new_pos)
                    if cost < best_cost:
                        best_cost = cost
                        best_pos = new_pos
                
                # 尝试向后移动
                for new_pos in range(i+1, min(self.n_vars, i+4)):
                    cost = self._estimate_bdd_width(order, i, new_pos)
                    if cost < best_cost:
                        best_cost = cost
                        best_pos = new_pos
                
                # 如果找到更好位置，执行移动
                if best_pos != i:
                    var = order.pop(i)
                    order.insert(best_pos, var)
                    improved = True
        
        print(f"SIFT优化完成，迭代次数: {iterations}")
        return order
    
    def window_permutation_order(self):
        """窗口置换算法"""
        if self.n_vars == 0:
            return []
        
        print("使用窗口置换算法...")
        
        # 初始排序
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            -self.var_info[x]['bitwidth'],
            -self.var_info[x]['support_count'],
            x
        ))
        
        # 窗口优化
        window_size = min(4, self.n_vars)
        
        for start in range(0, self.n_vars - window_size + 1, window_size // 2):
            end = min(start + window_size, self.n_vars)
            window_vars = order[start:end]
            
            # 对窗口内的变量尝试所有排列（如果变量不多）
            if len(window_vars) <= 4:
                best_perm = self._find_best_window_permutation(window_vars)
                order[start:end] = best_perm
        
        return order
    
    def interleaving_order(self):
        """交错排序 - 专为数据路径优化"""
        if self.n_vars == 0:
            return []
        
        print("使用交错排序算法...")
        
        # 按变量名分组
        var_groups = defaultdict(list)
        for i in range(self.n_vars):
            var_name = self.var_info[i]['var_name']
            bit_pos = self.var_info[i]['bit_position']
            var_groups[var_name].append((bit_pos, i))
        
        # 对每组按位位置排序
        for var_name in var_groups:
            var_groups[var_name].sort()
        
        # 交错策略：按重要性排序变量组
        group_importance = []
        for var_name, bit_list in var_groups.items():
            total_support = sum(self.var_info[var_idx]['support_count'] for _, var_idx in bit_list)
            avg_bitwidth = sum(self.var_info[var_idx]['bitwidth'] for _, var_idx in bit_list) / len(bit_list)
            importance = total_support * avg_bitwidth
            group_importance.append((importance, var_name, bit_list))
        
        group_importance.sort(reverse=True)
        
        # 交错放置：重要变量的高位优先
        order = []
        max_bits = max(len(bit_list) for _, _, bit_list in group_importance) if group_importance else 0
        
        # 从高位到低位交错放置
        for bit_level in range(max_bits-1, -1, -1):
            for _, var_name, bit_list in group_importance:
                if bit_level < len(bit_list):
                    _, var_idx = bit_list[bit_level]
                    order.append(var_idx)
        
        return order
    
    def early_quantification_order(self):
        """早期量化排序 - 专为约束求解优化"""
        if self.n_vars == 0:
            return []
        
        print("使用早期量化排序算法...")
        
        # 按early quantification优先级排序
        order = list(range(self.n_vars))
        order.sort(key=lambda x: (
            -self.var_info[x]['early_quant_priority'],  # 优先级高的在前
            self.var_info[x]['support_count'],          # 支撑少的在前
            -self.var_info[x]['bitwidth'],              # 位宽大的在前
            x
        ))
        
        return order
    
    def _estimate_bdd_width(self, order, old_pos, new_pos):
        """估算BDD宽度（简化版）"""
        # 创建临时排序
        temp_order = order.copy()
        var = temp_order.pop(old_pos)
        temp_order.insert(new_pos, var)
        
        # 估算宽度：计算在每个层级上活跃的变量数
        total_width = 0
        num_outputs = len(self.support_matrix)
        
        for level in range(len(temp_order)):
            active_vars = set()
            current_var = temp_order[level]
            
            # 对每个输出，检查当前变量是否在其支撑中
            for out_idx in range(num_outputs):
                if self.support_matrix[out_idx][current_var]:
                    # 如果是，添加该输出支撑的所有后续变量
                    for future_level in range(level, len(temp_order)):
                        future_var = temp_order[future_level]
                        if self.support_matrix[out_idx][future_var]:
                            active_vars.add(future_var)
            
            total_width += len(active_vars)
        
        return total_width
    
    def _find_best_window_permutation(self, window_vars):
        """找到窗口内的最佳排列"""
        if len(window_vars) <= 1:
            return window_vars
        
        import itertools
        
        best_perm = window_vars
        best_cost = float('inf')
        
        # 尝试所有排列（只对小窗口）
        for perm in itertools.permutations(window_vars):
            cost = self._evaluate_window_cost(list(perm))
            if cost < best_cost:
                best_cost = cost
                best_perm = list(perm)
        
        return best_perm
    
    def _evaluate_window_cost(self, window_order):
        """评估窗口排序的成本"""
        cost = 0
        
        # 简化的成本函数：相邻变量的交互强度
        for i in range(len(window_order) - 1):
            var1, var2 = window_order[i], window_order[i + 1]
            
            # 如果两个变量属于同一个变量组，成本较低
            if self.var_info[var1]['var_name'] == self.var_info[var2]['var_name']:
                cost -= 2
            
            # 如果两个变量有交互，且位置接近，成本较低
            interaction = self._get_variable_interaction(var1, var2)
            cost += interaction * (abs(self.var_info[var1]['bit_position'] - 
                                     self.var_info[var2]['bit_position']) + 1)
        
        return cost
    
    def _get_variable_interaction(self, var1, var2):
        """获取两个变量的交互强度"""
        interaction = 0
        
        # 检查是否在同一个AND门中出现
        for and_line in self.analyzer.parsed_aag['and_lines']:
            parts = and_line.split()
            if len(parts) == 3:
                try:
                    in1, in2 = int(parts[1]), int(parts[2])
                    
                    v1 = v2 = None
                    if in1 % 2 != 0: in1 -= 1
                    if in2 % 2 != 0: in2 -= 1
                    
                    if in1 in self.analyzer.lit_to_idx: v1 = self.analyzer.lit_to_idx[in1]
                    if in2 in self.analyzer.lit_to_idx: v2 = self.analyzer.lit_to_idx[in2]
                    
                    if (v1 == var1 and v2 == var2) or (v1 == var2 and v2 == var1):
                        interaction += 1
                        
                except ValueError:
                    continue
        
        return interaction

def bdd_specialized_reorder(parsed_aag, method='sift'):
    """BDD专用重排序主函数"""
    start_time = time.time()
    
    analyzer = BDDSpecializedAnalyzer(parsed_aag)
    algorithms = BDDSpecializedAlgorithms(analyzer)
    
    if method == 'sift':
        order = algorithms.sift_based_order()
    elif method == 'window':
        order = algorithms.window_permutation_order()
    elif method == 'interleave':
        order = algorithms.interleaving_order()
    elif method == 'quant':
        order = algorithms.early_quantification_order()
    else:
        print(f"未知方法 {method}，使用SIFT方法")
        order = algorithms.sift_based_order()
    
    end_time = time.time()
    print(f"BDD专用排序计算时间: {end_time - start_time:.3f} 秒")
    
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

    print(f"BDD专用排序AAG文件已保存到: {output_path}")

def main():
    parser = argparse.ArgumentParser(description='BDD专用变量排序算法')
    parser.add_argument('input_file', help='输入AAG文件')
    parser.add_argument('output_file', help='输出AAG文件')
    parser.add_argument('--method', 
                       choices=['sift', 'window', 'interleave', 'quant'],
                       default='sift',
                       help='BDD专用算法 (默认: sift)')
    
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
    
    # 使用BDD专用算法
    order = bdd_specialized_reorder(parsed, args.method)
    
    if not order:
        print("BDD专用排序失败，使用默认排序。")
        order = list(range(I))
    
    reorder_aag(parsed, order, args.output_file)

if __name__ == "__main__":
    main()