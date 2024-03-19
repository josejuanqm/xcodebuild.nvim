---@mod xcodebuild.project.manager Project Manager
---@tag xcodebuild.project-manager
---@brief [[
---This module is responsible for managing the project files and groups.
---
---It uses the `xcodeproj` tool to update the Xcode project file.
---
---In general, all functions that take paths as arguments, they don't
---change files on disk. These without arguments are interactive and
---perform changes on disk too.
---
---All actions send notifications to the user.
---
---See: https://github.com/CocoaPods/Xcodeproj
---@brief ]]

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local appdata = require("xcodebuild.project.appdata")
local projectConfig = require("xcodebuild.project.config")
local notifications = require("xcodebuild.broadcasting.notifications")
local pickers = require("xcodebuild.ui.pickers")

local M = {}

local helper = "ruby '" .. appdata.tool_path(appdata.PROJECT_HELPER_TOOL) .. "'"

---Checks if the `xcodeproj` tool is installed.
---If not, sends an error notification.
---@return boolean
local function validate_xcodeproj_tool()
  if vim.fn.executable("xcodeproj") == 0 then
    notifications.send_error("Xcodeproj tool not found. Please run `gem install xcodeproj` to install it.")
    return false
  end

  return true
end

---Runs the `xcodeproj` tool with the provided action and parameters.
---
---If the output starts with "WARN:", it sends a warning notification and
---returns an empty table.
---
---In case of error, it sends an error notification and returns an empty table.
---@param action string
---@param params string[]|nil
---@return string[]
local function run(action, params)
  local allParams = ""
  local project = projectConfig.settings.xcodeproj
  params = params or {}
  table.insert(params, 1, project)

  for _, param in ipairs(params) do
    allParams = allParams .. " '" .. param .. "'"
  end

  local errorFile = "/tmp/xcodebuild_nvimtree"
  local output = util.shell(helper .. " " .. action .. allParams .. " 2> " .. errorFile)

  if output[#output] == "" then
    table.remove(output, #output)
  end

  if output[1] and vim.startswith(output[1], "WARN:") then
    vim.notify(table.concat(output, "\n"):sub(7), vim.log.levels.WARN)
    return {}
  end

  local stderr_file = io.open(errorFile, "r")
  if stderr_file then
    if stderr_file:read("*all") ~= "" then
      vim.notify(
        "Could not update Xcode project file.\n"
          .. "To see more details please check /tmp/xcodebuild_nvimtree.\n"
          .. "If you are trying to add files to SPM packages, you may want to filter them out in the config using: integrations.nvim_tree.should_update_project.\n"
          .. "If the error is unexpected, please open an issue on GitHub.",
        vim.log.levels.ERROR
      )
      return {}
    end
  end

  return output
end

---Runs the `list_targets` action and returns the output.
---@return string[]
local function run_list_targets()
  return run("list_targets")
end

---Gets targets and shows the picker to select them.
---
---If there is only one target and {opts.autoselect} is `true`, it calls the {callback}
---without showing the picker.
---
---Returns `true` if the picker has been shown, otherwise `false`.
---@param title string
---@param opts {autoselect: boolean}|nil
---@param callback fun(target: string[])|nil
---@return boolean
local function run_select_targets(title, opts, callback)
  local targets = run_list_targets()

  if opts and opts.autoselect and #targets == 1 then
    util.call(callback, targets)
    return false
  end

  pickers.show(title, targets, callback, { close_on_select = true, multiselect = true })
  return true
end

---Adds file to the selected targets.
---The group from {filepath} must exist in the project.
---@param filepath string
---@param targets string[]
local function run_add_file_to_targets(filepath, targets)
  local targetsJoined = table.concat(targets, ",")
  run("add_file", { targetsJoined, filepath })
end

---Updates the file targets.
---@param filepath string
---@param targets string[]
local function run_update_file_targets(filepath, targets)
  local targetsJoined = table.concat(targets, ",")
  run("update_file_targets", { targetsJoined, filepath })
end

---Deletes the file from the project.
---@param filepath string
local function run_delete_file(filepath)
  run("delete_file", { filepath })
end

---Renames the file.
---@param oldPath string
---@param newPath string
local function run_rename_file(oldPath, newPath)
  run("rename_file", { oldPath, newPath })
end

---Moves the file.
---@param oldPath string
---@param newPath string
local function run_move_file(oldPath, newPath)
  run("move_file", { oldPath, newPath })
end

---Adds a new group.
---@param path string
local function run_add_group(path)
  run("add_group", { path })
end

---Renames the group.
---@param oldPath string
---@param newPath string
local function run_rename_group(oldPath, newPath)
  run("rename_group", { oldPath, newPath })
end

---Moves the group.
---@param oldPath string
---@param newPath string
local function run_move_group(oldPath, newPath)
  run("move_group", { oldPath, newPath })
end

---Deletes the group.
---@param path string
local function run_delete_group(path)
  run("delete_group", { path })
end

---Deletes the current buffer and loads {path}.
---@param path string
local function replace_file(path)
  vim.cmd("bd! | e " .. path)
end

---Creates a new file in the project and on disk.
---It asks for the file name and creates it in the current directory.
---It also asks the user to select targets.
function M.create_new_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local path = vim.fn.expand("%:p:h")
  local filename = vim.fn.input("File name: ", "")
  local extension = filename:match("%.([%w_]+)$") or ""

  if vim.trim(filename) == "" then
    return
  end

  if extension == "" then
    filename = filename .. ".swift"
  end

  local fullPath = path .. "/" .. filename
  vim.fn.system("touch '" .. fullPath .. "'")
  vim.cmd("e " .. fullPath)

  M.add_current_file()
end

---Adds the file to the selected targets.
---The group from {filepath} must exist in the project.
---@param filepath string
---@param targets string[]
function M.add_file_to_targets(filepath, targets)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_add_file_to_targets(filepath, targets)
end

---Returns all project targets.
---@return string[]|nil
function M.get_project_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  return run_list_targets()
end

---Adds the file to project.
---Asks the user to select the targets.
---All groups from {filepath} will be added to the project if they are not already there.
---
---Calls the {callback} after the file has been added to the targets or the user has canceled the action.
---@param filepath string
---@param callback function|nil
function M.add_file(filepath, callback)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filename = util.get_filename(filepath)

  local autocmd = vim.api.nvim_create_autocmd("BufWinLeave", {
    group = vim.api.nvim_create_augroup("project-manager-add-file", { clear = true }),
    pattern = "*",
    once = true,
    callback = function()
      if vim.bo.filetype == "TelescopePrompt" then
        util.call(callback)
      end
    end,
  })

  local pickerShown = run_select_targets(
    "Select Target(s) for " .. filename,
    { autoselect = true },
    function(targets)
      local dir = vim.fs.dirname(filepath)
      if not dir then
        notifications.send_error("Could not get the directory of: " .. filepath)
        return
      end

      M.add_group(dir, { silent = true })
      run_add_file_to_targets(filepath, targets)
      notifications.send("File has been added to targets")
    end
  )

  -- The target has been selected automatically, so we can remove the autocmd.
  if not pickerShown then
    vim.api.nvim_del_autocmd(autocmd)
    util.call(callback)
  end
end

---Adds the current file to the selected targets.
---Ask the user to select the targets.
---All groups will be added to the project if they are not already there.
function M.add_current_file()
  M.add_file(vim.fn.expand("%:p"))
end

---Moves the file to the new path in the project.
---The group from {newFilePath} must exist in the project.
---@param oldFilePath string
---@param newFilePath string
function M.move_file(oldFilePath, newFilePath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_move_file(oldFilePath, newFilePath)

  if vim.fs.basename(oldFilePath) == vim.fs.basename(newFilePath) then
    notifications.send("File has been moved")
  else
    notifications.send("File has been renamed")
  end
end

---Renames the file in the project.
---@param oldFilePath string
---@param newFilePath string
function M.rename_file(oldFilePath, newFilePath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_rename_file(oldFilePath, newFilePath)
  notifications.send("File has been renamed")
end

---Renames the current file in the project and on disk.
---Asks the user for the new file name.
function M.rename_current_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local oldFilePath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")
  local newFilename = vim.fn.input("New file name: ", filename)

  if vim.trim(newFilename) == "" or newFilename == filename then
    return
  end

  local newFilePath = vim.fn.expand("%:p:h") .. "/" .. newFilename
  run_rename_file(oldFilePath, newFilePath)
  vim.fn.rename(oldFilePath, newFilePath)
  replace_file(newFilePath)
  notifications.send("File has been renamed")
end

---Deletes the file from the project.
---@param filepath string
function M.delete_file(filepath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_delete_file(filepath)
  notifications.send("File has been deleted")
end

---Deletes the current file from the project and disk.
---Asks the user for confirmation.
function M.delete_current_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")
  local input = vim.fn.input("Delete " .. filepath .. "? (y/n) ", "")
  vim.cmd("echom ''")

  if input == "y" then
    run_delete_file(filepath)
    vim.fn.delete(filepath)
    vim.cmd("bd!")
    notifications.send("File has been deleted")
  end
end

---Creates a new group in the project and on disk.
---Asks the user for the group name.
function M.create_new_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local path = vim.fn.expand("%:p:h")
  local groupName = vim.fn.input("Group name: ", "")

  if vim.trim(groupName) == "" then
    return
  end

  local groupPath = path .. "/" .. groupName
  vim.fn.system("mkdir -p '" .. groupPath .. "'")

  run_add_group(groupPath)
  notifications.send("Group has been added")
end

---Adds the group to the project.
---@param path string
---@param opts table|nil
---
---* silent (boolean): If true, it doesn't send a notification.
function M.add_group(path, opts)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  opts = opts or {}
  run_add_group(path)

  if not opts.silent then
    notifications.send("Group has been added")
  end
end

---Adds the current group to the project.
function M.add_current_group()
  M.add_group(vim.fn.expand("%:p:h"))
end

---Renames the group in the project.
---@param oldGroupPath string
---@param newGroupPath string
function M.rename_group(oldGroupPath, newGroupPath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_rename_group(oldGroupPath, newGroupPath)
  notifications.send("Group has been renamed")
end

---Renames the current group in the project and on disk.
---Asks the user for the new group name.
function M.rename_current_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local oldGroupPath = vim.fn.expand("%:p:h")
  local oldGroupName = vim.fn.expand("%:p:h:t")

  local newGroupName = vim.fn.input("New group name: ", oldGroupName)
  if vim.trim(newGroupName) == "" or oldGroupName == newGroupName then
    return
  end

  local newGroupPath = vim.fn.expand("%:p:h:h") .. "/" .. newGroupName
  run_rename_group(oldGroupPath, newGroupPath)
  vim.fn.rename(oldGroupPath, newGroupPath)

  local newFilepath = newGroupPath .. "/" .. vim.fn.expand("%:t")
  replace_file(newFilepath)

  notifications.send("Group has been renamed")
end

---Moves or renames the group in the project.
---If the parent path is different, it moves the group.
---If the parent path is the same, it renames the group.
---The parent group of {newGroupPath} must exist.
---@param oldGroupPath string
---@param newGroupPath string
function M.move_or_rename_group(oldGroupPath, newGroupPath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local oldDir = vim.fn.fnamemodify(oldGroupPath, ":h")
  local newDir = vim.fn.fnamemodify(newGroupPath, ":h")

  if oldDir ~= newDir then
    run_move_group(oldGroupPath, newGroupPath)
    notifications.send("Group has been moved")
  else
    run_rename_group(oldGroupPath, newGroupPath)
    notifications.send("Group has been renamed")
  end
end

---Deletes the group from the project.
function M.delete_group(groupPath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_delete_group(groupPath)
  notifications.send("Group has been deleted")
end

---Deletes the current group from the project and disk.
---Asks the user for confirmation.
function M.delete_current_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local groupPath = vim.fn.expand("%:p:h")
  local input = vim.fn.input("Delete " .. groupPath .. " with all files? (y/n) ", "")
  vim.cmd("echom ''")

  if input == "y" then
    run_delete_group(groupPath)
    vim.fn.system("rm -rf '" .. groupPath .. "'")
    vim.cmd("bd!")
    notifications.send("Group has been deleted")
  end
end

---Updates the file targets in the project.
---Asks the user to select the targets.
function M.update_current_file_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")
  local filename = util.get_filename(filepath)

  run_select_targets("Select Target(s) for " .. filename, nil, function(targets)
    run_update_file_targets(filepath, targets)
    notifications.send("File targets have been updated")
  end)
end

---Shows the targets for the current file.
function M.show_current_file_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")
  local targets = run("list_targets_for_file", { filepath })
  pickers.show("Target Membership of " .. filename, targets)
end

---Shows the action picker with all available actions.
function M.show_action_picker()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local titles = {
    "Create new file",
    "Add current file",
    "Rename current file",
    "Delete current file",
    "Create new group",
    "Add current group",
    "Rename current group",
    "Delete current group",
    "Update current file target(s)",
    "Show current file target(s)",
  }

  local actions = {
    M.create_new_file,
    M.add_current_file,
    M.rename_current_file,
    M.delete_current_file,
    M.create_new_group,
    M.add_current_group,
    M.rename_current_group,
    M.delete_current_group,
    M.update_current_file_targets,
    M.show_current_file_targets,
  }

  pickers.show("Project Manager", titles, function(_, index)
    actions[index]()
  end, { close_on_select = true })
end

return M
