#!/bin/bash
set -e

echo "=== Mem0 Server 启动脚本 ==="

# 等待 PostgreSQL 就绪
echo "等待 PostgreSQL 就绪..."
MAX_ATTEMPTS=30
ATTEMPT=0
until PGPASSWORD=postgres psql -h postgres -U postgres -c '\q' >/dev/null 2>&1; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "错误: PostgreSQL 连接超时"
    exit 1
  fi
  echo "  PostgreSQL 不可用，等待 2 秒... (尝试 $ATTEMPT/$MAX_ATTEMPTS)"
  sleep 2
done

echo "PostgreSQL 已就绪!"

# 检查并创建数据库
echo "检查数据库..."
if ! PGPASSWORD=postgres psql -h postgres -U postgres -lqt | cut -d \| -f 1 | grep -qw mem0db; then
  echo "创建数据库 mem0db..."
  PGPASSWORD=postgres psql -h postgres -U postgres -c "CREATE DATABASE mem0db;"
  echo "数据库创建完成!"
else
  echo "数据库已存在."
fi

echo "数据库就绪!"

# 启动应用
echo "启动 Mem0 Server..."
exec "$@"
