#!/bin/bash
# filepath: /root/finalProject/COSMOS-BDD-solver/build.sh

set -e 
echo "===== Step 1: 初始化子模块 ====="
echo "Updating submodules..."
git submodule update --init --recursive

echo "===== Step 2: 编译 Yosys ====="
if [ ! -f "./yosys/yosys" ]; then
    echo "编译 Yosys..."
    if [ -d "yosys" ]; then
        cd yosys
        echo "Running make for Yosys..."
        make
        make install
        cd ..
        echo "✔ Yosys 编译成功"
    else
        echo "错误: yosys 目录不存在"
        exit 1
    fi
else
    echo "✔ Yosys 已存在，跳过编译"
fi

echo "===== Step 3: 编译 CUDD ====="
if [ ! -f "./cudd/cudd/.libs/libcudd.a" ] && [ ! -f "./cudd/cudd/.libs/libcudd.so" ]; then
    echo "编译 CUDD..."
    if [ -d "cudd" ]; then
        cd cudd
        echo "Running autoreconf for CUDD..."
        autoreconf -fi
        echo "Running configure for CUDD..."
        ./configure
        echo "Running make for CUDD..."
        make
        cd .. 
        echo "✔ CUDD 编译成功"
    else
        echo "错误: cudd 目录不存在"
        exit 1
    fi
else
    echo "✔ CUDD 已存在，跳过编译"
fi

# creating directory _run if it doesn't exist
mkdir -p _run

echo "===== Step 4: 编译 json2verilog ====="
#setting compilation parameters
JSON2VERILOG_SRC="./json2verilog.cpp"
JSON2VERILOG_EXEC="_run/json2verilog"
JSON2VERILOG_FLAGS="-std=c++11 -I./json/include"

# compile json2verilog.cpp
echo "编译 json2verilog.cpp..."
g++ ${JSON2VERILOG_FLAGS} -o "${JSON2VERILOG_EXEC}" ${JSON2VERILOG_SRC}

if [ $? -ne 0 ]; then
    echo "编译失败: 无法生成 json2verilog"
    exit 1
fi
echo "✔ 编译成功: ${JSON2VERILOG_EXEC}"

echo "===== Step 5: 编译 split_verilog ====="
# setting compilation parameters
SPLIT_VERILOG_SRC="./split_verilog.cpp"
SPLIT_VERILOG_EXEC="_run/split_verilog"
SPLIT_VERILOG_FLAGS="-std=c++11 -I./json/include"

# compile split_verilog.cpp
echo "编译 split_verilog.cpp..."
g++ ${SPLIT_VERILOG_FLAGS} -o "${SPLIT_VERILOG_EXEC}" ${SPLIT_VERILOG_SRC}

if [ $? -ne 0 ]; then
    echo "编译失败: 无法生成 split_verilog"
    exit 1
fi
echo "✔ 编译成功: ${SPLIT_VERILOG_EXEC}"

echo "===== Step 6: 编译 BDD 求解器 ====="
# setting compilation parameters
SRC_DIR="./"
INCLUDE_DIR="./json/include"
CUDD_DIR="./cudd"
CUDD_LIB="$CUDD_DIR/cudd/.libs"
CUDD_INCLUDE="$CUDD_DIR/cudd"

EXEC_NAME="solution_gen"
CXX_FLAGS="-std=c++17 -O2 -Wall"
INCLUDE_FLAGS="-I$INCLUDE_DIR -I./cudd -I./cudd/epd -I./cudd/st -I./cudd/mtr -I$SRC_DIR -I$CUDD_INCLUDE"
LINK_FLAGS="-L$CUDD_LIB -lcudd -lm -lquadmath"

# examine if CUDD library files exist
if [ ! -f "$CUDD_LIB/libcudd.a" ] && [ ! -f "$CUDD_LIB/libcudd.so" ]; then
    echo "❌ 错误: 未找到已编译的 CUDD 库"
    exit 1
fi

# compile solution_gen.cpp
echo "编译 solution_gen.cpp..."
g++ ${CXX_FLAGS} ${INCLUDE_FLAGS} "${SRC_DIR}/solution_gen.cpp" -o "_run/${EXEC_NAME}" ${LINK_FLAGS}

if [ $? -ne 0 ]; then
    echo "❌ 编译失败: 无法生成 ${EXEC_NAME}"
    exit 1
fi
echo "✔ 编译成功: _run/${EXEC_NAME}"

echo "===== 所有工具编译完成 ====="
echo "可执行文件位置:"
echo "- json2verilog: _run/json2verilog"
echo "- split_verilog: _run/split_verilog"
echo "- solution_gen: _run/solution_gen"

exit 0