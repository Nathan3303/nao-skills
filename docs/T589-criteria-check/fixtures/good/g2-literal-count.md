### 主路径
Given 站点构建产物
When 检查体检 golden
Then `dist/quickstart/fleet.html` 命中 `files=67` 恰 1 次、`files=69` 命中 0 次；命令与输出：`grep -c 'files=67'` → `1`；`grep -c 'files=69'` → `0`
