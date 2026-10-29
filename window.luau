--!strict
-- 窗口端：注册命令调色板动作、项目选择器与鼠标交互样式
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

local function find_bd(): string?
   local cands = {
      "/opt/homebrew/bin/bd",
      "/opt/homebrew/bin/beads",
      "/usr/local/bin/bd",
      (tern.getenv("HOME") or "") .. "/.local/bin/bd",
      "bd",
   }
   for _, p in cands do
      if #p > 0 and (string.sub(p, 1, 1) ~= "/" or tern.fs.exists(p)) then return p end
   end
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

local function get_known_projects(): { { label: string, detail: string, path: string } }
   local raw = tern.kv.get("known_projects")
   if type(raw) == "table" then
      local res = {}
      for _, it in raw do
         if type(it) == "table" and it.path then
            table.insert(res, {
               label = it.label or it.n or "project",
               detail = it.detail or it.path or "",
               path = it.path or it.p or "",
            })
         end
      end
      if #res > 0 then return res end
   end
   local home = tern.getenv("HOME") or ""
   return {
      { label = t("当前工作目录", "Current Working Directory"), detail = tern.getenv("PWD") or home, path = tern.getenv("PWD") or home },
   }
end

tern.command({
   id = "open",
   title = t("Beads: 开启当前焦点项目的看板", "Beads: Open Task Board for Focused Project"),
   icon = "sparkle",
   run = function(cx)
      local focused_id = cx.session:focused()
      local cwd: string? = nil
      if focused_id then
         local p = cx.session:pane(focused_id)
         if p and p.cwd and #p.cwd > 0 then cwd = p.cwd end
      end
      cx:new_block("beads.main", if cwd then { cwd } else nil, "beside")
      cx:toast("info", "Beads", t("已开启 Beads 看板", "Opened Beads Task Board"))
   end,
})

tern.command({
   id = "pick_project",
   title = t("Beads: 选择项目打开看板", "Beads: Select Project to Open Board"),
   icon = "sparkle",
   run = function(cx)
      local items = get_known_projects()
      local p = cx:pick({
         items = items,
         placeholder = t("选择要打开 Beads 任务看板的目标项目...", "Select a project to open Beads board..."),
         icon = "sparkle",
      })
      p:next(function(item, err, ncx)
         if err or not item then return end
         local active_cx = ncx or cx
         active_cx:new_block("beads.main", { item.path }, "beside")
         active_cx:toast("info", "Beads", t("已开启 " .. item.label .. " 任务看板", "Opened task board for " .. item.label))
      end)
   end,
})

tern.command({
   id = "open_tab",
   title = t("Beads: 在独立标签页中开启看板", "Beads: Open Task Board in New Tab"),
   icon = "sparkle",
   run = function(cx)
      local focused_id = cx.session:focused()
      local cwd: string? = nil
      if focused_id then
         local p = cx.session:pane(focused_id)
         if p and p.cwd and #p.cwd > 0 then cwd = p.cwd end
      end
      cx:new_block("beads.main", if cwd then { cwd } else nil, "tab")
   end,
})

tern.command({
   id = "create",
   title = t("Beads: 快速新建任务", "Beads: Quick Create Task"),
   icon = "sparkle",
   run = function(cx)
      local p = cx:prompt({
         placeholder = t("输入任务标题...", "Enter task title..."),
         icon = "sparkle",
         action = t("创建任务", "Create Task"),
      })
      p:next(function(title, err, ncx)
         if err or not title or #title == 0 then return end
         local active_cx = ncx or cx
         local bin = find_bd()
         if not bin then
            active_cx:toast("error", "Beads", t("未找到 bd 命令", "bd command not found"))
            return
         end

         tern.process.run({ bin, "create", title, "--type", "task", "--priority", "2" }, { env = get_env() }, function(res)
            if res.status == 0 then
               active_cx:toast("success", "Beads", t("已创建任务: ", "Created task: ") .. title)
            else
               active_cx:toast("error", "Beads", t("创建失败: ", "Failed to create: ") .. res.stderr)
            end
         end)
      end)
   end,
})

tern.css("beads-style", [[
   [data-surface="plugin.beads.main"].sf-main {
      padding: 10px 14px;
   }
   [data-surface="plugin.beads.main"].sf-dock {
      padding: 6px 12px;
      border-top: 1px solid var(--border, rgba(255, 255, 255, 0.08));
   }
   [data-surface="plugin.beads.main"].sf-layer {
      padding: 24px 32px;
   }
   button.sf-click {
      background: transparent;
      border: none;
      padding: 0;
      margin: 0;
      cursor: pointer;
      color: inherit;
      font: inherit;
      display: inline-flex;
      align-items: center;
   }
   button.sf-click:hover {
      opacity: 0.8;
   }
   button.sf-btn {
      background: var(--surface, rgba(255, 255, 255, 0.08));
      border: 1px solid var(--border, rgba(255, 255, 255, 0.15));
      border-radius: 4px;
      padding: 3px 10px;
      cursor: pointer;
      color: inherit;
      font: inherit;
      margin-right: 6px;
   }
   button.sf-btn:hover {
      background: var(--surface-hover, rgba(255, 255, 255, 0.15));
      border-color: var(--accent, #61afef);
   }
]])
