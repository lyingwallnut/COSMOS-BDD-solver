#!/bin/bash
# filepath: /root/finalProject/COSMOS-BDD-solver/run.sh

set -e  # 遇错退出

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "用法: $0 <约束文件.json> <解的数量> <输出目录> [<随机种子>]"
    exit 1
fi

# 参数
constraint_file="$1"
solution_num="$2"
run_dir="$3"
seed="${4:-42}"  # 默认种子为42

# 提取数据集和数据ID信息，便于日志显示
dataset_name=$(dirname "$constraint_file")
data_id=$(basename "$constraint_file" .json)

# 确保输出目录存在
mkdir -p "$run_dir"
basename=$(basename "$constraint_file" .json)

# 记录整体开始时间
total_start_time=$(date +%s)

echo "===== 处理 $dataset_name/$data_id.json 到 $run_dir ====="

# 检查预编译的可执行文件是否存在，如果不存在则运行 build.sh
if [ ! -f "_run/json2verilog" ] || [ ! -f "_run/solution_gen" ] || [ ! -f "_run/split_verilog" ]; then
    echo "===== 可执行文件不存在，运行 build.sh 进行编译 ====="
    build_start_time=$(date +%s)
    ./build.sh
    if [ $? -ne 0 ]; then
        echo "❌ 编译失败: build.sh 执行出错"
        exit 1
    fi
    build_end_time=$(date +%s)
    build_runtime=$((build_end_time - build_start_time))
    echo "✔ 编译成功: 可执行文件已生成"
else
    echo "✔ 使用已有的可执行文件"
    build_runtime=0
fi

echo "===== Step 1: JSON → Verilog ====="
# 记录JSON到Verilog转换开始时间
json2v_start_time=$(date +%s)

# 执行转换
"_run/json2verilog" "$constraint_file" "$run_dir"

# 确保 json2verilog.v 生成到正确目录
INITIAL_VERILOG_FILE="$run_dir/json2verilog.v"
if [ ! -f "$INITIAL_VERILOG_FILE" ]; then
    echo "❌ 错误: 初始 Verilog 文件 ($INITIAL_VERILOG_FILE) 未生成"
    exit 1
fi

# 记录JSON到Verilog转换结束时间
json2v_end_time=$(date +%s)
json2v_runtime=$((json2v_end_time - json2v_start_time))
echo "✔ Verilog 文件已生成: $run_dir/json2verilog.v"

echo "===== Step 1.5: 拆分 Verilog 文件 ====="
# 记录Verilog拆分开始时间
splitv_start_time=$(date +%s)

SPLIT_VERILOG_INPUT_FILE="$INITIAL_VERILOG_FILE"
SPLIT_VERILOG_TARGET_DIR="$run_dir" # 输出目录就是运行目录

echo "拆分 Verilog 文件: $SPLIT_VERILOG_INPUT_FILE -> $SPLIT_VERILOG_TARGET_DIR (文件名为 split_N.v)"
"_run/split_verilog" "$SPLIT_VERILOG_INPUT_FILE" "$SPLIT_VERILOG_TARGET_DIR"

num_split_files=$(ls -1 "$SPLIT_VERILOG_TARGET_DIR"/split_*.v 2>/dev/null | wc -l)

if [ "$num_split_files" -eq 0 ]; then
    echo "❌ 错误: Verilog 文件拆分失败，未在 $SPLIT_VERILOG_TARGET_DIR 中找到 split_N.v 文件。"
    exit 1
fi
echo "✔ Verilog 文件已拆分为 $num_split_files 份 (例如: split_0.v, ...)"

splitv_end_time=$(date +%s)
splitv_runtime=$((splitv_end_time - splitv_start_time))

# 在第95行左右，添加AAG输出目录的创建
echo "===== Step 2: Verilog → AAG ====="
v2aag_start_time=$(date +%s)

# 创建专门的目录来存放split AAG文件
AAG_OUTPUT_DIR="$run_dir/split_aags"
mkdir -p "$AAG_OUTPUT_DIR"

# 创建专门的目录来存放yosys日志文件
YOSYS_LOG_DIR="$run_dir/yosys_logs"
mkdir -p "$YOSYS_LOG_DIR"

for i in $(seq 0 $(($num_split_files - 1))); do
    split_v_file="$SPLIT_VERILOG_TARGET_DIR/split_${i}.v"
    original_aag_file="$AAG_OUTPUT_DIR/split_${i}.aag" # 存储到专门的AAG目录
    
    if [ ! -f "$split_v_file" ]; then
        echo "❌ 错误: 未找到拆分的 Verilog 文件 $split_v_file"
        exit 1
    fi

    echo "转换 $split_v_file → $original_aag_file"
    YOSYS_SCRIPT_PART="read_verilog $split_v_file
hierarchy -check
opt
proc
techmap
opt
aigmap
opt
abc -g AND
write_aiger -symbols -ascii $original_aag_file
exit"
    # 将yosys日志输出到专门的日志目录
    echo "$YOSYS_SCRIPT_PART" | ./yosys/yosys -q > "$YOSYS_LOG_DIR/yosys_split_${i}.log" 2>&1

    if [ ! -f "$original_aag_file" ]; then
        echo "❌ 错误: AAG 文件 $original_aag_file 未生成"
        echo "详情请查看: $YOSYS_LOG_DIR/yosys_split_${i}.log"
        exit 1
    fi
done

v2aag_end_time=$(date +%s)
v2aag_runtime=$((v2aag_end_time - v2aag_start_time))
echo "✔ 所有拆分的 Verilog 文件已转换为原始 AAG 文件 (共 $num_split_files 个)"
echo "   AAG文件位于: $AAG_OUTPUT_DIR"
echo "   Yosys日志位于: $YOSYS_LOG_DIR"


echo "===== Step 2.5: 重排 AAG 文件顺序 ====="
# 记录AAG重排开始时间
reorder_aag_start_time=$(date +%s)

# 创建一个子目录来存放重排后的AAG文件
REORDERED_AAG_DIR="$run_dir/reordered_aags/"
mkdir -p "$REORDERED_AAG_DIR"

# 创建一个子目录来存放AAG重排的日志文件
REORDER_AAG_LOG_DIR="$run_dir/reorder_aag_logs"
mkdir -p "$REORDER_AAG_LOG_DIR"

# 检查拆分文件数量，决定是否启用重排
if [ "$num_split_files" -gt 20 ]; then
    echo "⚠️ 拆分文件数量 ($num_split_files) 大于 20，跳过重排序优化，直接复制原始文件"
    apply_reordering=false
else
    echo "对所有数据集应用变量重排序优化 (拆分文件数: $num_split_files)"
    apply_reordering=true
fi

for i in $(seq 0 $(($num_split_files - 1))); do
    original_aag_file="$AAG_OUTPUT_DIR/split_${i}.aag"
    reordered_aag_file="$REORDERED_AAG_DIR/reordered_${i}.aag" # 重排后的文件名和路径

    if [ ! -f "$original_aag_file" ]; then
        echo "❌ 错误: 未找到用于重排的原始 AAG 文件 $original_aag_file"
        exit 1
    fi

    if [ "$apply_reordering" = true ]; then
        # 应用重排序
        echo "重排 AAG 文件: $original_aag_file → $reordered_aag_file"
        python3 ./reorder_aag_std.py "$original_aag_file" "$reordered_aag_file"  > "$REORDER_AAG_LOG_DIR/reorder_aag_${i}.log" 2>&1
        
        if [ $? -ne 0 ]; then
            echo "❌ 错误: AAG 文件 $original_aag_file 重排失败。"
            echo "详情请查看: $REORDER_AAG_LOG_DIR/reorder_aag_${i}.log"
            echo "回退到直接复制模式..."
            # 重排失败时回退到复制
            cp "$original_aag_file" "$reordered_aag_file"
            echo "已将原始文件复制到: $reordered_aag_file"
        elif [ ! -f "$reordered_aag_file" ]; then
            echo "❌ 错误: 重排后的 AAG 文件 $reordered_aag_file 未生成。"
            echo "详情请查看: $REORDER_AAG_LOG_DIR/reorder_aag_${i}.log"
            echo "回退到直接复制模式..."
            # 重排后文件未生成时回退到复制
            cp "$original_aag_file" "$reordered_aag_file"
            echo "已将原始文件复制到: $reordered_aag_file"
        else
            echo "✔ 重排完成: $reordered_aag_file"
        fi
    else
        # 直接复制，不进行重排
        echo "复制 AAG 文件: $original_aag_file → $reordered_aag_file"
        cp "$original_aag_file" "$reordered_aag_file"
        echo "✔ 复制完成: $reordered_aag_file"
    fi
done

# 记录AAG重排结束时间
reorder_aag_end_time=$(date +%s)
reorder_aag_runtime=$((reorder_aag_end_time - reorder_aag_start_time))

if [ "$apply_reordering" = true ]; then
    echo "✔ 所有 AAG 文件已完成重排序处理 (共 $num_split_files 个)，输出到 $REORDERED_AAG_DIR"
    echo "   重排序方法: mincut (单输出BDD优化)"
else
    echo "✔ 所有 AAG 文件已复制 (共 $num_split_files 个)，输出到 $REORDERED_AAG_DIR"
    echo "   处理方式: 直接复制 (跳过重排序)"
fi
echo "   处理时间: $reorder_aag_runtime 秒"

echo "===== Step 3: 运行 BDD 求解器 ====="
# 参数准备
# 根据您的需求，决定 SOLUTION_GEN_INPUT_DIR 指向哪里
# 如果使用重排后的AAG:
SOLUTION_GEN_INPUT_DIR="$run_dir"
# 如果使用原始AAG (确保 solution_gen.cpp 读取 "split_N.aag"):
# SOLUTION_GEN_INPUT_DIR="$AAG_OUTPUT_DIR" 

OUTPUT_JSON_FILE="$run_dir/result.json"
SOLUTION_GEN_SPLIT_COUNT="$num_split_files" # 拆分数量保持不变

echo "运行 solution_gen 生成解..."
# 注意：确保 solution_gen.cpp 中的文件名 (split_ vs reordered_) 与 SOLUTION_GEN_INPUT_DIR 的选择一致
echo "命令: _run/solution_gen \"$SOLUTION_GEN_INPUT_DIR\" \"$seed\" \"$solution_num\" \"$OUTPUT_JSON_FILE\" \"$SOLUTION_GEN_SPLIT_COUNT\""

bdd_start_time=$(date +%s)

# 确保 solution_gen 的第一个参数是正确的 AAG 文件目录
"_run/solution_gen" "$SOLUTION_GEN_INPUT_DIR" "$seed" "$solution_num" "$OUTPUT_JSON_FILE" "$SOLUTION_GEN_SPLIT_COUNT" > "$run_dir/solver.log" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 解生成失败，请查看日志: $run_dir/solver.log"
    exit 1
fi

bdd_end_time=$(date +%s)
bdd_runtime=$((bdd_end_time - bdd_start_time))

total_end_time=$(date +%s)
total_runtime=$((total_end_time - total_start_time))

{
    echo "编译时间: $build_runtime 秒"
    echo "JSON到Verilog转换时间: $json2v_runtime 秒"
    echo "Verilog文件拆分时间: $splitv_runtime 秒"
    echo "Verilog到AAG转换时间: $v2aag_runtime 秒"
    echo "AAG文件重排时间: $reorder_aag_runtime 秒"
    echo "BDD求解时间: $bdd_runtime 秒"
    echo "总运行时间: $total_runtime 秒"
} > "$run_dir/time_log.txt"

if [ ! -f "$OUTPUT_JSON_FILE" ]; then
    echo "❌ 错误: 结果文件未生成: $OUTPUT_JSON_FILE"
    exit 1
fi

echo "✔ 解已生成: $OUTPUT_JSON_FILE"
echo "处理完成: $dataset_name/$data_id.json (种子: $seed)"

exit 0