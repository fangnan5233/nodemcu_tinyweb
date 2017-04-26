local tinyweb = require "tinyweb"

--url:http://192.168.4.1/gpio?pin=1&val=0
--return:status=success
tinyweb.handle("/gpio",function(req,res)
	local pin = req.getParam("pin")
	local val = req.getParam("val")
	if( pin ~= nil) and (val ~= nil) then
		print("pin: "..pin .." , val: " ..val)
		gpio.mode(pin, gpio.OUTPUT)
		gpio.write(pin, val)
		res.setAttribute("status","success")
	end
	return res
end)

--url:http://192.168.4.1/helloworld?name=hello
--return: ...<h1>hello</h1>...
tinyweb.handle("/helloworld",function(req,res)
  local name = req.getParam("name")
  res.setAttribute("name",name)
  res.file = "hello.html" -- ... <h1>{{name}}</h1> ...
  return res
end)

tinyweb.run() --默认80端口，或指定其他端口，tinyweb.run(8080)
