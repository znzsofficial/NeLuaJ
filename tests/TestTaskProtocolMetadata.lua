local assets=ASSETS or 'app/src/main/assets/'
local protocol=assert(loadfile(assets..'mods/agent/OpenAIProtocol.lua'))()
local mode=false
local cfg={getModel=function() return 'test-model' end,getApiUrl=function() return 'https://example.test/v1' end,
  getMaxTokens=function() return 1000 end,getTemperature=function() return 0.5 end,useResponses=function() return mode end}
local metadata={scope={projectPath='/private/project',conversationId='private-conversation',generation=1}}
local history={
  {role='user',content='go',task_info=metadata},
  {role='assistant',content='',legacy_function_call=true,tool_calls={{id='legacy',type='function',['function']={name='read_file',arguments='{}'}}}},
  {role='tool',tool_call_id='legacy',content='legacy text',task_info=metadata,file_result={transactionId='secret-id'},tool_ok=true},
  {role='assistant',content='',tool_calls={{id='modern',type='function',['function']={name='read_file',arguments='{}'}}}},
  {role='tool',tool_call_id='modern',content='modern text',task_info=metadata,file_result={transactionId='secret-id'},tool_ok=false,
    child_file_results={{transactionId='private-child'}},continuation_state='stopped'},
}
local allowed={role=true,content=true,tool_call_id=true,name=true,tool_calls=true,function_call=true,reasoning_content=true}
local body=protocol.buildRequest(cfg,history,{builtinTools={}})
assert(body.messages[2].function_call.name=='read_file')
assert(body.messages[3].role=='function' and body.messages[3].content=='legacy text')
assert(body.messages[5].tool_call_id=='modern' and body.messages[5].content=='modern text')
for _,msg in ipairs(body.messages) do
  for key in pairs(msg) do assert(allowed[key],'internal field leaked: '..key) end
end
assert(history[5].task_info==metadata and history[5].child_file_results[1].transactionId=='private-child')
mode=true
body=protocol.buildRequest(cfg,history,{builtinTools={}})
for _,item in ipairs(body.input) do
  assert(item.task_info==nil and item.file_result==nil and item.tool_ok==nil and item.child_file_results==nil)
end
print('ALL-PASS task metadata stays local across mixed legacy, modern and Responses history')
