-- bbc.lua
-- generate students.csv and staff.csv nightly and upload them to Blackboard Connect

require 'table_print'
require 'app_config'

-- algorithm to select PrimaryPhone and AdditionalPhone
phone_prefs = { 'mother_cell', 'father_cell', 'home_phone',
  'mother_work_phone', 'father_work_phone' 
}

-- used with curl command
cookieFile    = 'cookies.txt'
headerFile    = 'headers.txt'
libcurlFile   = 'curl.c'
traceFile     = 'trace.txt'
libcurlLoaded = false

-- bbc-students AutoSend fields
-- tab field delimiter, lf line delimiter, no headers
autosend_student_fields = [[
Student_Number
First_Name
Last_Name
Grade_Level
Gender
HomeRoom_Teacher
SchoolID
Home_Phone
Mother_Work_Phone
Mother_Cell
Father_Work_Phone
Father_Cell
Mother_Email
Father_Email
Home2_Phone
Mother2_Work_Phone
Mother2_Cell
Father2_Work_Phone
Father2_Cell
Mother2_Email
Father2_Email
Enroll_Status
Network_Id
Network_Password
Web_Id
Web_Password
Home_Id
Mother_Staff_Id
Mother_First
Mother
Father_Staff_Id
Father_First
Father
Home2_Id
Mother2_Staff_Id
Mother2_First
Mother2_Last
Father2_Staff_Id
Father2_First
Father2_Last
EntryCode
Lang_Adults_Primary
CA_ELAStatus
]]

-- bbc-staff AutoSend fields
-- tab field delimiter, lf line delimiter, no headers
autosend_staff_fields = [[
Status
Staffstatus
Title
Teachernumber
First_Name
Last_Name
Gender
Schoolid
Home_Phone
Cell
Email_Addr
Email_Personal
Network_Id
Network_Password
Group_Membership
]]

-- headers for staff file
-- 6 groups
staffHeaders   = { 'ReferenceCode', 'FirstName', 'LastName',
  'HomePhone', 'MobilePhone', 'EmailAddress', 'Institution', 
  'Group', 'Group', 'Group', 'Group', 'Group', 'Group' }

-- headers for students file
-- no groups
studentHeaders = { 'ReferenceCode', 'FirstName', 'LastName',
  'Grade', 'Language', 'Gender',
  'HomePhone', 'WorkPhone', 'MobilePhone',
  'HomePhoneAlt', 'WorkPhoneAlt', 'MobilePhoneAlt',
  'PrimaryPhone', 'AdditionalPhone',
  'EmailAddress', 'EmailAddressAlt', 'Institution', 'Group', 'Group', 'Group' }

-- headers to send for file upload
-- copied from WinHttp.WinHttpRequest component defaults
-- Connection: Keep-Alive is the key header!
-- Expect: removes the Expext: 100-continue header
httpHeaders = { 
  'Accept: */*',
  'User-Agent: Mozilla/4.0 (compatible; Win32; WinHttp.WinHttpRequest.5)',
  'Version: HTTP/1.1',
  'Connection: Keep-Alive',
  'Expect:'
}

function string:is_empty()
  return not string.find(self, "%S")
end

function string:split(delimiter)
  local t = { }
  local from  = 1
  local delim_from, delim_to = string.find(self, delimiter, from)
  while delim_from do
    table.insert(t, string.sub(self, from, delim_from - 1))
    from  = delim_to + 1
    delim_from, delim_to = string.find(self, delimiter, from)
  end
  table.insert(t, string.sub(self, from))
  return t
end

function string:splitcsv()
  s = self .. ','     -- ending comma
  local t = {}        -- table to collect fields
  local fieldstart = 1
  repeat
    -- next field is quoted? (start with `"'?)
    if string.find(s, '^"', fieldstart) then
      local a, c
      local i  = fieldstart
      repeat
        -- find closing quote
        a, i, c = string.find(s, '"("?)', i + 1)
      until c ~= '"'    -- quote not followed by quote?
      if not i then error('unmatched "') end
      local f = string.sub(s, fieldstart + 1, i - 1)
      table.insert(t, (string.gsub(f, '""', '"')))
      fieldstart = string.find(s, ',', i) + 1
    else                -- unquoted; find next comma
      local nexti = string.find(s, ',', fieldstart)
      table.insert(t, string.sub(s, fieldstart, nexti - 1))
      fieldstart = nexti + 1
    end
  until fieldstart > string.len(s)
  return t
end

function readcsv(fname, headers, rowfn)
  io.input(fname)
  local lno = headers and 0 or 1
  local columns = { }
  while true do
    local line = io.read()
    if line == nil then break end
    line = string.gsub(line, "\r$", "") -- handle CRLF
    if lno == 0 then
      columns = string.splitcsv(line)
    else
      local row = { }
      if headers then
        local values = string.splitcsv(line)
        for k, v in pairs(columns) do
          row[v] = values[k]
        end
      else
        row = string.splitcsv(line)
      end
      for k, v in pairs(row) do
        if string.is_empty(v) then row[k] = nil end
      end
      rowfn(row)
    end
    lno = lno + 1
  end
end

function get_outreach_phones(phones)
  local primary_phone = nil
  local additional_phone = nil
  for i, key in ipairs(phone_prefs) do
    local test = phones[key]
    if test ~= "" then
      if not primary_phone then
        primary_phone = test
      elseif test ~= primary_phone then
        additional_phone = test
        break
      end
    end
  end
  return (primary_phone or ""), (additional_phone or "")
end

function readtab(fname, headers, rowfn)
  io.input(sourceDir..fname)
  local lno = headers and 0 or 1
  local columns = { }
  while true do
    local line = io.read()
    if verboseFlag > 0 then io.stderr:write("reading " .. fname .. " line " .. lno .. "\n") end
    if line == nil then break end
    line = string.gsub(line, "\r$", "") -- handle CRLF
    if lno == 0 then
      columns = string.split(line, "\t")
    else
      local row = { }
      if headers then
        local values = string.split(line, "\t")
        for k, v in pairs(columns) do
          row[v] = values[k]
        end
      else
        row = string.split(line, "\t")
      end
      for k, v in pairs(row) do
        if string.is_empty(v) then row[k] = nil end
      end
      local status, err = pcall(rowfn, row, fname, lno)
      if verboseFlag > 0 and not status then
        io.stderr:write("row invalid: " .. err .. "\n")
      end
    end
    lno = lno + 1
  end
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writestaffrow(row, fname, lno)
  -- staff fields
  local status = 0 + row[1]
  local title = string.lower(row[3] or "")
  if status == 1 and title ~= 'v-staff' then
    local staffstatus = 0 + row[2]
    local group_membership = string.lower(row[15] or "")
    local groups = { }
    -- staffstatus 0 is "unassigned"
    if staffstatus == 1 then table.insert(groups, "Certificated") end
    if staffstatus == 2 then table.insert(groups, "Classified") end
    -- staffstatus 3 is "lunch staff"
    -- staffstatus 4 is "substitute"
    if string.find(group_membership, 'administrators') then table.insert(groups, "Administrators") end
    if string.find(group_membership, 'trustees') then table.insert(groups, "Board") end
    if #groups > 0 then
      local teachernumber = row[4]
      local first_name = row[5]
      local last_name = row[6]
      local gender = string.upper(row[7] or "")
      
      -- any staff not assigned to school goes into District Office code 102
      local schoolid = row[8] or ""
      if schoolid ~= "103" and schoolid ~= "104" then schoolid = "102" end
      local home_phone = row[9] or ""
      local cell = row[10] or ""
      local email_address = row[11] or ""
    
      -- output a row that matches staffHeaders fields
      -- 6 groups
      io.write(string.format("%q,%q,%q,%q,%q,%q,%q,", teachernumber, 
        first_name, last_name, home_phone, cell, email_address, schoolid))
      io.write(string.format("%q,%q,%q,%q,%q,%q\r\n", 
        groups[1] or "", groups[2] or "", groups[3] or "", 
        groups[4] or "", groups[5] or "", groups[6] or ""))
      if verboseFlag > 0 then io.stderr:write("row written\n") end
    else
      if verboseFlag > 0 then io.stderr:write("no staff groups\n") end
    end
  else
    if verboseFlag > 0 then io.stderr:write("not current staff member\n") end
  end
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writestudentrow(row, fname, lno)
  -- student fields
  local language = 'English'
  local groups = { }
  local student_number = row[1]
  local first_name = row[2]
  local last_name = row[3]
  local grade_level = row[4]
  local gender = string.upper(row[5] or "")
  local teacher = row[6] or ""
  local schoolid = row[7]
  local phones = { 
    home_phone = row[8] or "",
    mother_work_phone = row[9] or "",
    mother_cell = row[10] or "",
    father_work_phone = row[11] or "",
    father_cell = row[12] or "" 
  }
  local primary_phone, additional_phone = get_outreach_phones(phones)
  local mother_email = row[13] or ""
  local father_email = row[14] or ""
  local enroll_status = tonumber(row[22] or 0)
  local entrycode = row[41] or ""
  -- TODO: add support for Spanish
  -- local lang_adults_primary = row[42] or "00"
  -- if lang_adults_primary == "01" then language = 'Spanish' end
  local ela_status = row[43] or "EO"
  if schoolid == "999999" then 
    schoolid = "104"
    grade_level = "8"
    table.insert(groups, "Graduates")
  elseif enroll_status < 0 or string.find(entrycode, "[NR]D") then 
    table.insert(groups, "New Students")
  end
  if ela_status == "EL" then
    table.insert(groups, "ELAC")
  end

  -- output a row that matches studentHeaders fields for primary family
  -- only group is whether student is new to district or not
  io.write(string.format("%q,%q,%q,%q,%q,%q,", student_number, first_name, last_name, grade_level, language, gender))
  io.write(string.format("%q,%q,%q,%q,%q,%q,%q,%q,", 
    phones.home_phone, phones.mother_work_phone, phones.mother_cell, '', 
    phones.father_work_phone, phones.father_cell,
    primary_phone, additional_phone))
  io.write(string.format("%q,%q,%q,", mother_email, father_email, schoolid))
  io.write(string.format("%q,%q,%q\r\n", groups[1] or "", groups[2] or "", groups[3] or ""))
  
  if verboseFlag > 0 then io.stderr:write("row written\n") end
  
  local phones2 = {
    home_phone = row[15] or "",
    mother_work_phone = row[16] or "",
    mother_cell = row[17] or "",
    father_work_phone = row[18] or "",
    father_cell = row[19] or ""
  }
  
  if phones2.home_phone ~= "" or phones2.mother_work_phone ~= "" or phones2.mother_cell ~= "" or phones2.father_work_phone ~= "" or phones2.father_cell ~= "" then
    -- for secondary family, reference code starts with 'NC'
    local nc_reference = 'NC' .. student_number
    local primary_phone2, additional_phone2 = get_outreach_phones(phones2)
    local mother2_email = row[20] or ""
    local father2_email = row[21] or ""

    -- output a row that matches studentHeaders fields for secondary family
    -- no groups
    io.write(string.format("%q,%q,%q,%q,%q,%q,", nc_reference, first_name, last_name, grade_level, language, gender))
    io.write(string.format("%q,%q,%q,%q,%q,%q,%q,%q,", 
      phones2.home_phone, phones2.mother_work_phone, phones2.mother_cell, '', 
      phones2.father_work_phone, phones2.father_cell,
      primary_phone2, additional_phone2))
    io.write(string.format("%q,%q,%q,", mother2_email, father2_email, schoolid))
    io.write(string.format("%q,%q,%q\r\n", groups[1] or "", groups[2] or "", groups[3] or ""))
      
    if verboseFlag > 0 then io.stderr:write("NC row written\n") end
  end
end

-- convert powerschool autosend files to csv format required by Blackboard Connect
function create_csv_file(psFile, csvFile, headers, rowfn)
  local o = assert(io.open(uploadDir..csvFile, "wb"))
  o:write(table.concat(headers, ','))
  o:write("\r\n")
  io.output(o)
  readtab(psFile, false, rowfn)
  o:close()
end

--function helper for result
--taken from luasocket page (MIT-License)
local function build_w_cb(t)
  return function(s,len)
    table.insert(t, s)
    return len,nil
  end
end

--function helper for headers
--taken from luasocket page (MIT-License)
local function h_build_w_cb(t)
  return function(s,len)
    --stores the received data in the table t
    --prepare header data
    name, value = s:match("(.-): (.+)")
    if name and value then
      t.headers[name] = value:gsub("[\n\r]", "")
    else
      code, codemessage = string.match(s, "^HTTP/.* (%d+) (.+)$")
      if code and codemessage then
        t.code = tonumber(code)
        t.codemessage = codemessage:gsub("[\n\r]", "")
      end
    end
    return len,nil
  end
end

function read_file(fileName)
  local strText = ''
  local i = assert(io.open(fileName, "rb"))
  strText = i:read("*all")
  assert(i:close())
  return strText,string.len(strText)
end

function clear_cookie_file()
  local c = assert(io.open(uploadDir..cookieFile, 'wb'))
  c:write("# Netscape HTTP Cookie File\n")
  assert(c:close())
end

function build_header_options(headers)
  header_opts = ''
  for i, value in ipairs(headers) do
    header_opts = header_opts .. string.format(' -H "%s"', value)
  end
  return header_opts
end

function build_post_options(postdata)
  post_opts = ''
  for key, value in pairs(postdata) do
    if type (value) == "table" and value.file then
      -- file upload
      if value.type then
        post_opts = post_opts .. string.format(' -F "%s=@%s;type=%s"', key, value.file, value.type)
      else
        post_opts = post_opts .. string.format(' -F "%s=@%s"', key, value.file)
      end
    else
      -- string
      post_opts = post_opts .. string.format(' -F "%s=%s"', key, value)
    end
  end
  return post_opts
end

-- contactType: "Student" or "Staff"
-- preserveData: true to remove records that aren't uploaded
function upload_file(uploadFile, contactType, preserveData)
  local postdata = {
    fNTIUser = strUserName,
    fNTIPass = strUserPass,
    fContactType = contactType,
    fRefreshType = contactType,
    fPreserveData = preserveData and 1 or 0,
    fSubmit = 1,
    fFile = { file = uploadDir..uploadFile, type = "text/plain" }
  }
  -- -c: cookiejar file
  -- -o: dump response body to file
  -- -D: dump response headers to file
  -- --libcurl: generate compilable libcurl source file
  -- --trace-ascii: dump more data to file
  -- -s: silent
  -- -j: junk previous session cookies
  -- -L: followlocation
  -- -e: (auto) referer
  -- --post301, --post302: keep POSTing on redirect
  local responseFile = string.gsub(uploadFile, '[.].*$', '-response.html')
  local curl_command = ''
  if verboseFlag > 4 then
    curl_command = string.format('/usr/bin/curl %s %s -c %s -o %s -D %s --libcurl %s --trace-ascii %s -s -j -L -e ";auto" --post301 --post302 %s', 
      build_header_options(httpHeaders),
      build_post_options(postdata),
      uploadDir..cookieFile, 
      uploadDir..responseFile,
      uploadDir..headerFile,
      uploadDir..libcurlFile,
      uploadDir..traceFile,
      destURL)
  else
    curl_command = string.format('/usr/bin/curl %s %s -c %s -o %s -D %s -s -j -L -e ";auto" --post301 --post302 %s', 
      build_header_options(httpHeaders),
      build_post_options(postdata),
      uploadDir..cookieFile,
      uploadDir..responseFile,
      uploadDir..headerFile,
      destURL)
  end
  os.execute(curl_command)

  local s, slen, line
  local resp = { headers = { } }
  local response_body = { }
  local clear_header = false

  -- all of this because when redirecting, curl keeps piling on the 
  -- header lines. if we see a blank line, and then something non-blank
  -- we must clear the header info and start afresh
  local h_func = h_build_w_cb(resp)
  local i = assert(io.open(uploadDir..headerFile, "rb"))
  for line in i:lines() do
    line = string.gsub(line, "[\r\n]+$", "")
    slen = string.len(line)
    if slen == 0 then
      clear_header = true
    else
      if clear_header then
        resp.headers = { }
        resp.code = nil
        resp.codemessage = nil
        clear_header = false
      end
      h_func(line, slen)
    end
  end
  assert(i:close())
  if verboseFlag > 0 then
    io.stderr:write("Post returned " .. resp.code .. "\n")
    io.stderr:write(to_string(resp))
  end
  
  local b_func = build_w_cb(response_body)
  s, slen = read_file(uploadDir..responseFile)
  b_func(s, slen)
  return resp, response_body
end

-- contactType: "Student" or "Staff"
-- preserveData: true to remove records that aren't uploaded
function upload_file_via_lua_curl(uploadFile, contactType, preserveData)
  if not libcurlLoaded then
    require("cURL")
    libcurlLoaded = true
  end

  local postdata = {
    fNTIUser = strUserName,
    fNTIPass = strUserPass,
    fContactType = contactType,
    fRefreshType = contactType,
    fPreserveData = preserveData and 1 or 0,
    fSubmit = 1,
    fFile = { file = uploadDir..uploadFile, type = "text/plain" }
  }
  
  if verboseFlag > 0 then
    io.stderr:write("Posting to " .. destURL .. " with data:\n")
    io.stderr:write(to_string(postdata))
  end

  clear_cookie_file()
  
  local resp = { headers = { } }
  local response_body = { }
  local c = cURL.easy_init()
  c:setopt_httpheader(httpHeaders)
  c:setopt_cookiejar(uploadDir..cookieFile)
  c:setopt_cookiefile(uploadDir..cookieFile)
  c:setopt_followlocation(1)
  -- c:setopt_autoreferer(1)
  -- need a post301 / post302 flag?
  c:setopt_url(destURL)
  c:post(postdata) -- use multipart/form-data
  
  c:perform({headerfunction=h_build_w_cb(resp), writefunction=build_w_cb(response_body)})
  if verboseFlag > 0 then 
    io.stderr:write("Post returned " .. resp.code .. "\n")
    io.stderr:write(to_string(resp))

    local responseFile = string.gsub(uploadFile, '[.].*$', '-response.html')
    local d = assert(io.open(uploadDir..responseFile, 'wb'))
    d:write(table.concat(response_body, "\n"))
    assert(d:close())
  end

  return resp,response_body
end


-- process a staff or student job
-- should mimic vbs script actions
function process_file(contactType, uploadFile, outputFile)
  local strResults = ""
  local s
  local slen

  if verboseFlag > 0 then io.stderr:write("Reading input file\n") end
  s, slen = read_file(uploadDir..uploadFile)
  if slen == 0 then 
    -- No Data Found
    strResults = "Input file has no data."
  else
    -- local status, err_or_resp, response_body = pcall(upload_file, uploadFile, contactType, 1)
    local status, err_or_resp, response_body = pcall(upload_file_via_lua_curl, uploadFile, contactType, 1)
    if status and err_or_resp.code then
      if err_or_resp.code == 200 then
        strResults = "Completed without errors"
      else
        strResults = "Status returned was "..err_or_resp.code
      end
      if response_body then
        strResults = strResults .. ".\nResponse message:\n" .. table.concat(response_body, "\n")
      else
        strResults = strResults .. ", with no response message.\n"
      end
    else
      strResults = "Post failed with error: " .. err_or_resp
    end
  end

  if verboseFlag > 0 then io.stderr:write(strResults .. "\n") end

  local f = assert(io.open(uploadDir..outputFile, "w"))
  f:write(strResults)
  assert(f:close())

  if verboseFlag > 0 then io.stderr:write("Job complete\n") end
end

-- begin main script

-- convert prereg students
-- create_csv_file("classof2012.txt", "classof2012.csv", studentHeaders, writestudentrow)
-- process_file("Other", "classof2012.csv", "classof2012_output.txt")

-- convert powerschool autosend files to BBC csv format
create_csv_file("ps-staff.txt", "staff.csv", staffHeaders, writestaffrow)
create_csv_file("ps-students.txt", "students.csv", studentHeaders, writestudentrow)

-- upload converted files to BBC
process_file("Staff", "staff.csv", "staff_output.txt")
process_file("Student", "students.csv", "student_output.txt")
