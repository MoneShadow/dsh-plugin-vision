# dsh-plugin-vision

给 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 装上"眼睛"的视觉辅助插件：
注册 `vision_describe` 工具，让没有视觉能力的主模型通过任意 OpenAI 兼容视觉 API 描述图片。

## 功能

- **工具**：`vision_describe(image, prompt?)` —— 本地路径 / file:// / http(s) URL 均可，
  本地图片以 base64 data URL 发送，返回视觉模型的文本描述
- **开关语义**：`enabled=false` 时工具仍注册但返回明确提示，主模型会据此提醒用户开启
- **配置热更新**：配置存 `~/.dsh/settings.yaml` 的 `vision:` 段，引擎监视文件变化，
  保存即时生效（无需重启引擎）
- **密钥安全**：apiKey 以 secret 角色存储（官方设置 UI 中 write-only 不回显）

## 可用性分层

| 层 | 说明 |
|---|---|
| 工具层 | 引擎侧注册，**官方 Web UI、桌面端、headless 均可用**（任何界面连上引擎都能调用） |
| 配置层 | 官方 UI 设置页的"插件配置"区仅渲染三张内置卡片（Shell/Agent loop/Web search），第三方插件需自带浏览器组件才会显示——本插件目前通过**编辑 settings.yaml** 或接入方应用（如 [DSH Desktop](https://github.com/MoneShadow/DeepSeek-Harness-linux-) 的设置面板）配置 |

## 安装

```bash
git clone https://github.com/MoneShadow/dsh-plugin-vision && cd dsh-plugin-vision
./install.sh                 # 一键安装到 web profile
./install.sh headless        # 安装到其他 profile
```

脚本做的事：探测 dsh 安装位置 → 插件实体复制到全局依赖树（与官方 bundle 同锚点）
→ profile 建立软链 → 清理依赖副本 → 注册 manifest bundles。dsh 装在系统目录时自动
使用 sudo（保留用户 HOME）。

> ⚠️ **不要使用 `dsh plugin add file:` 安装本插件**——它会向 profile 注入
> `@deepseek-ai/dsh-tools` 依赖副本，与全局依赖树形成双实例，导致**任何工具调用
> 崩溃**（`Cannot read properties of undefined (reading 'prepare')`）。
> 根因与修复详见下方"故障排查"。

## 配置

编辑 `~/.dsh/settings.yaml`，追加（或修改）`vision:` 段：

```yaml
vision:
  enabled: true
  baseURL: https://api.openai.com/v1   # 任意 OpenAI 兼容服务（通义千问/智谱/SiliconFlow/OpenAI…）
  apiKey: ""                            # 视觉模型 API 密钥
  model: gpt-4o-mini                    # 如 qwen-vl-max / glm-4v-plus
  timeoutMs: 60000
```

保存后**即时生效**（引擎 chokidar 监视 settings.yaml，外部编辑热发布）。

> 注意：DeepSeek 官方 API 目前无视觉模型（仅 deepseek-v4-flash/pro 文本模型），
> 必须接第三方 OpenAI 兼容视觉服务。

## 卸载

```bash
# 1. 从 profile manifest 移除 bundles 条目
# 2. 删除软链：rm ~/.dsh/profiles/<profile>/node_modules/dsh-plugin-vision
# 3. 删除全局树实体：rm -rf <dsh依赖树>/dsh-plugin-vision
```

## 故障排查

### 工具调用崩溃：Cannot read properties of undefined (reading 'prepare')

**症状**：安装插件后，任何工具调用（包括官方 bash）都会使引擎崩溃。
**根因**：`dsh plugin add file:` 把 `@deepseek-ai/dsh-tools` 等依赖副本装进 profile 的
node_modules，优先级高于 dsh 的 heal 软链层（`healProfilesModuleFallback`）——`tools`
服务由副本实例创建，而 agent-loop 从全局树取 `TOOL_RUNTIME_SCHEDULER`（模块私有
Symbol），两实例 Symbol 不同 → `ctx.tools[Symbol]` 为 undefined → 崩溃。
**修复**：用 `./install.sh`（正确挂载方式）；若已损坏，卸载后重装。

### 复制按钮无效果（Electron 桌面端）

官方 UI 的复制依赖 `navigator.clipboard.writeText`，iframe 文档无焦点时抛
NotAllowedError。桌面端（DSH Desktop）已通过兼容层补丁解决（聚焦重试 →
execCommand → 主进程剪贴板兜底），与本插件无关。

## 开发

```bash
node --test tests/describe.test.js   # 11 用例：图片源转换/请求构造/错误/超时/配置引导
```

结构：

```
lib/index.js      # Cordis 插件：注册 vision_describe 工具 + settings namespace（vision）
lib/describe.js   # 纯函数：图片→data URL、OpenAI 兼容 /chat/completions 调用（可单测）
cordis.patch.yml  # bundle patch：host plane 工具行（全局 agent 可见）
tests/            # node:test 单元测试
install.sh        # 一键安装（正确挂载方式，见上）
```

## License

[MIT](./LICENSE) — 依赖（@deepseek-ai/dsh-tools、@deepseek-ai/schemastery）均为 MIT。
