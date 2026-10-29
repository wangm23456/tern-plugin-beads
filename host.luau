--!strict
-- Beads 任务看板面板：任务列表、依赖管理、状态流转、多工作区与鼠标输入

type Issue = {
   id: string, title: string, description: string?, status: string, priority: number,
   issue_type: string, owner: string?, assignee: string?, created_at: string?,
   created_by: string?, updated_at: string?, dependency_count: number?, dependent_count: number?,
}

type FilterMode = "ready" | "in_progress" | "blocked" | "closed" | "all"

type State = {
   loading: boolean, filter: FilterMode, selected: number, issues: { Issue },
   ready_ids: { [string]: boolean }, error: string?, msg: string?, show_help: boolean,
   show_ws: boolean, input_mode: string?, input_text: string, cwd: string,
}

local ui = tern.ui

local function is_zh(): boolean
   local cfg_lang = tern.getenv("TERN_LANG") or tern.getenv("PLUGIN_LANG")
   if cfg_lang and #cfg_lang > 0 then
      return string.find(string.lower(cfg_lang), "zh") ~= nil
   end
   local home = tern.getenv("HOME") or ""
   if #home > 0 then
      local s_paths = {
         home .. "/Library/Application Support/Tern/settings.json",
         home .. "/.config/tern/settings.json",
      }
      for _, sp in s_paths do
         if tern.fs.exists(sp) then
            local ok, raw = pcall(function() return tern.fs.read(sp, 32768) end)
            if ok and raw and #raw > 0 then
               local pok, data = pcall(function() return tern.json.decode(raw) end)
               if pok and type(data) == "table" and type(data.language) == "string" then
                  return string.find(string.lower(data.language), "zh") ~= nil
               end
            end
         end
      end
   end
   local env_lang = (tern.getenv("LANG") or "") .. (tern.getenv("LC_ALL") or "") .. (tern.getenv("LC_MESSAGES") or "")
   if #env_lang > 0 and (string.find(string.lower(env_lang), "zh") ~= nil or string.find(string.lower(env_lang), "cn") ~= nil) then
      return true
   end
   if #home > 0 then
      local pref_path = home .. "/Library/Preferences/.GlobalPreferences.plist"
      if tern.fs.exists(pref_path) then
         local ok, bytes = pcall(function() return tern.fs.read(pref_path, 16384) end)
         if ok and bytes and (string.find(bytes, "zh-Hans") or string.find(bytes, "zh-Hant") or string.find(bytes, "zh_CN")) then
            return true
         end
      end
   end
   return false
end

local function t(zh: string, en: string): string
   return if is_zh() then zh else en
end

local function get_known_projects(): { { n: string, p: string } }
   local raw = tern.kv.get("known_projects")
   if type(raw) == "table" then
      local res = {}
      for _, it in raw do
         if type(it) == "table" and it.p then
            table.insert(res, { n = it.n or it.label or "project", p = it.p or it.path })
         end
      end
      if #res > 0 then return res end
   end
   local home = tern.getenv("HOME") or ""
   return {
      { n = "current", p = (tern.getenv("PWD") or home) },
   }
end

local function find_bd(): string?
   local cands = { "/opt/homebrew/bin/bd", "/opt/homebrew/bin/beads", "/usr/local/bin/bd", (tern.getenv("HOME") or "") .. "/.local/bin/bd", "bd" }
   for _, p in cands do if #p > 0 and (string.sub(p, 1, 1) ~= "/" or tern.fs.exists(p)) then return p end end
   return nil
end

local function get_env(): { [string]: string }
   local home = tern.getenv("HOME") or ""
   local path = tern.getenv("PATH") or ""
   return {
      PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" .. home .. "/.local/bin:" .. path,
      HOME = home,
   }
end

local function get_proj_name(cwd: string): string
   local kp_list = get_known_projects()
   for _, kp in kp_list do if string.find(cwd, kp.p, 1, true) then return kp.n end end
   return string.match(string.gsub(cwd, "/+$", ""), "([^/]+)$") or cwd
end

local function prio_info(p: number): (string, string)
   if p == 0 then return t("🔴 P0 紧急", "🔴 P0 Critical"), "error strong"
   elseif p == 1 then return t("🟠 P1 高优", "🟠 P1 High"), "warning strong"
   elseif p == 2 then return t("🟡 P2 普通", "🟡 P2 Medium"), "accent strong"
   elseif p == 3 then return t("🟢 P3 低优", "🟢 P3 Low"), "info"
   elseif p == 4 then return t("⚪ P4 备忘", "⚪ P4 Backlog"), "muted"
   else return "P" .. p, "muted" end
end

local function type_label(ty: string): string
   if ty == "bug" then return t("🐛 缺陷", "🐛 Bug")
   elseif ty == "feature" then return t("✨ 特性", "✨ Feature")
   elseif ty == "task" then return t("📋 任务", "📋 Task")
   elseif ty == "epic" then return t("🏔 史诗", "🏔 Epic")
   elseif ty == "chore" then return t("🔧 杂务", "🔧 Chore")
   else return "⚙ " .. ty end
end

local function status_view(s: string, is_ready: boolean): (string, string)
   if s == "in_progress" then return t("⏳ 进行中", "⏳ In Progress"), "warning strong"
   elseif s == "closed" then return t("✓ 已完成", "✓ Closed"), "success"
   elseif s == "blocked" then return t("⛔ 已阻塞", "⛔ Blocked"), "error strong"
   elseif s == "open" then
      return (if is_ready then t("⚡ 就绪", "⚡ Ready") else t("⏳ 待前置", "⏳ Pending")), (if is_ready then "accent strong" else "muted")
   else return s, "muted" end
end

local function filter_issues(state: State): { Issue }
   local res: { Issue } = {}
   for _, it in state.issues do
      local r = state.ready_ids[it.id] == true
      if state.filter == "ready" and it.status == "open" and r then table.insert(res, it)
      elseif state.filter == "in_progress" and it.status == "in_progress" then table.insert(res, it)
      elseif state.filter == "blocked" and (it.status == "blocked" or (it.status == "open" and not r)) then table.insert(res, it)
      elseif state.filter == "closed" and it.status == "closed" then table.insert(res, it)
      elseif state.filter == "all" then table.insert(res, it) end
   end
   return res
end

local function count_stats(state: State)
   local c = { ready = 0, in_progress = 0, blocked = 0, closed = 0, total = #state.issues }
   for _, it in state.issues do
      local r = state.ready_ids[it.id] == true
      if it.status == "closed" then c.closed += 1
      elseif it.status == "in_progress" then c.in_progress += 1
      elseif it.status == "blocked" or (it.status == "open" and not r) then c.blocked += 1
      elseif it.status == "open" and r then c.ready += 1 end
   end
   return c
end

local function fetch_data(state: State, cx: BlockCx)
   local bin = find_bd()
   if not bin then state.loading, state.error = false, t("未找到 bd 或 beads 程序", "bd or beads command not found"); cx:render(); return end
   state.loading = true
   local env = get_env()
   tern.process.run({ bin, "list", "--status", "all", "--json" }, { cwd = state.cwd, env = env }, function(res)
      if res.status ~= 0 then
         state.loading, state.error = false, if #res.stderr > 0 then res.stderr else (t("读取失败: ", "Read failed: ") .. res.status)
         cx:render(); return
      end
      local ok, list = pcall(function() return tern.json.decode(res.stdout) end)
      if not ok or type(list) ~= "table" then state.loading, state.error = false, t("解析 JSON 失败", "Failed to parse JSON"); cx:render(); return end
      state.issues = list

      tern.process.run({ bin, "ready", "--json" }, { cwd = state.cwd, env = env }, function(ready_res)
         state.loading = false
         local ready_ids: { [string]: boolean } = {}
         if ready_res.status == 0 then
            local r_ok, r_list = pcall(function() return tern.json.decode(ready_res.stdout) end)
            if r_ok and type(r_list) == "table" then
               for _, it in r_list do if it.id then ready_ids[it.id] = true end end
            end
         end
         state.ready_ids, state.error = ready_ids, nil
         cx:render()
      end)
   end)
end

local function run_bd_cmd(state: State, cx: BlockCx, args: { string }, success_msg: string)
   local bin = find_bd()
   if not bin then state.error = t("未找到 bd 程序", "bd command not found"); cx:render(); return end
   state.loading, state.msg = true, nil
   local cmd = { bin }
   for _, a in args do table.insert(cmd, a) end
   tern.process.run(cmd, { cwd = state.cwd, env = get_env() }, function(res)
      if res.status ~= 0 then
         state.loading, state.error = false, if #res.stderr > 0 then res.stderr else (t("失败: ", "Failed: ") .. res.status)
         cx:render()
      else
         state.msg = success_msg
         fetch_data(state, cx)
      end
   end)
end

local function handle_action(state: State, cx: BlockCx, act: string)
   local filtered = filter_issues(state)
   if act == "ws_toggle" then state.show_ws = not state.show_ws; cx:render()
   elseif string.sub(act, 1, 4) == "tab:" then state.filter, state.selected = string.sub(act, 5) :: FilterMode, 1; cx:render()
   elseif string.sub(act, 1, 3) == "ws:" then
      local kp_list = get_known_projects()
      local n = tonumber(string.sub(act, 4))
      if n and n >= 1 and n <= #kp_list then
         state.cwd, state.show_ws, state.selected = kp_list[n].p, false, 1
         state.msg = t("已切换项目: ", "Switched project: ") .. kp_list[n].n
         fetch_data(state, cx)
      end
   elseif act == "act:claim" and #filtered > 0 and state.selected <= #filtered then
      run_bd_cmd(state, cx, { "update", filtered[state.selected].id, "--claim" }, t("已认领: ", "Claimed: ") .. filtered[state.selected].id)
   elseif act == "act:close" and #filtered > 0 and state.selected <= #filtered then
      run_bd_cmd(state, cx, { "close", filtered[state.selected].id, "--reason", "completed" }, t("已完成: ", "Closed: ") .. filtered[state.selected].id)
   elseif act == "act:reopen" and #filtered > 0 and state.selected <= #filtered then
      run_bd_cmd(state, cx, { "reopen", filtered[state.selected].id }, t("已重开: ", "Reopened: ") .. filtered[state.selected].id)
   elseif act == "act:prio" and #filtered > 0 and state.selected <= #filtered then
      local it = filtered[state.selected]
      local np = (it.priority + 1) % 5
      local p_txt, _ = prio_info(np)
      run_bd_cmd(state, cx, { "priority", it.id, tostring(np) }, t("已调整优先级为 ", "Changed priority to ") .. p_txt .. ": " .. it.id)
   elseif act == "close_modal" then state.show_ws, state.show_help, state.input_mode = false, false, nil; cx:render()
   elseif act == "dock:new" then state.input_mode, state.input_text = "create", ""; cx:render()
   elseif act == "dock:refresh" then fetch_data(state, cx)
   elseif act == "dock:help" then state.show_help = not state.show_help; cx:render()
   elseif act == "dock:prev" then state.selected = math.max(1, state.selected - 1); cx:render()
   elseif act == "dock:next" then state.selected = math.min(#filtered, state.selected + 1); cx:render()
   end
end

local beads_block: BlockDef<State> = {
   init = function(cx, args, saved)
      local init_cwd = if args and args[1] and #args[1] > 0 then args[1]
         elseif saved and saved.cwd and #saved.cwd > 0 then saved.cwd
         else (cx.cwd or ".")
      local state: State = {
         loading = true, filter = if saved and saved.filter then saved.filter else "ready",
         selected = if saved and saved.selected then saved.selected else 1,
         issues = {}, ready_ids = {}, error = nil, msg = nil, show_help = false,
         show_ws = false, input_mode = nil, input_text = "", cwd = init_cwd,
      }
      fetch_data(state, cx)
      return state
   end,

   title = function(state)
      local s = count_stats(state)
      return "Beads · " .. get_proj_name(state.cwd) .. " (" .. s.ready .. " " .. t("待办", "ready") .. ")"
   end,

   view = function(state, _cx)
      local stats = count_stats(state)
      local filtered = filter_issues(state)
      if state.selected > #filtered then state.selected = math.max(1, #filtered) end

      local total, proj = stats.total, get_proj_name(state.cwd)
      local ratio = if total > 0 then stats.closed / total else 0
      local pct = math.floor(ratio * 100)

      -- 1. 顶部项目与指标
      local head_card = ui.card(ui.span("⚡ BEADS " .. t("看板", "BOARD") .. " · " .. proj, "strong accent"), {
         ui.row({
            ui.el("button", { id = "ws_toggle", text = "📁 " .. t("项目: ", "Project: ") .. proj .. " ▾" }),
            ui.badge(t("交付 ", "Done ") .. pct .. "%", if pct == 100 then "success strong" else "strong"),
            ui.badge(t("⚡ 就绪 ", "⚡ Ready ") .. stats.ready, if stats.ready > 0 then "accent" else "muted"),
            ui.badge(t("⏳ 进行 ", "⏳ Active ") .. stats.in_progress, if stats.in_progress > 0 then "warning strong" else "muted"),
            ui.badge(t("⛔ 阻塞 ", "⛔ Blocked ") .. stats.blocked, if stats.blocked > 0 then "error" else "muted"),
            ui.badge(t("✓ 完成 ", "✓ Closed ") .. stats.closed, if stats.closed > 0 then "success" else "muted"),
         }),
         ui.meter(ratio, ui.span(state.cwd .. " (" .. stats.closed .. " / " .. total .. " " .. t("完成", "closed") .. ")", "muted")),
      })

      -- 2. 标签栏（点击切换）
      local tabs = {
         { k = "ready", l = t("就绪", "Ready") .. " (" .. stats.ready .. ")" },
         { k = "in_progress", l = t("进行", "In Progress") .. " (" .. stats.in_progress .. ")" },
         { k = "blocked", l = t("阻塞", "Blocked") .. " (" .. stats.blocked .. ")" },
         { k = "closed", l = t("完成", "Closed") .. " (" .. stats.closed .. ")" },
         { k = "all", l = t("全部", "All") .. " (" .. stats.total .. ")" },
      }
      local tab_nodes: { Node } = {}
      for _, t in tabs do
         local active = state.filter == t.k
         table.insert(tab_nodes, ui.el("button", {
            id = "tab:" .. t.k,
            text = (if active then "● " else "○ ") .. t.l,
         }))
      end

      -- 3. 状态通知
      local notice: Node? = if state.loading then ui.badge(t("⟳ 正在同步 ", "⟳ Syncing ") .. proj .. t(" 数据库...", " database..."), "info")
         elseif state.error then ui.badge("⚠ " .. state.error, "error strong")
         elseif state.msg then ui.badge("✓ " .. state.msg, "success strong")
         else nil

      -- 4. 表格
      local cols: { Col } = {
         { id = "sel", head = " " },
         { id = "prio", head = t("优先级", "Priority") },
         { id = "status", head = t("状态", "Status") },
         { id = "id", head = t("编号", "ID") },
         { id = "type", head = t("类型", "Type") },
         { id = "title", head = t("任务标题", "Title"), grow = 1 },
         { id = "assignee", head = t("经办人", "Assignee") },
      }
      local rows: { { Cell } } = {}
      for idx, it in filtered do
         local is_sel = idx == state.selected
         local is_ready = state.ready_ids[it.id] == true
         local p_txt, p_tone = prio_info(it.priority)
         local s_txt, s_tone = status_view(it.status, is_ready)
         table.insert(rows, {
            ui.span(if is_sel then "▶" else " ", if is_sel then "accent strong" else "muted"),
            ui.span(p_txt, p_tone), ui.span(s_txt, s_tone),
            ui.span(it.id, if is_sel then "accent strong num" else "muted num"),
            ui.span(type_label(it.issue_type)),
            ui.span(it.title, if is_sel then "accent strong" else "default"),
            ui.span(it.assignee or it.owner or "-", if it.assignee then "strong" else "muted"),
         })
      end

      local list_node = if #filtered == 0
         then ui.card(ui.span("📋 " .. t("任务清单", "Task List"), "strong"), { ui.text({ ui.span(t("【" .. proj .. "】当前分类暂无任务。点击下方按钮新建或切换项目。", "No tasks in this category for [" .. proj .. "]. Create one or switch project below."), "muted") }) })
         else ui.table(cols, rows)

      -- 5. 详情与鼠标操作按钮
      local detail_node: Node? = nil
      local cur = if #filtered > 0 and state.selected <= #filtered then filtered[state.selected] else nil
      if cur then
         local is_ready = state.ready_ids[cur.id] == true
         local p_txt, p_tone = prio_info(cur.priority)
         local s_txt, _ = status_view(cur.status, is_ready)

         local action_btns: { Node } = {}
         if cur.status == "open" and is_ready then
            table.insert(action_btns, ui.el("button", { id = "act:claim", text = t("⚡ 认领任务", "⚡ Claim Task") }))
            table.insert(action_btns, ui.el("button", { id = "act:close", text = t("✓ 完成任务", "✓ Close Task") }))
         elseif cur.status == "in_progress" then
            table.insert(action_btns, ui.el("button", { id = "act:close", text = t("✓ 标记完成", "✓ Mark Closed") }))
         elseif cur.status == "closed" then
            table.insert(action_btns, ui.el("button", { id = "act:reopen", text = t("↻ 重新打开", "↻ Reopen Task") }))
         end
         table.insert(action_btns, ui.el("button", { id = "act:prio", text = t("▲ 轮转优先级", "▲ Rotate Priority") }))
         local cards: { Node } = {
            ui.kv({
               { ui.span(t("任务编号", "Task ID")), ui.span(cur.id, "strong accent") },
               { ui.span(t("状态/优先级", "Status/Priority")), ui.span(s_txt .. "  " .. p_txt, p_tone) },
               { ui.span(t("类型/经办人", "Type/Assignee")), ui.span(type_label(cur.issue_type) .. " · " .. (cur.assignee or t("未认领", "Unassigned"))) },
               { ui.span(t("所属项目", "Project")), ui.span(proj .. " (" .. state.cwd .. ")", "muted") },
            }),
            ui.rule(ui.span(t("快捷操作", "Actions"))),
            ui.row(action_btns),
         }
         if cur.description and #cur.description > 0 then
            table.insert(cards, ui.rule(ui.span(t("任务描述", "Description"))))
            table.insert(cards, ui.text({ ui.span(cur.description) }))
         end
         detail_node = ui.card(ui.span("🔍 " .. cur.title, "strong"), cards)
      end

      -- 6. 模态浮层
      local layer_node: Node? = nil
      if state.show_ws then
         local ws_nodes: { Node } = {}
         local kp_list = get_known_projects()
         for i, kp in kp_list do
            local is_cur = string.find(state.cwd, kp.p, 1, true) ~= nil
            local label = (if is_cur then "● " else "○ ") .. i .. "  " .. kp.n .. " — " .. kp.p
            table.insert(ws_nodes, ui.el("button", { id = "ws:" .. i, text = label }))
         end
         table.insert(ws_nodes, ui.el("button", { id = "close_modal", text = t("✕ 关闭弹窗", "✕ Close") }))
         layer_node = ui.card(ui.span("📁 " .. t("切换 Beads 项目仓库 (点击选择)", "Switch Beads Project Workspace (Click to Select)"), "accent strong"), { ui.col(ws_nodes) })
      elseif state.input_mode == "create" then
         layer_node = ui.card(ui.span("✨ " .. t("新建 Beads 任务", "New Beads Task") .. " (" .. proj .. ")", "accent strong"), {
            ui.text({ ui.span(t("键入标题后按 Enter 提交，或点击下方取消。", "Type title and press Enter to submit, or click cancel below.")) }),
            ui.rule(ui.span(t("任务标题", "Task Title"))),
            ui.row({ ui.span("❯ ", "accent strong"), ui.span(state.input_text, "strong"), ui.span("█", "accent") }),
            ui.row({ ui.el("button", { id = "close_modal", text = t("✕ 取消", "✕ Cancel") }) }),
         })
      elseif state.show_help then
         layer_node = ui.card(ui.span("⌨ " .. t("Beads 看板操作与快捷键", "Beads Shortcuts & Help"), "accent strong"), {
            ui.kv({
               { ui.span(t("鼠标点击", "Mouse Click")), ui.span(t("支持点击标签切换视图、点击按钮认领/完成/调级/换项目", "Click tabs to switch views, click buttons to claim/close/rotate/switch")) },
               { ui.span("w / " .. t("项目按钮", "Project button")), ui.span(t("切换项目工作区", "Switch project workspace")) },
               { ui.span("1 - 5 / " .. t("标签按钮", "Tab buttons")), ui.span(t("切换视图: 就绪 / 进行中 / 阻塞 / 完成 / 全部", "Switch tab: Ready / In Progress / Blocked / Closed / All")) },
               { ui.span("j / k " .. t("或", "or") .. " ▲/▼"), ui.span(t("上下移动任务选中项", "Move selection up / down")) },
               { ui.span("c / x / u / p"), ui.span(t("认领 / 完成 / 重开 / 轮转优先级", "Claim / Close / Reopen / Rotate Priority")) },
               { ui.span("n / r"), ui.span(t("新建任务 / 刷新数据", "New task / Refresh data")) },
            }),
            ui.rule(ui.span(t("关闭", "Close"))),
            ui.el("button", { id = "close_modal", text = t("✕ 关闭帮助", "✕ Close Help") }),
         })
      end

      local main_nodes: { Node } = { head_card, ui.row(tab_nodes) }
      if notice then table.insert(main_nodes, notice) end
      table.insert(main_nodes, list_node)
      if detail_node then table.insert(main_nodes, detail_node) end

      return {
         main = ui.col(main_nodes),
         dock = ui.col({
            ui.row({
               ui.el("button", { id = "dock:prev", text = t("▲ 上项", "▲ Prev") }),
               ui.el("button", { id = "dock:next", text = t("▼ 下项", "▼ Next") }),
               ui.el("button", { id = "ws_toggle", text = t("📁 换项目", "📁 Switch") }),
               ui.el("button", { id = "dock:new", text = t("＋ 新建", "＋ New") }),
               ui.el("button", { id = "dock:refresh", text = t("⟳ 刷新", "⟳ Refresh") }),
               ui.el("button", { id = "dock:help", text = t("？ 帮助", "？ Help") }),
            }),
         }),
         layer = layer_node,
      }
   end,

   key = function(state, key, cx)
      if state.show_ws then
         local kp_list = get_known_projects()
         local n = tonumber(key.name)
         if n and n >= 1 and n <= #kp_list then handle_action(state, cx, "ws:" .. n); return true
         elseif key.name == "escape" or key.name == "w" then state.show_ws = false; return true end
         return true
      end
      if state.show_help then
         if key.name == "escape" or key.name == "?" or key.name == "h" or key.name == "enter" or key.name == "space" then
            state.show_help = false; return true
         end
         return true
      end
      if state.input_mode == "create" then
         if key.name == "escape" then state.input_mode, state.input_text = nil, ""; return true
         elseif key.name == "enter" then
            local t = state.input_text
            state.input_mode, state.input_text = nil, ""
            if #t > 0 then run_bd_cmd(state, cx, { "create", t, "--type", "task", "--priority", "2" }, t("已创建: ", "Created: ") .. t) end
            return true
         elseif key.name == "backspace" then
            if #state.input_text > 0 then state.input_text = string.sub(state.input_text, 1, #state.input_text - 1) end
            return true
         elseif key.text and #key.text > 0 and not key.ctrl and not key.meta then
            state.input_text ..= key.text
            return true
         end
         return true
      end

      local filtered = filter_issues(state)
      if key.name == "w" then handle_action(state, cx, "ws_toggle"); return true
      elseif key.name == "1" or key.name == "2" or key.name == "3" or key.name == "4" then
         local m = ({ ["1"] = "ready", ["2"] = "in_progress", ["3"] = "blocked", ["4"] = "closed" })[key.name]
         handle_action(state, cx, "tab:" .. m); return true
      elseif key.name == "5" or key.name == "0" then handle_action(state, cx, "tab:all"); return true
      elseif key.name == "j" or key.name == "down" then handle_action(state, cx, "dock:next"); return true
      elseif key.name == "k" or key.name == "up" then handle_action(state, cx, "dock:prev"); return true
      elseif key.name == "g" or key.name == "home" then state.selected = 1; return true
      elseif key.name == "G" or key.name == "end" then state.selected = math.max(1, #filtered); return true
      elseif key.name == "r" then handle_action(state, cx, "dock:refresh"); return true
      elseif key.name == "n" then handle_action(state, cx, "dock:new"); return true
      elseif key.name == "?" or key.name == "h" then handle_action(state, cx, "dock:help"); return true
      elseif key.name == "c" then handle_action(state, cx, "act:claim"); return true
      elseif key.name == "x" or key.name == "d" then handle_action(state, cx, "act:close"); return true
      elseif key.name == "u" then handle_action(state, cx, "act:reopen"); return true
      elseif key.name == "p" then handle_action(state, cx, "act:prio"); return true
      end
      return false
   end,

   event = function(state, ev: UiEvent, cx: BlockCx)
      if ev.ev == "action" then
         local act = ev.act or ev.id or ""
         if #act > 0 then handle_action(state, cx, act); return end
      end
      if (ev.ev == "select" or ev.ev == "activate") and ev.row then
         local filtered = filter_issues(state)
         state.selected = math.min(math.max(1, ev.row), #filtered)
         cx:render()
      end
   end,

   save = function(state)
      return { filter = state.filter, selected = state.selected, cwd = state.cwd }
   end,
}

tern.block.define("main", beads_block)
