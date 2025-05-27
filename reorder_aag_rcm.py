#!/usr/bin/env python3
"""
reorder_aag_rcm_manual.py

A script to reorder the input lines of an AAG file using
a manual implementation of Reverse Cuthill-McKee (RCM) based on input correlation.

Usage:
    python3 reorder_aag_rcm_manual.py input.aag output_reordered.aag

Dependencies:
    - networkx (for graph construction only, RCM is implemented manually)
"""

import sys
import networkx as nx
from collections import deque

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

def build_literal_to_input_map(in_lits):
    lit_to_idx = {}
    for k, lit in enumerate(in_lits):
        try:
            val = int(lit)
        except:
            continue
        if val % 2 != 0:
            val -= 1
        lit_to_idx[val] = k
    return lit_to_idx

def build_and_dict(and_lines):
    and_dict = {}
    for line in and_lines:
        parts = line.split()
        if len(parts) != 3:
            continue
        out_lit = int(parts[0])
        in1 = int(parts[1])
        in2 = int(parts[2])
        and_dict[out_lit] = (in1, in2)
    return and_dict

def find_input_sources(lit, lit_to_idx, and_dict, cache):
    if lit % 2 != 0:
        lit -= 1
    if lit in cache:
        return cache[lit]
    if lit in lit_to_idx:
        idx = lit_to_idx[lit]
        cache[lit] = {idx}
        return cache[lit]
    if lit in and_dict:
        in1, in2 = and_dict[lit]
        sources1 = find_input_sources(in1, lit_to_idx, and_dict, cache)
        sources2 = find_input_sources(in2, lit_to_idx, and_dict, cache)
        combined = sources1.union(sources2)
        cache[lit] = combined
        return combined
    cache[lit] = set()
    return cache[lit]

def build_input_association_graph(parsed):
    I = parsed['I']
    in_lits = parsed['in_lits']
    and_lines = parsed['and_lines']

    G = nx.Graph()
    G.add_nodes_from(range(I))

    lit_to_idx = build_literal_to_input_map(in_lits)
    and_dict = build_and_dict(and_lines)
    cache = {}

    for line in and_lines:
        parts = line.split()
        if len(parts) != 3:
            continue
        out_lit = int(parts[0])
        sources = find_input_sources(out_lit, lit_to_idx, and_dict, cache)
        src_list = list(sources)
        n = len(src_list)
        for i in range(n):
            for j in range(i + 1, n):
                u = src_list[i]
                v = src_list[j]
                if u != v:
                    G.add_edge(u, v)
    return G

def manual_rcm_order(G):
    """
    Manual Reverse Cuthill-McKee implementation.
    """
    N = G.number_of_nodes()
    degrees = dict(G.degree())
    visited = [False] * N
    order = []

    # Process all connected components
    for start in sorted(degrees, key=lambda x: degrees[x]):
        if visited[start]:
            continue
        # BFS queue ordered by degree
        queue = deque([start])
        visited[start] = True
        component_order = [start]
        while queue:
            u = queue.popleft()
            neighbors = [v for v in G.neighbors(u) if not visited[v]]
            neighbors.sort(key=lambda x: degrees[x])
            for v in neighbors:
                visited[v] = True
                queue.append(v)
                component_order.append(v)
        # Append reversed component order
        order.extend(reversed(component_order))
    return order

def reorder_aag(parsed, order, output_path):
    M, I, L, O, A = parsed['M'], parsed['I'], parsed['L'], parsed['O'], parsed['A']
    in_lits = parsed['in_lits']
    latch_lines = parsed['latch_lines']
    output_lines = parsed['output_lines']
    and_lines = parsed['and_lines']
    symbol_lines = parsed['symbol_lines']
    comment_lines = parsed['comment_lines']

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
                except:
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

    print(f"Reordered AAG saved to: {output_path}")

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 reorder_aag_rcm_manual.py input.aag output_reordered.aag")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    parsed = parse_aag(input_path)
    I = parsed['I']

    G = build_input_association_graph(parsed)
    if G.number_of_nodes() != I:
        print("Warning: Graph nodes count does not match number of inputs.")
    order = manual_rcm_order(G)
    if len(order) != I:
        print("Warning: RCM order size does not match number of inputs. Using default order.")
        order = list(range(I))

    reorder_aag(parsed, order, output_path)

if __name__ == "__main__":
    main()

