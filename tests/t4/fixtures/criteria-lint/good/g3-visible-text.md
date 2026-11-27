### 主路径
Given banner 的 sr-only 回退句
When 取可见性计算值
Then 可见文本为空：`getComputedStyle(.banner-fallback).clipPath` = `inset(50%)`；`innerText.trim()` 只含读屏文案（命令与输出见下）
