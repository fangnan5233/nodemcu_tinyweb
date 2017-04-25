local moduleName = "tinyweb"
local M = {}
_G[moduleName] = M

local handlers = {}

local files = {}

local function urlDecode(str)
    if str == nil then
        return nil
    end
    str = string.gsub(str, '+', ' ')
    str = string.gsub(str, '%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    return str
end

-- 解析request请求参数
local function parseRequest(data)
  local req = {}
  local i,j = string.find(data,"\r\n") -- 第一行
  local n,m = string.find(data,"\r\n\r\n") -- 请求体开始
  local _,_, method,path,protocol= string.find(string.sub(data,1,i),"(%a+)%s*([^%s]+)%s*([^%s]+)")
  --local header = string.sub(data,j+1,n+1)
  local param = nil
  req.parameter = {}
  --req.header = {}
  req.method = method
  req.protocol = protocol
  -- 解析请求路径及请求参数
  if (method == "GET") then
    _,_,req.path,param = string.find(path,"([^%?]+)%??([^%s]*)")
  else
    req.path = path
    _,_,param = string.find(data,"\r\n\r\n([^%s]*)")
  end
  if param ~= nil then --解析请求参数
    for key,value in string.gmatch(param,"([^%?%&]+)=([^%?%&]+)") do
      req.parameter[key] = urlDecode(value)
    end
    param = nil
  end
  -- if header ~= nil then -- 解析请求头
    -- for h in string.gmatch(header,"(.*)\r\n") do
      -- local _,_,k,v = string.find(h,"%s*([^%s]*)%s*:%s*(.*)%s*")
      -- req.header[k] = v
    -- end
    -- header = nil --释放资源
    -- k = nil
    -- v = nil
  -- end
  print("request path : " .. path)
  data = nil
  path = nil
  protocol = nil
  req.getParam = function(name) --获取请求参数
	if(name == nil) then
		return req.parameter
	end
    return req.parameter[name]
  end
  -- req.getHeader = function(name) --获取请求头参数
    -- if(name == nil) then
		-- return req.header
	-- end
	-- return req.header[name]
  -- end
  return req
end



-- tabel to string
local function renderString(subs)
  local content = ""
  for k,v in pairs(subs) do
	content = content.. k .."=" .. v ..","
  end
  if ( #content == 0 ) then
	return nil
  end
  return string.sub(content,1,#content -1)
end

-- 渲染返回数据
local function render(conn,res)
	local body = nil
	local attr = res.attribute
	conn:send("HTTP/1.1 ".. tostring(res.code or 200) .." OK\r\n") -- 响应码
	conn:send("Server:NodeMCU\r\n")
	for k,v in pairs(res.header) do-- 添加头文件 
		conn:send(k .. ": ".. v .."\r\n")
	end
	conn:send("Content-Type: ".. res.type .."; charset=utf-8\r\n") -- 返回类型（html，xml，json）
	conn:send("Transfer-Encoding: chunked\r\n")
	conn:send("Expires: o\r\n") -- 不缓存页面
	conn:send("Connection: close\r\n\r\n")
	if res.file then
        file.open(res.file,"r")
		print("response file : " .. res.file)
		while true do
			local line = file.readline()
			if line == nil then
				break
			end
			if attr then
				for k, v in pairs(attr) do
					line = string.gsub(line, '{{'..k..'}}', v)
				end
			end
			conn:send(("%X\r\n"):format(#line))
			conn:send(line)
			conn:send("\r\n")
		end
		file.close()
	elseif res.body  then
		body = res.body
		if attr then
		  for k, v in pairsattr do
			body = string.gsub(body, '{{'..k..'}}', v)
		  end
		end
		conn:send(("%X\r\n"):format(#body))
		conn:send(body)
		conn:send("\r\n")
	elseif attr then
		body = renderString(attr)
		if body then
			conn:send(("%X\r\n"):format(#body))
			conn:send(body)
			conn:send("\r\n")
		end
	end
	conn:send("0\r\n\r\n")
	res = nil
	body = nil
	attr = nil
end


local function receive(conn,data)
    local s = tmr.now() -- start time
	local req = parseRequest(data)
	local func = handlers[req.path]
	local response = {}
	response.code = 200
	response.type = "text/html"
	response.header = {}
	response.attribute = {} --当file或body不为nil时，做变量置换，否则body为attribute解析之后的结果
	response.body = nil --响应体
	response.file = nil -- 静态文件
	response.setAttribute = function(k,v)
		if(type(k) == "table") then
			for key,val in pairs(k) do
				response.attribute[key] = val
			end
		else
			response.attribute[k] = v
		end
	end
	response.getAttribute = function(k)
		if(k == nil) then
			return response.attribute
		end
		return response.attribute[k]
	end
	response.setHeader = function(k,v)
		response.header[k] = v
	end
	tmr.wdclr()
	if func == nil then -- 没有匹配路径
		response.code = 404
		response.body = "404 Not Found"
	elseif func == "file" then
		response.file = string.sub(req.path,2)
	else
		response = func(req,response)
	end
    req = nil
	if response then
		print("begin response ...")
		render(conn,response)
	end
	response = nil
	local e = tmr.now() -- end time
	print("heap:" .. node.heap() .. "bytes, start_time : ".. s .. "us,end_time:".. e .."us,total_time : " .. (e-s) .."us")
	conn:close()
	conn = nil
	collectgarbage("collect")
end

local function route(conn)
    conn:on('receive', receive)
	-- conn:on("disconnection",function()
		-- collectgarbage("collect")
        -- print("disconnection")
	-- end)
end

function M.handle(path, func)
    handlers[path] = func
end

function M.run( port )
    srv = net.createServer(net.TCP) 
    srv:listen((port or 80), route)
	print("server is running at " .. tostring(port or 80))
	local l = file.list()
	for k,v in pairs (l) do
		if not string.find(k,".lc") then
			handlers["/"..k] = "file"
		end
	end
	l = nil
	for k,v in pairs (handlers) do
		print("path:" .. k)
	end
	collectgarbage("collect")
	tmr.delay(100000)
end

return M
