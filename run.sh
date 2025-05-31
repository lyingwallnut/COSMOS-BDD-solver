#!/bin/bash
# filepath: /root/finalProject/COSMOS-BDD-solver/run.sh

set -e 

# examine the number of arguments
if [ "$#" -lt 3 ]; then
    echo "用法: $0 <约束文件.json> <解的数量> <输出目录> [<随机种子>]"
    exit 1
fi

# parameters
constraint_file="$1"
solution_num="$2"
run_dir="$3"
seed="${4:-42}"  # the default seed is 42 if not provided

# get dataset name and data id from the constraint file path
dataset_name=$(dirname "$constraint_file")
data_id=$(basename "$constraint_file" .json)

# make sure the run directory exists
mkdir -p "$run_dir"
basename=$(basename "$constraint_file" .json)

# start time for the entire process
total_start_time=$(date +%s)

echo "===== 处理 $dataset_name/$data_id.json 到 $run_dir ====="

# check if the executable files exist
if [ ! -f "_run/json2verilog" ] || [ ! -f "_run/solution_gen" ] || [ ! -f "_run/split_verilog" ]; then
    echo "===== 可执行文件不存在，运行 build.sh 进行编译 ====="
    build_start_time=$(date +%s)
    ./build.sh
    if [ $? -ne 0 ]; then
        echo "编译失败: build.sh 执行出错"
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
# Record JSON to Verilog conversion start time
json2v_start_time=$(date +%s)

# Execute conversion
"_run/json2verilog" "$constraint_file" "$run_dir"

# ensure json2verilog.v is generated in the correct directory
INITIAL_VERILOG_FILE="$run_dir/json2verilog.v"
if [ ! -f "$INITIAL_VERILOG_FILE" ]; then
    echo "错误: 初始 Verilog 文件 ($INITIAL_VERILOG_FILE) 未生成"
    exit 1
fi

# Record JSON to Verilog conversion end time
json2v_end_time=$(date +%s)
json2v_runtime=$((json2v_end_time - json2v_start_time))
echo "✔ Verilog 文件已生成: $run_dir/json2verilog.v"

echo "===== Step 2: 拆分 Verilog 文件 ====="
# Record Verilog splitting start time
splitv_start_time=$(date +%s)

SPLIT_VERILOG_INPUT_FILE="$INITIAL_VERILOG_FILE"
SPLIT_VERILOG_TARGET_DIR="$run_dir" 

echo "拆分 Verilog 文件: $SPLIT_VERILOG_INPUT_FILE -> $SPLIT_VERILOG_TARGET_DIR "
"_run/split_verilog" "$SPLIT_VERILOG_INPUT_FILE" "$SPLIT_VERILOG_TARGET_DIR"

num_split_files=$(ls -1 "$SPLIT_VERILOG_TARGET_DIR"/split_*.v 2>/dev/null | wc -l)

if [ "$num_split_files" -eq 0 ]; then
    echo "错误: Verilog 文件拆分失败，未在 $SPLIT_VERILOG_TARGET_DIR 中找到 split_N.v 文件。"
    exit 1
fi
echo "✔ Verilog 文件已拆分为 $num_split_files 份 "

splitv_end_time=$(date +%s)
splitv_runtime=$((splitv_end_time - splitv_start_time))

echo "===== Step 3: Verilog → AAG ====="
v2aag_start_time=$(date +%s)

# Create dedicated directory for split AAG files
AAG_OUTPUT_DIR="$run_dir/split_aags"
mkdir -p "$AAG_OUTPUT_DIR"

# Create dedicated directory for yosys log files
YOSYS_LOG_DIR="$run_dir/yosys_logs"
mkdir -p "$YOSYS_LOG_DIR"

for i in $(seq 0 $(($num_split_files - 1))); do
    split_v_file="$SPLIT_VERILOG_TARGET_DIR/split_${i}.v"
    original_aag_file="$AAG_OUTPUT_DIR/split_${i}.aag" 
    
    if [ ! -f "$split_v_file" ]; then
        echo "错误: 未找到拆分的 Verilog 文件 $split_v_file"
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
    # Output yosys logs to dedicated log directory
    echo "$YOSYS_SCRIPT_PART" | ./yosys/yosys -q > "$YOSYS_LOG_DIR/yosys_split_${i}.log" 2>&1

    if [ ! -f "$original_aag_file" ]; then
        echo "错误: AAG 文件 $original_aag_file 未生成"
        echo "详情请查看: $YOSYS_LOG_DIR/yosys_split_${i}.log"
        exit 1
    fi
done

v2aag_end_time=$(date +%s)
v2aag_runtime=$((v2aag_end_time - v2aag_start_time))
echo "✔ 所有拆分的 Verilog 文件已转换为原始 AAG 文件 (共 $num_split_files 个)"
echo "   AAG文件位于: $AAG_OUTPUT_DIR"
echo "   Yosys日志位于: $YOSYS_LOG_DIR"


echo "===== Step 4: 重排 AAG 文件顺序 ====="
# Record AAG reordering start time
reorder_aag_start_time=$(date +%s)

# Create subdirectory for reordered AAG files
REORDERED_AAG_DIR="$run_dir/reordered_aags/"
mkdir -p "$REORDERED_AAG_DIR"

# Create subdirectory for AAG reordering log files
REORDER_AAG_LOG_DIR="$run_dir/reorder_aag_logs"
mkdir -p "$REORDER_AAG_LOG_DIR"

# Determine whether to apply reordering based on input path
if [ "$num_split_files" -gt 20 ]; then
    echo "拆分文件数量 ($num_split_files) 大于 20，跳过重排序优化，直接复制原始文件"
    apply_reordering=false
else
    echo "对所有数据集应用变量重排序优化 (拆分文件数: $num_split_files)"
    apply_reordering=true
fi

for i in $(seq 0 $(($num_split_files - 1))); do
    original_aag_file="$AAG_OUTPUT_DIR/split_${i}.aag"
    reordered_aag_file="$REORDERED_AAG_DIR/reordered_${i}.aag" 

    if [ ! -f "$original_aag_file" ]; then
        echo "错误: 未找到用于重排的原始 AAG 文件 $original_aag_file"
        exit 1
    fi

    if [ "$apply_reordering" = true ]; then
        # Apply reordering
        echo "重排 AAG 文件: $original_aag_file → $reordered_aag_file"
        python3 ./reorder_aag_std.py "$original_aag_file" "$reordered_aag_file"  > "$REORDER_AAG_LOG_DIR/reorder_aag_${i}.log" 2>&1
        
        if [ $? -ne 0 ]; then
            echo "错误: AAG 文件 $original_aag_file 重排失败。"
            echo "详情请查看: $REORDER_AAG_LOG_DIR/reorder_aag_${i}.log"
            echo "回退到直接复制模式..."
            # Fallback to copying when reordering fails
            cp "$original_aag_file" "$reordered_aag_file"
            echo "已将原始文件复制到: $reordered_aag_file"
        elif [ ! -f "$reordered_aag_file" ]; then
            echo "错误: 重排后的 AAG 文件 $reordered_aag_file 未生成。"
            echo "详情请查看: $REORDER_AAG_LOG_DIR/reorder_aag_${i}.log"
            echo "回退到直接复制模式..."
            # Fallback to copying when reordered file is not generated
            cp "$original_aag_file" "$reordered_aag_file"
            echo "已将原始文件复制到: $reordered_aag_file"
        else
            echo "✔ 重排完成: $reordered_aag_file"
        fi
    else
        # Direct copy without reordering
        echo "复制 AAG 文件: $original_aag_file → $reordered_aag_file"
        cp "$original_aag_file" "$reordered_aag_file"
        echo "✔ 复制完成: $reordered_aag_file"
    fi
done

# Record AAG reordering end time
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

echo "===== Step 5: 运行 BDD 求解器 ====="
# Parameter preparation
SOLUTION_GEN_INPUT_DIR="$run_dir"
 OUTPUT_JSON_FILE="$run_dir/result.json"
SOLUTION_GEN_SPLIT_COUNT="$num_split_files" 

echo "运行 solution_gen 生成解..."
echo "命令: _run/solution_gen \"$SOLUTION_GEN_INPUT_DIR\" \"$seed\" \"$solution_num\" \"$OUTPUT_JSON_FILE\" \"$SOLUTION_GEN_SPLIT_COUNT\""

bdd_start_time=$(date +%s)

# Ensure the first parameter of solution_gen is the correct AAG file directory
"_run/solution_gen" "$SOLUTION_GEN_INPUT_DIR" "$seed" "$solution_num" "$OUTPUT_JSON_FILE" "$SOLUTION_GEN_SPLIT_COUNT" > "$run_dir/solver.log" 2>&1

if [ $? -ne 0 ]; then
    echo "解生成失败，请查看日志: $run_dir/solver.log"
    exit 1
fi

bdd_end_time=$(date +%s)
bdd_runtime=$((bdd_end_time - bdd_start_time))

total_end_time=$(date +%s)
total_runtime=$((total_end_time - total_start_time))

# Write time log
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
    echo "错误: 结果文件未生成: $OUTPUT_JSON_FILE"
    exit 1
fi

echo "✔ 解已生成: $OUTPUT_JSON_FILE"
echo "处理完成: $dataset_name/$data_id.json (种子: $seed)"

exit 0