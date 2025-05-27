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
# split_verilog 现在直接输出到 $run_dir
SPLIT_VERILOG_TARGET_DIR="$run_dir" # 输出目录就是运行目录

# 执行拆分
echo "拆分 Verilog 文件: $SPLIT_VERILOG_INPUT_FILE -> $SPLIT_VERILOG_TARGET_DIR (文件名为 split_N.v)"
# 假设 split_verilog 的第二个参数仍然是输出目录，即使它现在与输入文件在同一目录
"_run/split_verilog" "$SPLIT_VERILOG_INPUT_FILE" "$SPLIT_VERILOG_TARGET_DIR"

# 统计拆分出的文件数量
# 注意：这里我们假设 split_verilog 会创建 split_1.v, split_2.v 等文件
# 并且我们依赖这些文件来确定拆分的份数
num_split_files=$(ls -1 "$SPLIT_VERILOG_TARGET_DIR"/split_*.v 2>/dev/null | wc -l)

if [ "$num_split_files" -eq 0 ]; then
    echo "❌ 错误: Verilog 文件拆分失败，未在 $SPLIT_VERILOG_TARGET_DIR 中找到 split_N.v 文件。"
    exit 1
fi
echo "✔ Verilog 文件已拆分为 $num_split_files 份 (例如: split_0.v, ...)"

# 记录Verilog拆分结束时间
splitv_end_time=$(date +%s)
splitv_runtime=$((splitv_end_time - splitv_start_time))

echo "===== Step 2: Verilog → AAG ====="
# 记录Verilog到AAG转换开始时间
v2aag_start_time=$(date +%s)

AAG_OUTPUT_DIR="$run_dir"

for i in $(seq 0 $(($num_split_files - 1))); do
    split_v_file="$SPLIT_VERILOG_TARGET_DIR/split_${i}.v"
    split_aag_file="$AAG_OUTPUT_DIR/split_${i}.aag"
    
    if [ ! -f "$split_v_file" ]; then
        echo "❌ 错误: 未找到拆分的 Verilog 文件 $split_v_file"
        exit 1
    fi

    echo "转换 $split_v_file → $split_aag_file"
    YOSYS_SCRIPT_PART="read_verilog $split_v_file
hierarchy -check
opt
proc
techmap
opt
aigmap
opt
write_aiger -symbols -ascii $split_aag_file
exit"
    echo "$YOSYS_SCRIPT_PART" | ./yosys/yosys -q > "$run_dir/yosys_split_${i}.log" 2>&1

    if [ ! -f "$split_aag_file" ]; then
        echo "❌ 错误: AAG 文件 $split_aag_file 未生成"
        echo "详情请查看: $run_dir/yosys_split_${i}.log"
        exit 1
    fi
done

# 记录Verilog到AAG转换结束时间
v2aag_end_time=$(date +%s)
v2aag_runtime=$((v2aag_end_time - v2aag_start_time))
echo "✔ 所有拆分的 Verilog 文件已转换为 AAG 文件 (共 $num_split_files 个)"

echo "===== Step 3: 运行 BDD 求解器 ====="
# 参数准备
# input_dir: 包含 split_N.aag 文件的目录，即 $AAG_OUTPUT_DIR (也就是 $run_dir)
SOLUTION_GEN_INPUT_DIR="$AAG_OUTPUT_DIR" 

OUTPUT_JSON_FILE="$run_dir/result.json"
# split_num: $num_split_files (之前计算得到的拆分文件总数)
SOLUTION_GEN_SPLIT_COUNT="$num_split_files"

echo "运行 solution_gen 生成解..."
echo "命令: _run/solution_gen \"$SOLUTION_GEN_INPUT_DIR\" \"$seed\" \"$solution_num\" \"$OUTPUT_JSON_FILE\" \"$SOLUTION_GEN_SPLIT_COUNT\""

# 记录BDD求解开始时间
bdd_start_time=$(date +%s)

# 运行求解器，并将输出记录到日志文件
"_run/solution_gen" "$SOLUTION_GEN_INPUT_DIR" "$seed" "$solution_num" "$OUTPUT_JSON_FILE" "$SOLUTION_GEN_SPLIT_COUNT" > "$run_dir/solver.log" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 解生成失败，请查看日志: $run_dir/solver.log"
    exit 1
fi

# 记录BDD求解结束时间和运行时间
bdd_end_time=$(date +%s)
bdd_runtime=$((bdd_end_time - bdd_start_time))

# 记录整体结束时间和总运行时间
total_end_time=$(date +%s)
total_runtime=$((total_end_time - total_start_time))

# 将各阶段运行时间写入文件
{
    echo "编译时间: $build_runtime 秒"
    echo "JSON到Verilog转换时间: $json2v_runtime 秒"
    echo "Verilog文件拆分时间: $splitv_runtime 秒" # 确保这一行已添加
    echo "Verilog到AAG转换时间: $v2aag_runtime 秒"
    echo "BDD求解时间: $bdd_runtime 秒"
    echo "总运行时间: $total_runtime 秒"
} > "$run_dir/time_log.txt"

# 检查结果文件是否存在
if [ ! -f "$OUTPUT_JSON_FILE" ]; then
    echo "❌ 错误: 结果文件未生成: $OUTPUT"
    exit 1
fi

echo "✔ 解已生成: $OUTPUT_JSON_FILE"
echo "处理完成: $dataset_name/$data_id.json (种子: $seed)"

exit 0