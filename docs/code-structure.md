# tmux-dev 代码结构记录

## 1. 仓库定位

这个仓库本身是一个薄封装，真正的主体代码在 `tmux/` 目录下。根目录只有少量辅助文件：

- `build.sh`: 仓库级构建入口，最终编译出 `tmux/tmux`
- `CHANGES-feature.md`: 当前仓库层面的变更记录
- `AGENTS.md`: 本仓库的协作与修改约束
- `tmux/`: 上游 tmux 源码主树

因此，阅读和后续改动都应该默认以 `tmux/` 为主。

## 2. 总体架构

从运行时看，tmux 可以拆成 4 层：

1. 启动与进程层
   - `tmux.c` 负责程序入口、参数处理、环境准备、socket 路径与默认 shell 解析。
   - `client.c` 负责客户端启动、连接 server、必要时拉起 server。
   - `server.c` 负责 server 生命周期、全局对象初始化、事件循环。
   - `proc.c` 负责 client/server 间的内部消息传递与 signal/event 封装。

2. 命令与配置层
   - `cmd-parse.y` 把命令行和配置文件语句解析成命令列表。
   - `cmd.c`、`cmd-queue.c` 组织命令对象、执行队列和执行上下文。
   - `cmd-*.c` 是具体命令实现，目前大约 65 个文件。
   - `cfg.c` 负责加载 `tmux.conf`，并把配置文件内容送入命令队列执行。

3. 会话/窗口/Pane 模型层
   - `session.c` 管理 session 生命周期、session group、当前窗口切换。
   - `window.c` 管理 window、pane、winlink 以及全局 pane/window 集合。
   - `layout.c`、`layout-set.c`、`layout-custom.c` 管理 pane 布局树。
   - `spawn.c` 负责把“命令结果”落实成新 window/pane 和其子进程。

4. 终端渲染与交互层
   - `input.c` 解析 pane 内程序输出的 ANSI/VT 序列。
   - `screen.c`、`grid.c`、`screen-write.c` 维护虚拟屏幕与写入操作。
   - `screen-redraw.c` 负责把 window/pane/status 重新绘制到 client。
   - `tty.c`、`tty-term.c`、`tty-keys.c`、`tty-features.c` 负责与真实终端交互。
   - `server-client.c` 连接 client 状态、输入事件、redraw、overlay、title/path 更新。

可以把它理解为：

`tmux.c -> client.c/server.c -> cmd/cfg -> session/window/layout/spawn -> screen/input/tty`

## 3. 目录结构

### 3.1 根目录

- `build.sh`
- `CHANGES-feature.md`
- `AGENTS.md`
- `docs/`
- `tmux/`

### 3.2 `tmux/` 主目录

这里是绝大多数 C 源码，按照文件名前缀基本能看出职责：

- `cmd-*.c`: 单条命令实现，比如新建 session、切 pane、设置 option 等
- `server*.c`: server 主循环、client 管理、server 侧辅助逻辑
- `window*.c`: window/pane 相关模式与 UI
- `screen*.c`: 屏幕抽象、写屏、重绘
- `tty*.c`: 终端能力、按键、输出
- `layout*.c`: pane 布局树与布局算法
- `osdep-*.c`: 平台差异层
- 其他关键单文件模块：
  - `tmux.c`
  - `client.c`
  - `proc.c`
  - `cfg.c`
  - `options.c`
  - `format.c`
  - `spawn.c`
  - `input.c`
  - `session.c`
  - `window.c`

### 3.3 其他子目录

- `tmux/compat/`: 兼容性 shim，例如平台补丁和第三方接口适配
- `tmux/regress/`: shell 回归测试，当前约 38 个文件
- `tmux/fuzz/`: fuzz 相关入口和输入
- `tmux/tools/`: 辅助脚本、颜色/终端测试素材
- `tmux/logo/`: logo 和图标资源
- `tmux/presentations/`: 演讲材料
- `tmux/.github/`: CI/workflow 配置

## 4. 核心模块拆解

### 4.1 程序入口与进程模型

#### `tmux.c`

职责：

- 解析 CLI 参数
- 确定 socket 路径
- 解析 shell、配置文件路径、环境变量
- 决定当前进程是作为 client 还是配合 server 启动

这里定义了不少全局对象入口，例如：

- `global_options`
- `global_s_options`
- `global_w_options`
- `global_environ`

也就是说，tmux 里“全局默认配置”在入口阶段就会建立好。

#### `client.c`

职责：

- 连接现有 tmux server
- 如需要则通过锁文件机制安全地启动新 server
- 把命令、shell 请求、终端信息发送给 server
- 维护 client 退出原因和退出消息

可把它视为“用户当前这次 tmux 命令调用”的前台代理。

#### `server.c`

职责：

- 初始化 server 运行时全局集合：`windows`、`sessions`、`clients`
- 创建监听 socket
- 初始化 key binding、ACL、tidy 定时器
- 启动事件循环 `proc_loop`

`server.c` 是 server 生命周期总控，不承载所有业务细节，很多细节会下沉到 `server-client.c`、`server-fn.c`、`server-acl.c`。

#### `proc.c`

职责：

- 封装 `tmuxproc` 和 `tmuxpeer`
- 处理 client/server 间基于 `imsg` 的消息收发
- 统一 signal 与 libevent 事件循环

它是 tmux 内部“进程间消息总线”的核心抽象。

### 4.2 命令系统

#### `cmd-parse.y`

职责：

- 解析命令行、配置文件和 if/elif/else 条件块
- 支持 `#{...}` 格式展开参与解析
- 产出命令列表，供后续命令队列执行

tmux 的命令并不是“读一行直接执行”，而是先变成结构化命令树/列表。

#### `cmd-queue.c`

职责：

- 管理命令队列 `cmdq_list`
- 维护命令执行时的上下文 `cmdq_state`
- 保存 source/target/current 等查找状态
- 在回调、等待、异步命令之间串联执行

这是命令系统真正的调度层。

#### `cmd-*.c`

特点：

- 单文件单命令或单类命令
- 命令粒度清晰，便于按功能定位
- 和 `options.c`、`format.c`、`session.c`、`window.c` 等频繁交互

阅读策略：

- 查某个用户命令时，优先看对应的 `cmd-*.c`
- 查命令如何被解析和串联时，看 `cmd-parse.y` + `cmd-queue.c`

### 4.3 配置与模板系统

#### `cfg.c`

职责：

- 读取配置文件
- 调用 parser 解析
- 把结果插入全局命令队列
- 在启动时阻塞初始 client，确保配置先加载完成

这解释了为什么 tmux 配置本质上也是命令语言，而不是单独的一套配置语法。

#### `options.c` 与 `options-table.c`

职责：

- 管理 option 的层级继承
- 使用红黑树存储 option
- 区分 string/number/flag/choice/command/array 等类型

层级关系大致是：

- global options
- session options
- window options
- 更局部对象继承父级

#### `format.c`

职责：

- 维护格式树 `format_tree`
- 展开 `#{key}` 风格模板
- 支持 modifier、递归展开、以及某些动态 job

tmux 很多“可配置展示文本”都依赖这个模块，例如状态栏、窗口名称、控制模式输出。

### 4.4 会话、窗口、Pane 数据模型

#### `session.c`

职责：

- session 的创建、查找、销毁、引用计数
- session group 同步
- 当前 window 和访问历史管理

关键点：

- session 放在全局 RB tree 中
- session 持有自己的 `windows` 树和 `lastw` 栈

#### `window.c`

职责：

- window 与 pane 的生命周期
- `winlink` 作为 session 和 window 的关联层
- pane 的全局索引和引用关系

关键理解：

- `window` 是全局对象，可被多个 session 通过 `winlink` 引用
- `pane` 是 window 的子单元，持有 pty、屏幕和输入输出状态
- `winlink` 是“某个 session 里第几个窗口”的本地视图

这是 tmux 模型里最值得先吃透的部分。

#### `layout.c`

职责：

- 用树结构描述 pane 布局
- 非叶子节点表示水平/垂直容器
- 叶子节点映射到具体 `window_pane`

理解这层后，再看 split、resize、select-layout 等命令会清晰很多。

#### `spawn.c`

职责：

- 依据命令上下文生成 window/pane
- 解析 cwd、PATH、shell、history-limit、termios 等运行参数
- 为 pane 启动实际子进程

也就是说，命令系统最终通过 `spawn.c` 把抽象操作落地成真实终端进程。

### 4.5 屏幕、输入和输出

#### `input.c`

职责：

- 解析 pane 子进程输出的 ANSI/VT 转义序列
- 更新 `screen_write_ctx`
- 处理 OSC、CSI、DCS、UTF-8 等

这是“程序输出 -> tmux 内部屏幕状态”的入口。

#### `screen.c` / `grid.c` / `screen-write.c`

职责：

- `grid.c`: 底层字符网格和历史缓冲
- `screen.c`: 虚拟屏幕对象、标题、模式、selection、alternate screen
- `screen-write.c`: 面向写操作的高层 API

这层是 tmux 的“虚拟终端画布”。

#### `screen-redraw.c`

职责：

- 将当前 session/window/pane/status 的状态重新渲染到 client
- 处理 pane border、status line、可见区域等

这是“内部屏幕状态 -> 客户端重绘”的核心。

#### `tty.c` / `tty-term.c` / `tty-keys.c` / `tty-features.c`

职责：

- 探测真实终端能力
- 处理客户端键盘输入
- 把重绘结果编码成终端可理解的转义序列
- 控制流量与阻塞，避免慢终端拖垮 server

这里是 tmux 和真实终端设备之间的适配层。

#### `server-client.c`

职责：

- 管理 attached client 的行为
- 处理按键、mouse、overlay、标题/路径、重绘标记
- 连接 session/window 状态变化与 tty 输出

如果要追“用户按下一个键后发生了什么”，通常会走到这里。

### 4.6 UI 辅助模块

- `status.c`: 状态栏与命令提示历史
- `menu.c`: 菜单 UI
- `popup.c`: popup UI
- `mode-tree.c`: 树状模式基础设施
- `window-copy.c`: copy mode
- `window-tree.c`: 树式窗口选择 UI
- `window-clock.c`, `window-buffer.c`, `window-client.c`, `window-customize.c`: 特定 window mode

这些文件更多是“交互模式”和“界面特性”的实现。

### 4.7 平台与兼容层

- `osdep-*.c`: 当前大约 12 个平台文件，对应 Linux/macOS/OpenBSD/FreeBSD 等
- `compat/`: 平台缺失接口与兼容实现

这里解决的是“tmux 核心逻辑尽量平台无关，差异集中收口”的问题。

## 5. 关键执行链路

### 5.1 启动并执行命令

1. `tmux.c` 解析参数，准备 socket、shell、配置路径
2. `client.c` 连接 server；若 server 不存在则触发 `server_start`
3. `server.c` 初始化全局状态并进入事件循环
4. `cfg.c` 加载配置文件，把配置内容转成命令队列
5. 用户命令经 `cmd-parse.y` 解析，进入 `cmd-queue.c`
6. 具体 `cmd-*.c` 执行，对 session/window/pane/options 做修改
7. 如需新 pane/window，则进入 `spawn.c`
8. 状态变更触发 `server-client.c` / `screen-redraw.c` / `tty.c` 完成刷新

### 5.2 Pane 内程序输出到屏幕

1. pane 子进程向 pty 输出字节流
2. `input.c` 解析 ANSI/VT 序列
3. `screen-write.c` / `screen.c` 更新 pane 的虚拟屏幕
4. server 标记相关 client 需要 redraw
5. `screen-redraw.c` 计算需要刷新的 pane/status/border
6. `tty.c` 把结果编码并写回用户终端

### 5.3 用户按键进入 Pane

1. 用户在 attached client 终端输入按键
2. `tty.c` / `tty-keys.c` 读取并解码按键
3. `server-client.c` 结合 key table、模式和上下文决定行为
4. 若是 tmux 命令，进入 `cmd-queue.c`
5. 若是发往 pane，则通过 `input-keys.c` 编码后写入 pane 的 pty

### 5.4 核心数据结构关系图

#### 运行时对象关系

```text
global sessions (RB tree)
    |
    +-- session
          |
          +-- windows (RB tree of winlink)
          |     |
          |     +-- winlink
          |           |
          |           +-- points to window
          |
          +-- curw / lastw
          +-- options
          +-- environ
          +-- cwd

global windows (RB tree)
    |
    +-- window
          |
          +-- panes (TAILQ)
          |     |
          |     +-- window_pane
          |           |
          |           +-- pty fd
          |           +-- screen
          |           +-- input parser state
          |           +-- layout_cell
          |
          +-- active pane
          +-- layout root
          +-- options
```

#### `session / winlink / window / pane` 的语义分工

- `session`: 用户视角的工作区，决定“当前在哪个窗口、有哪些窗口引用”
- `winlink`: session 内的本地窗口槽位，负责 index 和 window 的关联
- `window`: 可被多个 session 共享的 pane 容器
- `window_pane`: 真正连接 pty、screen、子进程的执行单元

一个重要结论是：窗口索引属于 `winlink`，不属于 `window` 本身。

#### layout 树关系

```text
window
  |
  +-- layout_root
        |
        +-- LAYOUT_LEFTRIGHT / LAYOUT_TOPBOTTOM
        |      |
        |      +-- child layout_cell
        |
        +-- LAYOUT_WINDOWPANE
               |
               +-- window_pane
```

因此 split/resize 的本质不是直接操作 pane 列表，而是先改 layout tree，再让 pane 尺寸与偏移重新对齐。

### 5.5 命令系统关系图

```text
CLI / tmux.conf
    |
    v
cmd-parse.y
    |
    v
cmd_list
    |
    v
cmd-queue.c
    |
    +-- cmdq_state
    |     |
    |     +-- current target
    |     +-- key event
    |     +-- extra formats
    |
    +-- cmd-*.c
           |
           +-- session/window/options/layout
           +-- spawn.c
           +-- server-fn.c (redraw/status helpers)
```

这里最关键的是 `cmdq_state`。tmux 不是简单“执行一条命令”，而是在一个携带 target、事件、格式上下文的状态里连续执行命令链。

### 5.6 输入输出双向链路图

#### 程序输出方向

```text
pane child process
    -> pty output
    -> input.c
    -> screen-write.c / screen.c / grid.c
    -> server marks redraw
    -> screen-redraw.c
    -> tty.c
    -> user terminal
```

#### 用户输入方向

```text
user terminal
    -> tty.c / tty-keys.c
    -> server-client.c
    -> key-bindings.c
       |- tmux command -> cmd-queue.c -> cmd-*.c
       `- pane input   -> input-keys.c -> pty write
```

这两个方向共同构成 tmux 的“中间层终端”角色。

## 6. 阅读源码的推荐顺序

如果第一次接触这个仓库，建议按下面顺序读：

1. `tmux/README`
2. `tmux/Makefile.am`
3. `tmux/tmux.c`
4. `tmux/client.c`
5. `tmux/server.c`
6. `tmux/session.c`
7. `tmux/window.c`
8. `tmux/layout.c`
9. `tmux/spawn.c`
10. `tmux/cmd-parse.y`
11. `tmux/cmd-queue.c`
12. `tmux/input.c`
13. `tmux/screen.c`
14. `tmux/screen-redraw.c`
15. `tmux/tty.c`
16. 再按需进入具体 `cmd-*.c` 或 UI mode 文件

这样读的好处是先建立“主链路”，再补具体功能，不容易陷入单个命令文件的细节。

## 7. 按场景的源码入口索引

### 7.1 想查“命令是怎么生效的”

建议入口：

1. `tmux/cmd-parse.y`
2. `tmux/cmd-queue.c`
3. 对应的 `tmux/cmd-*.c`
4. 若命令涉及创建 pane/window，再看 `tmux/spawn.c`
5. 若命令执行后需要刷新界面，再看 `tmux/server-fn.c`

### 7.2 想查“为什么这个键会触发这个动作”

建议入口：

1. `tmux/tty-keys.c`: 从终端字节流识别按键
2. `tmux/server-client.c`: client 上下文中的按键调度
3. `tmux/key-bindings.c`: key table 和默认绑定
4. `tmux/cmd-send-keys.c`: send-keys 命令本身
5. `tmux/input-keys.c`: 把按键重新编码发给 pane 程序

### 7.3 想查“Pane 里的输出为什么显示成这样”

建议入口：

1. `tmux/input.c`
2. `tmux/screen-write.c`
3. `tmux/screen.c`
4. `tmux/grid.c`
5. `tmux/screen-redraw.c`
6. `tmux/tty.c`

### 7.4 想查“split / resize / select-layout 为什么这样工作”

建议入口：

1. `tmux/layout.c`
2. `tmux/layout-set.c`
3. `tmux/layout-custom.c`
4. `tmux/window.c`
5. `tmux/cmd-split-window.c`
6. `tmux/cmd-resize-pane.c`
7. `tmux/cmd-select-layout.c`

### 7.5 想查“配置项是怎么继承和生效的”

建议入口：

1. `tmux/cfg.c`
2. `tmux/options.c`
3. `tmux/options-table.c`
4. `tmux/format.c`
5. 具体消费该 option 的模块，例如 `status.c`、`window.c`、`server-client.c`

### 7.6 想查“server 为什么 redraw / status / lock 了某个 client”

建议入口：

1. `tmux/server-fn.c`
2. `tmux/server-client.c`
3. `tmux/server.c`
4. `tmux/status.c`

## 8. 后续定位问题时的查找建议

- 命令行为异常：先查 `cmd-*.c`、`cmd-parse.y`、`cmd-queue.c`
- session/window 选择错误：查 `session.c`、`window.c`、`server-fn.c`
- split/resize/layout 问题：查 `layout.c`、`layout-set.c`、`cmd-split-window.c`、`cmd-resize-pane.c`
- 状态栏/格式字符串问题：查 `status.c`、`format.c`、`options.c`
- 按键问题：查 `tty-keys.c`、`key-bindings.c`、`input-keys.c`、`server-client.c`
- 屏幕渲染异常：查 `input.c`、`screen.c`、`screen-redraw.c`、`tty.c`
- 平台差异问题：查 `osdep-*.c` 与 `compat/`
- 配置文件加载问题：查 `cfg.c`、`cmd-source-file.c`

## 9. 结构总结

tmux 代码虽然文件很多，但组织方式其实比较稳定：

- 用 `client/server + event loop` 驱动运行时
- 用 `cmd parser + command queue` 驱动命令系统
- 用 `session/window/pane/layout` 表达核心数据模型
- 用 `input/screen/tty` 把 pty 字节流和真实终端渲染连接起来

真正需要优先建立的心智模型只有两个：

1. `session -> winlink -> window -> pane`
2. `命令解析 -> 命令队列 -> 数据模型变更 -> redraw/tty 输出`

理解这两个主轴后，后续无论是改命令、查渲染问题还是加功能，定位成本都会低很多。
