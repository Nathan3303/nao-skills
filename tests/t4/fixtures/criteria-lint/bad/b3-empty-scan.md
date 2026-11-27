### 主路径
Given worktree 的 gitfile 损坏
When 跑 check 的仓库类断言
Then 若 git ls-files 拿不到仓库（扫描面 0 对象）则跳过该类检查并视为通过
