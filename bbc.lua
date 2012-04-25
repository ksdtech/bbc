-- bbc.lua
-- generate students.csv and staff.csv nightly and upload them to Blackboard Connect

require "table_print"
require "app_config"

-- libcurl stuff
require "cURL"
libcurlLoaded = true
cookieFile = "cookies.txt"

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
  'EmailAddress', 'EmailAddressAlt', 'Institution', 'Group' }

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

function readtab(fname, headers, rowfn)
  io.input(sourceDir..fname)
  local lno = headers and 0 or 1
  local columns = { }
  while true do
    local line = io.read()
    if verboseFlag then io.stderr:write("reading " .. fname .. " line " .. lno .. "\n") end
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
      if verboseFlag and not status then
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
      if verboseFlag then io.stderr:write("row written\n") end
    else
      if verboseFlag then io.stderr:write("no staff groups\n") end
    end
  else
    if verboseFlag then io.stderr:write("not current staff member\n") end
  end
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writestudentrow(row, fname, lno)
  -- student fields
  local student_number = row[1]
  local first_name = row[2]
  local last_name = row[3]
  local grade_level = row[4]
  local gender = string.upper(row[5] or "")
  local teacher = row[6] or ""
  local schoolid = row[7]
  local home_phone = row[8] or ""
  local mother_work_phone = row[9] or ""
  local mother_cell = row[10] or ""
  local father_work_phone = row[11] or ""
  local father_cell = row[12] or ""
  local mother_email = row[13] or ""
  local father_email = row[14] or ""
  local new_student = ""
  local entrycode = row[41] or ""
  if string.find(entrycode, "[NR]D") then new_student = 'New Students' end
  local language = 'English'
  -- TODO: add support for Spanish
  -- local lang_adults_primary = row[42] or "00"
  -- if lang_adults_primary == "01" then language = 'Spanish' end

  -- output a row that matches studentHeaders fields for primary family
  -- only group is whether student is new to district or not
  io.write(string.format("%q,%q,%q,%q,%q,%q,", student_number, first_name, last_name, grade_level, language, gender))
  io.write(string.format("%q,%q,%q,%q,%q,%q,", home_phone, mother_work_phone, mother_cell, '', father_work_phone, father_cell))
  io.write(string.format("%q,%q,%q,%q\r\n", mother_email, father_email, schoolid, new_student))
  if verboseFlag then io.stderr:write("row written\n") end
  
  local home2_phone = row[15]
  local mother2_work_phone = row[16]
  local mother2_cell = row[17]
  local father2_work_phone = row[18]
  local father2_cell = row[19]
  if home2_phone or mother2_work_phone or mother2_cell or father2_work_phone or father2_cell then

    -- for secondary family, reference code starts with 'NC'
    local nc_reference = 'NC' .. student_number
    home2_phone = row[15] or ""
    mother2_work_phone = row[16] or ""
    mother2_cell = row[17] or ""
    father2_work_phone = row[18] or ""
    father2_cell = row[19] or ""
    local mother2_email = row[20] or ""
    local father2_email = row[21] or ""

    -- output a row that matches studentHeaders fields for secondary family
    -- no groups
    io.write(string.format("%q,%q,%q,%q,%q,%q,", nc_reference, first_name, last_name, grade_level, language, gender))
    io.write(string.format("%q,%q,%q,%q,%q,%q,", home2_phone, mother2_work_phone, mother2_cell, '', father2_work_phone, father2_cell))
    io.write(string.format("%q,%q,%q,%q\r\n", mother2_email, father2_email, schoolid, new_student))
    if verboseFlag then io.stderr:write("NC row written\n") end
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

-- contactType: "Student" or ""
-- preserveData: true to remove records that aren't uploaded
function upload_file(uploadFile, contactType, preserveData)
  if not libcurlLoaded then
    require("cURL")
    libcurlLoaded = true
  end

  local c = cURL.easy_init()
  c:setopt_url(destURL)
  c:setopt_followlocation(1)
  c:setopt_maxredirs(5)
  c:setopt_cookiejar(cookieFile)
  
  -- post file from filesystem
  local postdata = {
    fNTIUser = strUserName,
    fNTIPass = strUserPass,
    fContactType = contactType,
    fRefreshType = contactType,
    fPreserveData = preserveData and 1 or 0,
    fSubmit = 1,
    fFile = { file = uploadDir..uploadFile, type = "text/plain" }
  }
  if verboseFlag then
    io.stderr:write("Posting to " .. destURL .. "with data:\n")
    io.stderr:write(to_string(postdata))
  end
  c:post(postdata)
  
  local resp = { headers = { } }
  local response_body = { }
  c:perform({headerfunction=h_build_w_cb(resp), writefunction=build_w_cb(response_body)})
  if verboseFlag then 
    io.stderr:write("Post returned " .. resp.code .. "\n")
    io.stderr:write(to_string(resp))
  end 
  return resp,response_body
end

-- process a staff or student job
-- should mimic vbs script actions
function process_file(contactType, inputFile, uploadFile, outputFile)
  local strResults = ""
  local strText = ""

  if verboseFlag then io.stderr:write("Reading input file\n") end

  local i = assert(io.open(uploadDir..inputFile, "rb"))
  strText = i:read("*all")
  assert(i:close())

  local s, e, data = string.find(strText, "^%S+[^\r\n]+[\r\n]+(%S+),")
  if data == nil or string.len(data) == 0 then
    -- No Data Found
    strResults = "Input file has no data"
  else
    if verboseFlag then io.stderr:write("Creating upload file\n") end

    -- create upload file
    local u = assert(io.open(uploadDir..uploadFile, "wb"))
    u:write(strText)
    assert(u:close())

    if verboseFlag then io.stderr:write("Sending upload file\n") end

    local status, err_or_resp, response_body = pcall(upload_file, uploadFile, contactType, true)
    if status then
      if err_or_resp.code and err_or_resp.code >= 200 and err_or_resp.code < 400 then
        strResults = "Completed without errors"
      else
        if response_body then
          strResults = table.concat(response_body, "\n")
        else
          strResults = "Post Failed?  No response body"
        end
      end
    else
      strResults = "Post Failed. " .. err_or_resp
    end
  end

  if verboseFlag then io.stderr:write(strResults .. "\n") end

  local f = assert(io.open(uploadDir..outputFile, "w"))
  f:write(strResults)
  assert(f:close())

  if verboseFlag then io.stderr:write("Job complete\n") end
end

-- begin main script

-- convert powerschool autosend files to BBC csv format
-- create_csv_file("ps-staff.txt", "staff.csv", staffHeaders, writestaffrow)
-- create_csv_file("ps-students.txt", "students.csv", studentHeaders, writestudentrow)

-- upload converted files to BBC
process_file("Staff", "staff.csv", "staff_upload.txt", "staff_output.txt")
-- process_file("Student", "students.csv", "student_upload.txt", "student_output.txt")
