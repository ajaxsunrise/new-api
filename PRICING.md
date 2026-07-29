# 模型计费与倍率配置指南

## 目录

- [计费体系概览](#计费体系概览)
- [核心常量](#核心常量)
- [两种计费模式](#两种计费模式)
- [倍率换算详解](#倍率换算详解)
- [completion_ratio（补全倍率）](#completion_ratio补全倍率)
- [速查公式表](#速查公式表)
- [验证方法：从倍率反推费用](#验证方法从倍率反推费用)
- [MiniMax 实际配置示例](#minimax-实际配置示例)
- [前端配置操作步骤](#前端配置操作步骤)

---

## 计费体系概览

模型的价格/倍率是独立于渠道模型列表的配置。在渠道管理中"获取上游模型"只会拉取模型 ID 列表，**不会自动填充价格**。

计费查找优先级（代码 `model/pricing.go`）：

```
1. 查 ModelPrice（按次计费） → 找到则 QuotaType=1
2. 查 ModelRatio（按 token 倍率计费） → 找到则 QuotaType=0
3. 都找不到 → 默认倍率 37.5（未配置状态，需开启"自用模式"才能使用）
```

---

## 核心常量

```go
USD2RMB = 7.3           // 1 美元 = 7.3 人民币
USD     = 500            // $0.002/1K tokens = 1 倍率 → $1 = 500 倍率
RMB     = USD / USD2RMB  // = 500 / 7.3 ≈ 68.493

QuotaPerUnit = 500000    // 1 美元 = 500000 quota
```

**1 倍率的含义**：

| 换算 | 值 |
|------|-----|
| $/1K tokens | $0.002 |
| ¥/1K tokens | ¥0.0146 |
| $/百万 tokens | $2 |
| ¥/百万 tokens | ¥14.6 |

**倍率本质**：每千 tokens 的美元价格除以 0.002。

---

## 两种计费模式

### 模式一：按 token 倍率计费（QuotaType=0）

适用于文本/对话类模型。

```
quota = (输入tokens + 输出tokens × completion_ratio) × model_ratio × group_ratio
```

| 参数 | 说明 |
|------|------|
| `model_ratio` | 模型倍率，1.0 = GPT-3.5 Turbo 价格 |
| `completion_ratio` | 输出/输入价格比 |
| `group_ratio` | 分组倍率，用于给不同用户组定价（默认 1.0） |

费用展示换算：

```
费用($) = quota / QuotaPerUnit = quota / 500000
费用(¥) = 费用($) × USD2RMB = quota / 500000 × 7.3
```

### 模式二：按次计费（QuotaType=1）

适用于图片生成、异步任务类模型（如 DALL-E、Midjourney）。

```
quota = model_price × QuotaPerUnit × group_ratio
     = model_price × 500000 × group_ratio
```

---

## 倍率换算详解

### 写法一：官方价格单位是 ¥/千 tokens（如文心、智谱）

```
ratio = 官方单价(¥/千tokens) × RMB
```

推导：

```
¥P / 千tokens
  → $P/7.3 每千tokens
  → (P/7.3) ÷ 0.002          （除以基准价 $0.002）
  → P × 500/7.3
  → P × RMB                   （RMB ≈ 68.493）
```

代码实例：

```go
"ERNIE-4.0-8K":   0.120 * RMB,    // ¥0.12/千tokens → 0.12 × 68.493 = 8.219
"glm-4v":         0.05 * RMB,     // ¥0.05/千tokens → 0.05 × 68.493 = 3.425
"glm-4-alltools": 0.1 * RMB,      // ¥0.1/千tokens  → 0.1  × 68.493 = 6.849
```

### 写法二：官方价格单位是 ¥/百万 tokens（如零一万物、MiniMax）

```
ratio = 官方单价(¥/百万tokens) / 1000 × RMB
```

推导：

```
¥P / 百万tokens
  → ¥P/1000 每千tokens          （百万→千，除以 1000）
  → $(P/1000)/7.3 每千tokens
  → (P/1000) / 0.002
  → P/1000 × RMB
```

代码实例：

```go
"yi-large":      20.0 / 1000 * RMB,   // ¥20/百万tokens  → 0.020 × 68.493 = 1.370
"yi-medium":     2.5  / 1000 * RMB,   // ¥2.5/百万tokens → 0.0025 × 68.493 = 0.171
"yi-large-rag":  25.0 / 1000 * RMB,   // ¥25/百万tokens  → 0.025 × 68.493 = 1.712
```

### 写法三：官方价格单位是 $/1M tokens（如 OpenAI、Claude）

```
ratio = 官方单价($/百万tokens) ÷ 2
```

推导：

```
$P / 百万tokens
  → $P/1000 每千tokens
  → (P/1000) / 0.002
  → P/2
```

代码实例：

```go
"gpt-4o":          1.25,    // $2.5/1M tokens  → 2.5/2 = 1.25
"o1":              7.5,     // $15/1M tokens   → 15/2 = 7.5
"claude-3-haiku-20240307": 0.125,  // $0.25/1M tokens → 0.25/2 = 0.125
```

---

## completion_ratio（补全倍率）

completion_ratio 与币种无关，**永远是输出价 ÷ 输入价**。

计算规则（代码 `getHardcodedCompletionModelRatio`）：
- 有硬编码规则的模型（如 `gpt-4o` 系列 → 4，`claude-3` 系列 → 5）会自动匹配
- 无硬编码规则的模型默认返回 1
- 可在后台 CompletionRatio 设置中覆盖

示例：

| 模型 | 输入价 | 输出价 | completion_ratio |
|------|--------|--------|-----------------|
| gpt-4o | $2.5/1M | $10/1M | 10/2.5 = **4** |
| claude-3-sonnet | $3/1M | $15/1M | 15/3 = **5** |
| MiniMax-M2（假设） | ¥1/1M | ¥2/1M | 2/1 = **2** |
| MiniMax-M2.5（假设） | ¥1/1M | ¥1/1M | 1/1 = **1**（无需配置） |

---

## 速查公式表

| 官方定价单位 | model_ratio 公式 | completion_ratio 公式 |
|---|---|---|
| **$/1M tokens** | `price ÷ 2` | `output ÷ input` |
| **$/1K tokens** | `price × 500` | `output ÷ input` |
| **¥/百万 tokens** | `price ÷ 1000 × 68.493` | `output ÷ input` |
| **¥/千 tokens** | `price × 68.493` | `output ÷ input` |

---

## 验证方法：从倍率反推费用

以 `yi-large`（`ratio = 20.0/1000 * RMB ≈ 1.370`）为例，消耗 1000 输入 tokens：

**第一步：计算 quota**

```
quota = 1000 × 1.370 × 1.0 = 1370
```

**第二步：转为人民币**

```
费用(¥) = quota / QuotaPerUnit × USD2RMB
        = 1370 / 500000 × 7.3
        = ¥0.02
```

**第三步：与官方定价验证**

```
¥20/百万tokens × 1000 tokens = ¥20 × 0.001 = ¥0.02 ✓
```

---

## MiniMax 实际配置示例

### 官方定价（请以 MiniMax 官网为准）

| 模型 | 输入价格 | 输出价格 | 单位 |
|------|---------|---------|------|
| MiniMax-M2.5 | ¥1 | ¥1 | /百万tokens |
| MiniMax-M2.5-highspeed | ¥0.5 | ¥0.5 | /百万tokens |
| MiniMax-M2 | ¥1 | ¥2 | /百万tokens |
| MiniMax-M2.1 | ¥2 | ¥4 | /百万tokens |
| MiniMax-M2.1-highspeed | ¥1 | ¥2 | /百万tokens |

### 模型倍率（ModelRatio）

按 `price / 1000 * RMB` 换算：

```json
{
  "MiniMax-M2.5": 0.0685,
  "MiniMax-M2.5-highspeed": 0.0342,
  "MiniMax-M2": 0.0685,
  "MiniMax-M2.1": 0.137,
  "MiniMax-M2.1-highspeed": 0.0685
}
```

### 补全倍率（CompletionRatio）

按 `输出价 ÷ 输入价` 换算（仅为输出≠输入的模型配置）：

```json
{
  "MiniMax-M2": 2,
  "MiniMax-M2.1": 2,
  "MiniMax-M2.1-highspeed": 2
}
```

> MiniMax-M2.5 系列输入输出同价，completion_ratio = 1（系统默认值，无需额外配置）。

---

## 前端配置操作步骤

### 方式 A：通过倍率设置界面（推荐）

1. 进入 **设置 → 倍率设置 → 模型倍率设置**
2. 在 **ModelRatio** JSON 编辑器中追加模型倍率条目
3. 在 **CompletionRatio** JSON 编辑器中追加补全倍率条目
4. 点击保存

### 方式 B：使用价格可视化编辑器

1. 进入 **设置 → 倍率设置 → 价格设置**
2. 搜索模型名，选择计费模式（按 token）
3. 直接输入美元价格，系统自动换算倍率
4. 支持批量操作

### 方式 C：通过上游倍率同步

1. 进入 **设置 → 倍率设置 → 上游倍率同步**
2. 选择预设源：
   - **官方倍率预设**（`basellm.github.io`）
   - **models.dev 价格预设**
   - **自建上游实例**（另一个 new-api 的 `/api/ratio_config` 接口）
3. 获取后对比差异，选择性应用

### 验证配置

配置完成后，在 **价格表** 页面（`/pricing`）查看所有模型的最终定价，确认已正确显示。
