# tmux 功能改造说明

**分支**：`feature/floating-term-session-switcher`  
**基于**：tmux 3.5a (`549c35b0`)  
**提交**：`1abc6728`（初始实现）、`a895023a`（bug 修复）

---

## 功能一：Alt+F 持久浮动终端

### 用法

| 操作 | 效果 |
|------|------|
| `Alt+F`（无 prefix） | 首次：在屏幕中央弹出浮动终端 |
| `Alt+F`（已弹出） | 收起 popup，shell 进程和 scrollback **保持存活** |
| `Alt+F`（已收起） | 重新弹出，完全恢复上次状态 |
| popup 内 shell 正常退出 | popup 自动关闭；下次 `Alt+F` 重新创建 |

- 窗口尺寸：客户端宽的 **80%** × 高的 **75%**，居中显示
- 标题栏显示 `Floating Terminal`
- 每个 tmux client 独立持有一个浮动终端实例，随 session 生命周期结束自动释放

---

### 改动文件

#### `cmd-toggle-floating-term.c`（新增，100 行）

实现 `toggle-floating-term` 命令（别名 `tft`）。

```
命令名：toggle-floating-term
别  名：tft
标  志：CMD_CLIENT_CANFAIL
参  数：无
```

执行逻辑（`cmd_toggle_floating_term_exec`）：

```
c->floating_popup == NULL
    → popup_display()  创建新 popup，80%×75% 居中
    → 保存 c->floating_popup = c->overlay_data

c->floating_popup_visible == 1（当前可见）
    → server_client_hide_overlay()  隐藏，不销毁
    → floating_popup_visible = 0

c->floating_popup_visible == 0（已隐藏）
    → popup_reattach()  重新装回 overlay
    → floating_popup_visible = 1
```

shell 退出时触发 `cmd_toggle_floating_term_close_cb`，将 `c->floating_popup` 置 NULL。

---

#### `popup.c`（+42 行）

**1. 修复 `popup_job_complete_cb`**

原代码在 shell 退出时无条件调用 `server_client_clear_overlay`，但若此时 popup 已被隐藏（`overlay_draw == NULL`），该调用是空操作，popup_data 永远无法释放。

```c
// 改前
server_client_clear_overlay(pd->c);

// 改后
if (pd->c->overlay_draw != NULL)
    server_client_clear_overlay(pd->c);
else
    popup_free_cb(pd->c, pd);   // popup 隐藏时直接释放
```

**2. 新增 `popup_reattach()`**

将一个已隐藏的 `popup_data` 重新安装为 client 的活跃 overlay，无需重建 job 或 screen。

```c
void popup_reattach(struct popup_data *pd, struct client *c)
{
    server_client_unref(pd->c);   // 释放对旧 client 的引用
    pd->c = c;
    pd->c->references++;          // 持有对新 client 的引用
    server_client_set_overlay(c, 0, popup_check_cb, popup_mode_cb,
        popup_draw_cb, popup_key_cb, popup_free_cb, popup_resize_cb, pd);
}
```

**3. 新增 `popup_close_floating()`**

修复引用计数泄漏：`popup_display()` 会对 `pd->c->references++`，对应的 `--` 由 `popup_free_cb` 负责。若 popup 处于隐藏状态时 client 断开，`server_client_clear_overlay` 不会被触发，client 的引用计数永远无法归零，导致 client 结构体和 popup_data（含 job、screen、scrollback）全部泄漏。

```c
/*
 * Free a floating popup that has been hidden (not attached to any overlay).
 * Called when the owning client is disconnecting to avoid a reference count
 * leak: popup_display() bumps pd->c->references and popup_free_cb() owns the
 * corresponding unref.  Without this call the client would never reach
 * references == 0 and would leak.
 */
void popup_close_floating(struct client *c)
{
    struct popup_data *pd = c->floating_popup;
    if (pd == NULL)
        return;
    c->floating_popup = NULL;
    c->floating_popup_visible = 0;
    popup_free_cb(c, pd);
}
```

---

#### `server-client.c`（+32 行）

**1. 新增 `server_client_hide_overlay()`**

与 `server_client_clear_overlay()` 的区别：不调用 `overlay_free` 回调，不销毁 overlay data，仅清除 client 上的回调指针并解冻 TTY。用于 toggle-floating-term 的"收起"操作。

```c
void server_client_hide_overlay(struct client *c)
{
    if (c->overlay_draw == NULL)
        return;
    evtimer_del(&c->overlay_timer);
    c->overlay_check = NULL;
    c->overlay_mode  = NULL;
    c->overlay_draw  = NULL;
    c->overlay_key   = NULL;
    c->overlay_free  = NULL;
    c->overlay_data  = NULL;
    c->tty.flags &= ~(TTY_FREEZE|TTY_NOCURSOR);
    server_redraw_client(c);
}
```

**2. 在 `server_client_lost()` 中调用 `popup_close_floating()`**

```c
// server_client_lost() 内，server_client_clear_overlay 之后立即执行：
server_client_clear_overlay(c);
popup_close_floating(c);        // ← 新增，清理隐藏中的浮动 popup
status_prompt_clear(c);
```

---

#### `tmux.h`

```c
// struct client 新增两个字段：
struct popup_data   *floating_popup;        // 当前 client 的浮动 popup 实例
int                  floating_popup_visible; // 1=可见 0=隐藏

// 新增前向声明：
struct popup_data;

// 新增函数原型：
void  server_client_hide_overlay(struct client *);
void  popup_reattach(struct popup_data *, struct client *);
void  popup_close_floating(struct client *);
```

---

#### `Makefile.am`

```makefile
# dist_tmux_SOURCES 列表中按字母顺序插入：
cmd-toggle-floating-term.c \
```

#### `key-bindings.c`

```c
// key_bindings_init() 默认绑定中新增：
"bind -N 'Toggle floating terminal' -n M-f { toggle-floating-term }",
```

---

## 功能二：Alt+S 会话切换器（支持模糊搜索）

### 用法

按 `Alt+S`（无 prefix）打开全屏会话列表（`choose-tree -Zs`）：

| 按键 | 效果 |
|------|------|
| `↑` / `↓` | 移动光标 |
| `Enter` | attach 到选中 session |
| `d` | kill 选中 session |
| `/` 后输入字符 | **模糊搜索**过滤会话名（见下） |
| `n` / `N` | 跳转到下一个 / 上一个匹配项 |
| `q` / `Esc` | 退出 |

---

### 改动文件

#### `key-bindings.c`

```c
// key_bindings_init() 默认绑定中新增：
"bind -N 'Choose a session from a list' -n M-s { choose-tree -Zs }",
```

`-Z` 使 choose-tree 进入时自动 zoom 当前 pane（全屏）；`-s` 只展示 session 层级，不展开 window/pane。

---

#### `mode-tree.c`（+16 行）

**模糊搜索算法 `mode_tree_fuzzy_match()`**

原实现使用 `strstr` 做子串匹配（区分大小写，要求连续匹配）。改为**大小写不敏感的子序列匹配**：needle 的所有字符必须在 haystack 中按序出现，但不要求连续——与 fzf、vim `/` 等工具的核心逻辑一致。

```c
static int
mode_tree_fuzzy_match(const char *haystack, const char *needle)
{
    while (*haystack != '\0') {
        if (tolower((u_char)*haystack) == tolower((u_char)*needle)) {
            needle++;
            if (*needle == '\0')
                return (1);
        }
        haystack++;
    }
    return (0);
}
```

替换位置：`mode_tree_search_backward()` 和 `mode_tree_search_forward()` 中各一处：

```c
// 改前
if (strstr(mti->name, mtd->search) != NULL)

// 改后
if (mode_tree_fuzzy_match(mti->name, mtd->search))
```

**效果范围**：此改动影响所有使用 `mode-tree` 的 `choose-*` 命令：
- `choose-tree`（会话/窗口/pane）
- `choose-buffer`（paste buffer）
- `choose-client`（客户端列表）

---

## 架构图：浮动终端状态机

```
                  ┌─────────────────────────────────────┐
                  │          client 生命周期             │
                  │                                     │
  Alt+F           │  [无 popup]                         │
─────────────────►│      │ popup_display()              │
                  │      ▼                              │
                  │  [VISIBLE]  ◄──────────────┐        │
                  │      │ Alt+F               │Alt+F   │
                  │      │ hide_overlay()      │reattach│
                  │      ▼                    │        │
                  │  [HIDDEN]  ────────────────┘        │
                  │      │                              │
                  │      │ shell 退出                   │
                  │      │ popup_free_cb()              │
                  │      ▼                              │
                  │  [无 popup]                         │
                  │                                     │
                  │  client 断开 → popup_close_floating │
                  │  → popup_free_cb() → 引用计数归零   │
                  └─────────────────────────────────────┘
```

---

## Bug 修复（`a895023a`）

### 问题一：popup 内按 Alt+F 无法收起

**根本原因**：popup 处于活跃状态时所有按键由 `popup_key_cb` 处理，不经过 root key table，因此 tmux 的 `toggle-floating-term` 命令不会被触发——字符直接透传给 shell。

**修复**：在 `popup_data` struct 中增加 `toggle_key` 字段；`popup_key_cb` 在转发按键给 shell 之前，先判断是否匹配 `toggle_key`，若匹配则直接调用 `server_client_hide_overlay()`。

- `popup.c`：新增 `toggle_key key_code` 字段；`popup_key_cb` 中拦截；新增 `popup_set_toggle_key()` accessor
- `tmux.h`：声明 `popup_set_toggle_key`
- `cmd-toggle-floating-term.c`：popup 创建后调用 `popup_set_toggle_key(c->floating_popup, 'f' | KEYC_META)`

---

### 问题二：choose-tree 模糊搜索无效

**根本原因**：`mode_tree_fuzzy_match()`（`mode-tree.c`）只在 `searchcb == NULL` 时被调用，但 `choose-tree` 通过 `window_tree_search()` 注册了自定义 `searchcb`，内部直接用 `strstr` 做精确子串匹配，导致 `mode-tree.c` 中的模糊匹配逻辑完全被绕过。

**修复**：在 `window-tree.c` 中添加 `window_tree_fuzzy_match()` 静态函数（大小写不敏感子序列匹配），替换 `window_tree_search()` 中三处 `strstr` 调用（session name、window name、pane cmd）。

- `window-tree.c`：新增 `window_tree_fuzzy_match()`；替换三处 `strstr`

---

## 文件变更汇总

| 文件 | 类型 | 净增行数 | 说明 |
|------|------|----------|------|
| `cmd-toggle-floating-term.c` | 新增/修改 | +101 | toggle-floating-term 命令；调用 popup_set_toggle_key |
| `popup.c` | 修改 | +54 | popup_reattach / popup_close_floating / toggle_key 拦截 / popup_set_toggle_key |
| `server-client.c` | 修改 | +32 | server_client_hide_overlay / popup_close_floating 调用 |
| `tmux.h` | 修改 | +11 | 新字段、前向声明、函数原型 |
| `mode-tree.c` | 修改 | +16 | 模糊搜索函数，替换 strstr（mode-tree 层） |
| `window-tree.c` | 修改 | +19 | window_tree_fuzzy_match + 替换三处 strstr（choose-tree 实际生效） |
| `key-bindings.c` | 修改 | +2 | M-f 和 M-s 默认绑定 |
| `Makefile.am` | 修改 | +1 | 新增源文件 |
| `cmd.c` | 修改 | +2 | 注册新命令入口 |
