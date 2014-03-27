-- bbe.lua
-- generate 4 csv files nightly and for upload to Blackboard Engage

require 'table_print'
require 'app_config'

debugFlag = 1
verboseFlag = 1

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
Reg_Will_Attend
Form2_Updated_At
Form3_Updated_At
Form4_Updated_At
Form5_Updated_At
Form6_Updated_At
Form7_Updated_At
Form8_Updated_At
Form9_Updated_At
Form10_Updated_At
Form11_Updated_At
Form12_Updated_At
Form13_Updated_At
Form14_Updated_At
Reg_Grade_Level
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

-- course fields
autosend_section_fields = [[
id
course_number
section_number
schoolid
[02]course_name
[05]teachernumber
[13]abbreviation
[05]last_name
]]

-- cc fields
autosend_roster_fields = [[
sectionid
course_number
section_number
schoolid
[02]course_name
[05]teachernumber
[13]abbreviation
[05]last_name
[01]student_number
expression
]]

-- number of elements in table (table.getn is for "lists" only)
function tlength(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

-- strip whitespace from beginning and end of string
function string:trim6()
  return self:match'^()%s*$' and '' or self:match'^%s*(.*%S)'
end

-- headers for staff file
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

function wordsplit(s)
	local t = { }
	for word in s:gmatch('%w+') do 
		table.insert(t, word) 
	end
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

function course_abbr(name)
  local words = wordsplit(name)
  local abbr = string.sub(words[1], 1, 4)
  local suffix = ''
  local nwords = table.getn(words) 
  if nwords > 1 then
    local lastw = words[nwords]
    if lastw == 'K' or tonumber(lastw) ~= nil and tonumber(lastw) > 0 then
    	suffix = lastw
    end
  end
  return abbr .. suffix
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

function readtab(fname, headers, rowfn, sumfn)
  io.input(sourceDir..fname)
  local lno = headers and 0 or 1
  local columns = { }
  while true do
    local line = io.read()
    if verboseFlag > 2 then io.stderr:write("reading " .. fname .. " line " .. lno .. "\n") end
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
	if sumfn then
		local status, err = pcall(sumfn, fname, lno)
	end
end

-- edline specific stuff 
included_students = nil
if debugFlag then
	included_students = { ['111984']=true, ['111985']=true }
end

excluded_courses = { ['9991']=true, ['9993']=true, ['9996']=true, ['9997']=true }
class_table = { }
course_terms = { }
assigned_teachers = { }
enrolled_students = { }
enrolled_classes = { }

-- if we are limiting students for testing purposes
function check_student(sn)
	return sn~= "" and (not included_students or included_students[sn])
end

function check_teacher(tn)
	return tn~= ""
end

function check_course(cn)
	return cn ~= "" and not excluded_courses[cn]
end

function check_school(sid)
	return sid == "103" or sid == "104"
end

function check_class(cid)
	return enrolled_classes[cid]
end

function full_year(term)
	return not term:match('^[STQH][1-6]$')
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writestudentrow(row, fname, lno)
  -- student fields
  local student_number = row[1] or ""
  local first_name = row[2]
  local last_name = row[3]
  local grade_level = 0 + row[4]
  local schoolid = row[7]
  local enroll_status = tonumber(row[22] or 0)
  if enroll_status == 0 and check_student(student_number) and check_school(schoolid) then		
		enrolled_students[student_number] = true
		local s_grade_level = string.format("%02d", grade_level);
		
	  -- output a row 
	  -- "ID","LastName","FirstName","GradeLevel","SchoolID" 
	  io.write(string.format("%q,%q,%q,%q,%q\r\n", "S" .. student_number, last_name, first_name, s_grade_level, schoolid))
  
	  if verboseFlag > 2 then io.stderr:write("row written\n") end
	end
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writeschedulerow(row, fname, lno)
  -- cc fields
	local course_number = row[2]
  local schoolid = row[4]
  local student_number = row[9] or ""

  if enrolled_students[student_number] and check_course(course_number) and check_school(schoolid) then
  	local section_number = row[3]
		local teachernumber = row[6]
		local term = row[7]
		local class_id = "C" .. schoolid .. "-" .. course_number .. "-" .. teachernumber
		if not full_year(term) then 
			class_id = class_id .. "-" .. term
		end
		enrolled_classes[class_id] = true
		
	  -- output a row 
	  -- "ClassID","StudentID","SchoolID" 
	  io.write(string.format("%q,%q,%q\r\n", class_id, "S" .. student_number, schoolid))
  
	  if verboseFlag > 2 then io.stderr:write("row written\n") end
	end
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writeclassrow(row, fname, lno)
  -- section fields
	local course_number = row[2]
  local schoolid = row[4]
	local teachernumber = row[6] or ""
	
  if check_teacher(teachernumber) and check_course(course_number) and check_school(schoolid) then
		local section_number = row[3]
  	local course_name = (row[5] or ""):trim6()
		local term = row[7]
		local teacher_last = row[8]
		local class_id    = "C" .. schoolid .. "-" .. course_number .. "-" .. teachernumber
		local course_term = "C" .. course_number
		local class_teacher_name = course_name .. "-" .. teacher_last
		local class_bare_name    = course_name
		if not full_year(term) then
		 	class_id    = class_id .. "-" .. term
			course_term = course_term .. "-" .. term
			class_teacher_name = class_teacher_name .. "-" .. term
			class_bare_name    = class_bare_name .. "-" .. term
		end
		if check_class(class_id) then
			if not class_table[class_id] then
				assigned_teachers[teachernumber] = true
				class_table[class_id] = { class_bare_name, class_teacher_name, "T" .. teachernumber, schoolid }
			end
			if not course_terms[course_term] then
				course_terms[course_term] = {  }
			end
			course_terms[course_term][class_id] = true
		end
	end
end

function writeclasses(fname, lno)
	for course_term, class_id_table in pairs(course_terms) do
		local nclass_ids = tlength(class_id_table)
		for class_id, _ in pairs(class_id_table) do
			local data = class_table[class_id]
			local class_name = nclass_ids > 1 and data[2] or data[1]
		  -- output a row 
		  -- ClassID","Class Name","TeacherID","SchoolID"
		  io.write(string.format("%q,%q,%q,%q\r\n", class_id, class_name, data[3], data[4]))
  	end
	end
end

-- convert row. if autosend fields are changed, you must change the logic
-- in this function
function writestaffrow(row, fname, lno)
  -- staff fields
  local status = 0 + (row[1] or 0)
  local staffstatus = 0 + (row[2] or 0)
  local teachernumber = row[4] or ""
  local first_name = row[5] or ""
  local last_name = row[6] or ""
  local schoolid = row[8] or ""

  if assigned_teachers[teachernumber] then
    -- output a row

    -- "ID","LastName","FirstName","GradeLevel","SchoolID”
    io.write(string.format("%q,%q,%q,%q,%q\r\n", "T" .. teachernumber, last_name, first_name, "", schoolid))
    if verboseFlag > 2 then io.stderr:write("row written\n") end
  end
end

-- convert powerschool autosend files to csv format required by Edline
function create_csv_file(psFile, csvFile, mode, rowfn, sumfn)
  local o = assert(io.open(uploadDir..csvFile, mode))
  io.output(o)
  readtab(psFile, false, rowfn, sumfn)
  o:close()
end

-- begin main script

-- must run students first (to get enroll_status)!
create_csv_file("ps-students.txt",        "edline-student.csv",  'wb', writestudentrow, nil)
-- must run rosters before sections!
create_csv_file("ps-rosters-bacich.txt",  "edline-schedule.csv", 'wb', writeschedulerow, nil)
create_csv_file("ps-rosters-kent.txt",    "edline-schedule.csv", 'ab', writeschedulerow, nil)
-- must run sections before staff!
create_csv_file("ps-sections-bacich.txt", "edline-class.csv",    'wb', writeclassrow, nil)
create_csv_file("ps-sections-kent.txt",   "edline-class.csv",    'ab', writeclassrow, writeclasses)
create_csv_file("ps-staff.txt",           "edline-teacher.csv",  'wb', writestaffrow, nil)
