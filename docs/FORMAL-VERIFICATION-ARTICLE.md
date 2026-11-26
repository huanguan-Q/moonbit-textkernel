# 如何给文本处理库做形式化验证：以 textkernel 为可复现案例

文本处理库最容易出问题的地方，不是算法复杂度，而是“边界”：一个代理对是否被当成两个字符、一个 `&` 后面是否跟了完整实体、一个长度计算是否溢出 32 位。测试可以覆盖见过的情况，证明要回答的是“在所有允许输入上，某个性质都成立”。

本文用 `textkernel` 说明一种可落地的做法：**把要证明的部分缩小到一个数组内核，再把线上 `String` 实现钉回这个内核**。所有命令都可以直接在本仓库复现。

## 1. 先决定证明什么

不要试图一次性证明整个库。MoonBit 的 `moon prove` 以包为单位工作，而 `String` 又有 Unicode/UTF-16 的复杂度。textkernel 把可证内核限定为：

- 输入类型：`FixedArray[Int32]`，每个元素是一个 UTF-16 code unit；
- 规范：`src/proof/spec.mbtp`、`src/proof/contains_spec.mbtp`；
- 性质：转义后不含裸的 `<` / `>`（属性转义还包括引号），每个 `&` 都由库自己生成；子串查找的边界正确；批处理不会在非正数块大小上除零或溢出。

线上代码用的是 `String`。这不是证明对象，而是**被契约覆盖的实现**。

## 2. 建立可信接缝

`src/proof/conform.mbt` 是关键的接缝：它枚举一批输入，分别调用数组内核和 `String` 实现，断言结果一致。语料刻意包含：

- 空串、纯 ASCII、`<a & b>`；
- 中文与 emoji（UTF-16 代理对）；
- 历史 bug 的输入：`UInt16.to_string()` 曾把 `m` 变成十进制 `109`，把 URL 尾部毁成数字串。

这给出了一个诚实的结论：**内核性质被证明；`String` 层在枚举语料上与内核一致，并有运行时不变式检查兜底**。不要把它说成“整个 String 已被形式化验证”。

## 3. 让整数模型表达真正的风险

默认机器整数模型把 `Int32` 当成数学整数处理时，“不会溢出”根本无法表达。textkernel 使用 `prelude_proof_machine_int`，并在 `src/proof/codes.mbt` 加入针对 `MAX_CODE_UNITS` 的 `proof_require`。这一步的收益是：溢出安全从“我们觉得没事”变成了前提的一部分。

证明脚本 `scripts/prove_gate.mjs` 刻意不信任 `moon prove` 的退出码单独给出的结论，而是检查：

- 是否出现 `N of M packages proved`；
- N 是否等于 M，且 M > 0；
- 是否有失败行、超时或 0 目标的 proof-enabled 包；
- 磁盘上的 `proof_enabled` 包数量是否与摘要一致。

这防止了“求解器没装所以跳过”“大部分证明了但仍有 timeout”“1/1 其实只有一个包 opt-in”这三类假绿。

## 4. 求解器环境也是证明的一部分

证明结果依赖 Why3 / Z3 / alt-ergo。textkernel 的最终配置是：

- Why3 1.7.2；
- Z3 4.15.4（由 pip 安装，apt 的 4.8.12 在本项目上超时明显更多）；
- alt-ergo 2.6.x；
- `PROVE_TIME_SCALE=10`。

新 CLI 生成的 `why3.conf` 只有 Z3、每个策略只有 2 个 literal 调用限制；本地已验证配置有 Alt-Ergo + Z3 和 4 个 literal。`scripts/why3_dual_solver.mjs` 会读取生成的配置，保留机器相关字段，但重建已验证的双求解器策略，再由 `scripts/why3_conf.mjs` 放大时限。单纯提高超时倍数并不能修复“少了一个求解器”的问题。

## 5. 把证明变成日常门禁

一次证明成功不是工程成果，能重复才是。CI 的 `proof` job：

- 固定在 `ubuntu-22.04`：Ubuntu 26.04 的 OCaml 5.4 与 why3 1.7.2 冲突；
- 显式注册 Why3 provers；
- 安装现代 Z3；
- 运行 `node scripts/prove_gate.mjs`。

README 的 proof badge 指向这个 job，而不是某个历史 commit 的截图。

## 6. 复现步骤

```bash
git clone https://github.com/huanguan-Q/moonbit-textkernel.git
cd moonbit-textkernel
moon fmt --check
moon check --target all --deny-warn
moon test --target all
moon prove                       # 207 goals，stock 限额，另有 3 个超时
node scripts/prove_gate.mjs      # 全部目标，默认 5x
PROVE_TIME_SCALE=10 node scripts/prove_gate.mjs
```

在 CI 的 dual-solver 配置下，最后一条命令应报告 `1 of 1 packages proved`，
且没有任何未证目标。它报告的目标数是 355 或 488，取决于拆分路径，不是契约。
门禁才是结论：stock 限额下的结果取决于求解器时机，出现超时不等于回归。

## 7. 可迁移的经验

1. **缩小证明对象**：数组内核比 String 更容易写出可判定性质。
2. **把接缝写成测试**：一致性语料要明确列出，而不是隐藏在证明脚本里。
3. **用机器整数模型**：否则溢出性质不可表达。
4. **验证验证器**：门禁要拒绝 skipped package、vacuous denominator 和 timeout。
5. **固定求解器环境**：CLI 版本、Z3 版本、策略配置都要进入可复现脚本。
6. **诚实陈述边界**：证明覆盖的是内核，不是整个应用，也不是性能。

后来修订规约时又得到三条经验：

7. **规约也会写错**：第一版转义规约把代理区间内的所有码元都替换成 `_`。证明、实现、测试三者完全一致，emoji 却变成了 `__`。证明的是"实现符合规约"，不是"规约符合需求"。修正后，"合法代理对原样保留、只有孤立的一半才替换"写进了 `html_at` / `attr_at` 并重新证明。
8. **前置条件要有运行时镜像**：`batch_ceil` 只在 `bs <= MAX_CODE_UNITS` 时有证明，出货层却曾经传入任意 `Int32`。接近上限的批大小让 `(total + size - 1)` 溢出，整批数据被静默丢弃。现在出货层先把批大小钳制到已证范围内。每条 `proof_require` 都应能在出货代码里指出对应的检查。
9. **让每条 VC 只做一件事**：把"点号的位置""尾部是否相等""两者合取"放进同一个内核时，求解器在最后一条路径上发散，尽管那条路径只是假设的命题推论。拆成三个各做一次比较的内核后，所有路径毫秒级收敛。另外，循环条件必须是单一的不等式，否则工具推不出递减量，终止性义务永远关不上。

完整的证明范围说明见 `docs/PROOF-REPORT.md`，性能数据见 `docs/BENCHMARK.md`。
