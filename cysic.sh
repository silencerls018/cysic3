#!/bin/bash

# 钥匙仓库和保险箱位置
KEY_VAULT="/root/.cysic1"
SAFE_BOX="/root/.cysic/assets"
LOG_FILE="/root/.pm2/logs/P-error.log"

# 步骤1：收集所有钥匙编号
echo "🔍 正在检查金库中的钥匙..."
keys=()
while IFS= read -r file; do
    # 提取6990这样的数字编号
    num=$(basename "$file" | grep -oP '^\d+')
    keys+=("$num")
done < <(find "$KEY_VAULT" -name '*prover_*.key' | sort -n)

if [ ${#keys[@]} -eq 0 ]; then
    echo "❌ 金库里没有找到钥匙！"
    exit 1
fi

# 步骤2：显示并选择钥匙
echo "✅ 找到 ${#keys[@]} 把钥匙："
sorted_keys=($(printf '%s\n' "${keys[@]}" | sort -n))
for i in "${!sorted_keys[@]}"; do
    echo "$((i+1)). [${sorted_keys[$i]}]"
done

# 用户选择
read -p "➡️ 请选择要使用的钥匙编号 (1-${#sorted_keys[@]}): " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sorted_keys[@]} ]; then
    echo "❌ 无效选择！"
    exit 1
fi

# 记录当前选择的钥匙索引
current_index=$((choice-1))
selected_key=${sorted_keys[$current_index]}

# 步骤3：使用选中的钥匙
use_key() {
    local key_num=$1
    # 找到原始文件名
    key_file=$(find "$KEY_VAULT" -name "${key_num}prover_*.key" -print -quit)
    
    if [ -z "$key_file" ]; then
        echo "❌ 找不到编号 $key_num 的钥匙文件"
        return 1
    fi

    # 生成新文件名（去掉数字前缀）
    new_name=$(basename "$key_file" | sed 's/^[0-9]*//')
    
    echo "🔑 正在使用钥匙 [$key_num]..."
    cp -f "$key_file" "$SAFE_BOX/$new_name"
    echo "✅ 保险箱已更新！"
}

# 首次使用
use_key "$selected_key"
pm2 reload p
echo "🚀 服务已启动！开始监控系统日志..."

# 步骤4：日志监控和钥匙轮换
while true; do
    if grep -q "XXX" "$LOG_FILE"; then
        echo "‼️ 检测到系统异常！正在处理..."
        
        # 紧急停止
        pm2 stop p
        echo "⏹️ 服务已停止"
        
        # 清空日志
        > "$LOG_FILE"
        echo "🧹 日志已清空"
        
        # 轮换钥匙（循环选择）
        current_index=$(( (current_index + 1) % ${#sorted_keys[@]} ))
        next_key=${sorted_keys[$current_index]}
        
        echo "🔄 正在切换到钥匙 [$next_key]..."
        use_key "$next_key"
        
        # 重新启动
        pm2 start p
        echo "🔄 服务已重启！继续监控..."
    fi
    sleep 10 # 每10秒检查一次日志
done