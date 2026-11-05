return {
  id = "list", version = 1,
  titleKey = "template_list_title", descriptionKey = "template_list_description",
  scenario = "A local checklist with add, complete, delete, empty and storage-error states.",
  themeFamilies = { "m3", "dynamic" },
  defaults = { useInternet = false, debugMode = true },
  requiredPermissions = {}, optionalCapabilities = { "internet", "debug", "modules" },
  files = {
    { source = "main.lua.tpl", path = "main.lua" },
    { source = "app/tasks.lua.tpl", path = "app/tasks.lua" },
    { source = "res/layout/main.lua.tpl", path = "res/layout/main.lua" },
    { source = "README.md.tpl", path = "README.md" },
    { source = "templates/shared/screen.lua.tpl", path = "app/screen.lua" },
    { source = "templates/shared/strings.lua.tpl", path = "res/string/init.lua" },
    { source = "templates/shared/strings-en.lua", path = "res/string/en.lua" },
    { source = "templates/shared/strings-zh.lua", path = "res/string/zh.lua" },
    { source = "templates/shared/strings-default.lua", path = "res/string/default.lua" },
  },
}
