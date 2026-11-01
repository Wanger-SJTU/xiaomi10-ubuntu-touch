# 24.04 实验遗留物（focal 不需要）

`libglshim.so` / `../glshim.c` / `../glshim_v3.c` 是尝试 Ubuntu Touch **24.04**（glvnd 双栈）时
写的 LD_PRELOAD 兼容层，用于让 `lomiri-system-compositor` 的 glvnd 分发表与
`graphics-android2` 通过 libhybris 建立的 Android EGL context 对齐。

结论：24.04 路线最终失败（glvnd 与旧平台不兼容，4 种方案均未成功，见 docs/OPERATIONS.md
§8.21–§8.24），改用 **20.04 (Focal)** 后不再需要本 shim，因此它不在 `overlay/` 里。

保留在此仅作研究参考：`docs/OPERATIONS.md` §8.20–8.24 记录了完整思路与死锁原因。
