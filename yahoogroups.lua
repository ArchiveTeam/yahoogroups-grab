dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local ids = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://login%.yahoo%.com/")
      or string.match(url, "^https?://b%.scorecardresearch%.com/")
      or string.match(url, "^https?://xa%.yimg%.com/$")
      or string.match(url, "^https?://dmros%.ysm%.yahoo%.com/")
      or string.match(url, "&at=email:")
      or string.match(url, "^https?://[^/]*groups.yahoo.com/api/v1/groups/[^/]+/topics")
      or string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/conversations/topics")
      or string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/invitations/$")
      or string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/management/$") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if string.match(url, "^https?://[^/]*consent%.yahoo%.com") then
    io.stdout:write("Got a consent problem.\n")
    io.stdout:flush()
  end

  if string.match(url, "^https?://s%.yimg%.com/[^/]+/defcovers/")
      or string.match(url, "^https?://xa%.yimg%.com") then
    return true
  end

  if string.match(url, "^https?://[^/%.]*%.?groups%.yahoo%.com") then
    for s in string.gmatch(url, "([a-z0-9A-Z_%-]+)") do
      if ids[s] then
        return true
      end
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}\"]")
      or string.match(url, "^https?://b%.scorecardresearch%.com/")
      or string.match(url, "^https?://xa%.yimg%.com/$")
      or string.match(url, "^https?://dmros%.ysm%.yahoo%.com/") then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
      and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
      return true
    end
    return false
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      return check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      return check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      return check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      return check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      return check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      return check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      return check(string.match(url, "^(https?://[^/]+)")..newurl)
    elseif string.match(newurl, "^%./") then
      return checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      return check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      return check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  local function extract_group(url_)
    local match = string.match(url_, "^https?://[^/]*groups%.yahoo%.com/api/v1/groups/([^/]+)")
    if match == nil then
      match = string.match(url_, "^https?://[^/]*groups%.yahoo%.com/neo/groups/([^/]+)")
    end
    if match == nil then
      sys.stdout:write("Got bad group URL " .. url_ .. ".")
      sys.stdout:flush()
      abortgrab = true
    end
    return match
  end

  local function extract_timezone(html_)
    local match = string.match(html_, 'GROUPS%.TIMEZONE%s*=%s*"([^"]+)";')
    if match == nil then
      io.stdout:write("Could not extract timezone data.\n")
      io.stdout:flush()
      abortgrab = true
    end
    return string.gsub(match, "/", "%%2B")
  end

  if allowed(url, nil) and status_code == 200
      and not string.match(url, "^https?://[^/]*yimg%.com/") then
    html = read_file(file)
    if string.match(html, ">Please wait while we are redirecting!<") then
      local match = string.match(html, 'window.location.href%s+=%s+"(https?://[a-z]+%.groups%.yahoo%.com/[^"]+)"')
      if match ~= nil and extract_group(url) == extract_group(match) then
        check(match)
      end
      return urls
    end

    local domain = string.match(url, "^https?://([^/]+)/")

    if string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[a-zA-Z0-9_%-]+/info$") then
      local timezone = extract_timezone(html)
      local group = extract_group(url)
      check("https://" .. domain .. "/neo/groups/" .. group)
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/history?chrome=raw&tz=" .. timezone)
      --check("https://" .. domain .. "/api/v1/groups/" .. group .. "/")

    elseif string.match(url, "^https?://[^/]*groups%.yahoo%.com/api/v1/groups/[^/]+/history"--[[%?chrome=raw"]]) then
      local data = load_json_file(html)
      local group = extract_group(url)
      local read = false
      for _, capability in ipairs(data["ygPerms"]["resourceCapabilityList"]) do
        if capability["resourceType"] == "MESSAGE"
            or capability["resourceType"] == "POST" then
          for _, resource_type in ipairs(capability["capabilities"]) do
            if resource_type["name"] == "READ" then
              read = true
            end
          end
        end
      end
      if read then
        for _, year_data in ipairs(data["ygData"]["messageHistory"]) do
          for _, month_data in ipairs(year_data["months"]) do
            check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/messages?messageStartId=" .. month_data["firstMessageId"] .. "&archiveSearch=true")
          end
        end
      end

    elseif string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/conversations/messages%?messageStartId=[0-9]+") then
      local post_id = string.match(url, "messageStartId=([0-9]+)")
      local group = extract_group(url)
      local timezone = extract_timezone(html)
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/messages?start=" .. post_id .. "&count=15&sortOrder=asc&direction=1&chrome=raw&tz=" .. timezone)

    elseif string.match(url, "^https?://[^/]*groups.yahoo.com/api/v1/groups/[^/]+/messages%?"--[[start=[0-9]+&count=[0-9]+&sortOrder=asc&direction=1&chrome=raw"]])
        and string.match(url, "&direction=%-?[0-9]+") then
      local direction = string.match(url, "&direction=(%-?[0-9]+)")
      local group = extract_group(url)
      local data = load_json_file(html)
      local nextpage = data["ygData"]["nextPageStart"]
      if direction == "-1" then
        nextpage = data["ygData"]["prevPageStart"]
      end
      local count = 0
      for _, message_data in ipairs(data["ygData"]["messages"]) do
        if check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/messages/" .. message_data["messageId"]) then
          count = count + 1
        end
      end
      if count > 0 then
        check(string.gsub(url, "start=[0-9]+", "start=" .. nextpage))
      end

    --[[elseif string.match(url, "^https?://[^/]*groups.yahoo.com/api/v1/groups/[^/]+/topics%?"--startTopicId=1009&count=15&sortOrder=desc&direction=-1&chrome=raw&tz=America%2FLos_Angeles&ts=1574111731499")
        and string.match(url, "&direction=%-?[0-9]+") then
      local group = extract_group(url)
      local data = load_json_file(html)
      local nextpage = tonumber(string.match(url, "startTopicId=([0-9]+)"))
      local count = 0
      for _, message_data in ipairs(data["ygData"]["topicRecords"]) do
        if check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/messages/" .. message_data["recordId"]) then
          count = count + 1
        end
        if message_data["recordId"] < nextpage then
          nextpage = message_data["recordId"]
        end
      end
      if count > 0 then
        check(string.gsub(url, "startTopicId=[0-9]+", "startTopicId=" .. nextpage))
      end]]

    elseif string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/conversations/messages$") then
      local timezone = extract_timezone(html)
      local group = extract_group(url)
      local nextpage = string.match(html, 'data%-prev%-page%-start="([0-9]+)"')
      check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/messages?noImage=true&noNavbar=true&chrome=raw&tz=" .. timezone)
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/messages?start=" .. nextpage .. "&count=15&sortOrder=desc&direction=-1&chrome=raw&tz=" .. timezone)

    elseif string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/conversations/messages/[0-9]+$") then
      local post_id = string.match(url, "([0-9]+)$")
      local timezone = extract_timezone(html)
      local group = extract_group(url)
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/messages/" .. post_id .. "/raw?chrome=raw&tz=" .. timezone)
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/messages/" .. post_id .. "/")
      --check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/messages/" .. post_id .. "?noImage=true&noNavbar=true&_gb=GB0&chrome=raw&tz=" .. timezone)
      --check("https://groups.yahoo.com/api/v1/groups/" .. group .. "/messages/" .. post_id .. "/raw")
      --[[local match = string.match(html, "(%?advance=true&am=CONTAINS&at=email:[^@]+@&dm=IS_ANY&fs=false&count=)[0-9]+")
      if match then
        check("https://" .. domain .. "/api/v1/search/groups/" .. group .. "/messages" .. match .. "3&stripSubjectprefix=true&mm=DOES_NOT_CONTAINS&mo=IS_EQUAL_TO&mid=" .. post_id .. "&chrome=raw&tz=" .. timezone)
      end]]

    --[[elseif string.match(url, "^https?://groups%.yahoo%.com/neo/groups/[^/]+/conversations/messages%?noImage=true&noNavbar=true&chrome=raw") then
      local timezone = extract_timezone(html)
      local group = extract_group(url)
      check()]]

    --[[elseif string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/conversations/topics/[0-9]+$") then
      local topic_id = string.match(url, "([0-9]+)$")
      local timezone = extract_timezone(html)
      local group = extract_group(url)
      --check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/topics/" .. topic_id .. "?noImage=true&noNavbar=true&_gb=GB0&chrome=raw&tz=" .. timezone)
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/topics/" .. topic_id)
      --check("https://" .. domain .. "/api/v1/groups/" .. group .. "/polls/?topicId=" .. topic_id .. "&chrome=raw&tz=" .. timezone)
      --check("https://" .. domain .. "/api/v1/groups/" .. group .. "/topics/" .. topic_id .. "/attachments?start=0&count=3&includeTotalCount=true&chrome=raw&tz=" .. timezone)
    elseif string.match(url, "^https?://[^/]*groups%.yahoo%.com/neo/groups/[^/]+/conversations/topics$") then
      local timezone = extract_timezone(html)
      local group = extract_group(url)
      local nextpage = string.match(html, 'data%-prev%-page%-start="([0-9]+)"')
      check("https://" .. domain .. "/api/v1/groups/" .. group .. "/topics?startTopicId=" .. nextpage .. "&count=15&sortOrder=desc&direction=-1&chrome=raw&tz=" .. timezone)
      check("https://" .. domain .. "/neo/groups/" .. group .. "/conversations/topics?noImage=true&noNavbar=true&_gb=GB0&chrome=raw&tz=" .. timezone)]]
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if string.match(url["url"], "^https?://[^/]*consent%.yahoo%.com") then
    io.stdout:write("Got a consent problem.\n")
    io.stdout:flush()
  end

  if downloaded[url["url"]] then
    io.stdout:write("Already got URL. Likely incomplete response.\n")
    io.stdout:flush()
    return wget.actions.EXIT
  end

  if string.match(url["url"], "^https?://groups%.yahoo%.com/neo/groups/[a-zA-Z0-9_%-]+/info$") then
    ids[string.match(url["url"], "([a-z0-9A-Z_%-]+)/info$")] = true
  end

  if status_code >= 300 and status_code <= 399 then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
