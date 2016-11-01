# bbc.py
# generate students.csv and staff.csv nightly and upload them to Blackboard Connect

import certifi
import csv
import os.path
import pycurl
import re
from StringIO import StringIO
import sys
import traceback

# Application settings (passwords, etd, not in git repository)
from app_config import (
  regFormStartDate, verboseFlag, sourceDir, uploadDir,
  strUserName, strUserPass, destURL)

# Global settings (TODO: put these in command line arguments)
# input file is only pre-regs
allPreRegs = False

# input file is only graduates
allGraduates = False

# allow pre-reg groups
preRegGroups = False
if allPreRegs:
  preRegGroups = True

# Allow online reg status groups
# 0 - do not add these groups
# 1 - check pre-regs (before EOY)
# 2 - check active (after EOY)
regStatusGroups = 0
if allPreRegs or allGraduates:
  regStatusGroups = 0

# Algorithm to select PrimaryPhone and AdditionalPhone, as available
staff_phone_prefs   = [ 'cell', 'home_phone' ]
student_phone_prefs = [ 'mother_cell', 'father_cell', 'home_phone',
  'mother_work_phone', 'father_work_phone' ]
student_sms_phone_prefs = [ 'mother_cell', 'father_cell' ]

# Settings for with pycurl
cookieFile    = 'cookies.txt'
headerFile    = 'headers.txt'
libcurlFile   = 'curl.c'
traceFile     = 'trace.txt'


# bbc-students AutoSend fields
# tab field delimiter, lf line delimiter, no headers
autosend_student_fields = [s.strip() for s in '''
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
Family_Ident
Mother_Staff_Id
Mother_First
Mother
Father_Staff_Id
Father_First
Father
Student_Web_Id
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
Reg_Grade_Level
ExitCode
Form3_Updated_At
Form4_Updated_At
Form6_Updated_At
Form9_Updated_At
Form10_Updated_At
Form15_Updated_At
Form1_Updated_At
Form16_Updated_At
TK_Current_Year
CA_PrimDisability
CA_SpEd504
'''.split('\n')[1:-1]]
student_nfields = len(autosend_student_fields)

# bbc-staff AutoSend fields
# tab field delimiter, lf line delimiter, no headers
autosend_staff_fields = [s.strip() for s in '''
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
'''.split('\n')[1:-1]]
staff_nfields = len(autosend_staff_fields)

# headers for staff file
# 6 groups
staffHeaders = [s.strip() for s in '''
ReferenceCode
FirstName
LastName
HomePhone
MobilePhone
SMSPhone
PrimaryPhone
AdditionalPhone
EmailAddress
Institution
RefreshGroup
RefreshGroup
RefreshGroup
RefreshGroup
RefreshGroup
RefreshGroup
'''.split('\n')[1:-1]]

# headers for students file
# 6 groups
studentHeaders = [s.strip() for s in '''
ReferenceCode
FirstName
LastName
Grade
Language
Gender
HomePhone
WorkPhone
MobilePhone
HomePhoneAlt
WorkPhoneAlt
MobilePhoneAlt
SMSPhone
SMSPhone2
PrimaryPhone
AdditionalPhone
EmailAddress
EmailAddressAlt
Institution
RefreshGroup
RefreshGroup
RefreshGroup
RefreshGroup
RefreshGroup
RefreshGroup
'''.split('\n')[1:-1]]

# headers for students file
# 6 groups
studentNoRefreshHeaders = [s.strip() for s in '''
ReferenceCode
FirstName
LastName
Grade
Language
Gender
HomePhone
WorkPhone
MobilePhone
HomePhoneAlt
WorkPhoneAlt
MobilePhoneAlt
SMSPhone
SMSPhone2
PrimaryPhone
AdditionalPhone
EmailAddress
EmailAddressAlt
Institution
Group
Group
Group
Group
Group
Group
'''.split('\n')[1:-1]]

# Get first and second phone depending on user type
def get_outreach_phones(phones, prefs):
  primary_phone = ''
  additional_phone = ''
  for key in prefs:
    test = phones[key]
    if test != '':
      if primary_phone == '':
        primary_phone = test
      elif additional_phone == '' and test != primary_phone:
        additional_phone = test
        break
  return (primary_phone, additional_phone)


# Convert one row of staff data.
# WARNING: If you change AutoSend fields, you must change the logic in this function
def writestaffrow(out, row, fname, lno, group):
  if len(row) < staff_nfields:
    sys.stderr.write('%s line %d - row not parsed?\n' % (fname, lno))
    sys.stderr.write('%d staff fields, %d fields in row\n' % (staff_nfields, len(row)))
    sys.stderr.write('%s\n' % row)
    return

  # staff fields
  status        = int(row[0]) if row[0] else 0
  staffstatus   = int(row[1]) if row[1] else 0
  title         = row[2].lower()
  teachernumber = row[3] or '000000'
  first_name    = row[4]
  last_name     = row[5]

  if status == 1 and title != 'v-staff':
    groups = [ ]
    # staffstatus 0 is 'unassigned'
    if group:
      groups.append(group)
    if staffstatus == 1:
      groups.append('Certificated')
    elif staffstatus == 2:
      groups.append('Classified')
    # staffstatus 3 is 'lunch staff'
    # staffstatus 4 is 'substitute'

    group_membership = row[14].lower()
    if 'administrators' in group_membership:
      groups.append('Administrators')
    if 'trustees' in group_membership:
      groups.append('Board')
    if len(groups) > 0:

      gender = row[6].upper()

      # any staff not assigned to school goes into District Office code 102
      schoolid = row[7]
      if schoolid != '103' and schoolid != '104':
        schoolid = '102'
      phones = {
        'home_phone': row[8],
        'cell':       row[9]
      }
      primary_phone, additional_phone = get_outreach_phones(phones, staff_phone_prefs)
      email_address = row[10]

      while len(groups) < 6:
        groups.append('')

      # output a row that matches staffHeaders fields
      # use cell for SMSPhone
      # use cell, then home phone for Primary and Alternate
      out.writerow([teachernumber, first_name, last_name,
        phones['home_phone'], phones['cell'], phones['cell'],
        primary_phone, additional_phone,
        email_address, schoolid] + groups[:6])

      if verboseFlag > 2:
        sys.stderr.write('row written\n')
    elif verboseFlag > 1:
      sys.stderr.write('%s %s %s: no staff groups\n' %
        (teachernumber, first_name, last_name))
  elif verboseFlag > 1:
    sys.stderr.write('%s %s %s: not a current staff member\n' %
      (teachernumber, first_name, last_name))

# convert row. if autosend fields are changed, you must change the logic
# in this function
def writestudentrow(out, row, fname, lno, group):
  if len(row) < student_nfields:
    sys.stderr.write('%s line %d - row not parsed?\n' % (fname, lno))
    sys.stderr.write('%d student fields, %d fields in row\n' % (student_nfields, len(row)))
    sys.stderr.write('%s\n' % row)
    return

  # student fields
  language        = 'English'
  groups          = [ ]
  student_number  = row[0]
  first_name      = row[1]
  last_name       = row[2]
  grade_level     = int(row[3])
  is_tk           = row[54]
  sped_disability = row[55]
  is_504          = row[56]
  if grade_level == 0:
    if is_tk:
      grade_level = 'TK'
    else:
      grade_level = 'RK'
  gender          = row[4].upper()
  teacher         = row[5]
  schoolid        = row[6]
  phones = {
    'home_phone':        row[7],
    'mother_work_phone': row[8],
    'mother_cell':       row[9],
    'father_work_phone': row[10],
    'father_cell':       row[11]
  }
  primary_phone, additional_phone = get_outreach_phones(phones, student_phone_prefs)
  sms_phone, sms_phone_2 = get_outreach_phones(phones, student_sms_phone_prefs)
  mother_email    = row[12]
  father_email    = row[13]
  enroll_status   = int(row[21])
  entrycode       = row[40]

  # TODO: add support for Spanish
  # lang_adults_primary = row[42-1] or '00'
  # if lang_adults_primary == '01' then language = 'Spanish' end
  ela_status      = row[42] or 'EO'
  will_attend     = row[43]
  reg_grade_level = row[44]

  if group:
    groups.append(group)
  if is_tk:
    groups.append('Transitional Kindergarten')
  if ela_status == 'EL':
    groups.append('ELAC')
  if sped_disability != '':
    groups.append('SPED')
  elif is_504:
    groups.append('504')

  if schoolid == '999999':
    schoolid = '104'
    grade_level = 9
    groups.append('Graduates')

  if schoolid == '103' or schoolid == '104':
    is_new = 'ND' == entrycode or 'RD' == entrycode
    if (not allPreRegs) and (is_new or enroll_status < 0):
      groups.append('New Students')

    if preRegGroups and (allPreRegs or (enroll_status < 0)):
      if reg_grade_level in ['5','6','7','8']:
        schoolid = '104'
        groups.append('Pre-Registered 5-8')
      else:
        schoolid = '103'
        if reg_grade_level == 'TK':
          groups.append('Pre-Registered TK')
        elif reg_grade_level == 'K':
          groups.append('Pre-Registered K')
        else:
          groups.append('Pre-Registered 1-4')

    if regStatusGroups > 0:
      attending = True
      if regStatusGroups == 1:
        will_attend = row[43]
        if 'nr-' in will_attend:
          # not returning
          attending = False
          groups.append('Registration Will Be Exiting')

      if attending:
        # blank (unknown) or returning
        pages_completed = 0
        pages_required = 0
        # check forms 3, 4, 6, 9 and 10 only for now
        for k in range(46, 51):
          date = row[k] or '0000-00-00'
          date = date[:10]
          pages_required = pages_required + 1
          # WARNING: hard coded date!
          if date >= regFormStartDate:
            pages_completed = pages_completed + 1

        if pages_completed == 0:
          groups.append('Registration Not Started')
        elif pages_completed < pages_required:
          groups.append('Registration Partially Complete')

  while len(groups) < 6:
    groups.append('')

  # output a row that matches studentHeaders fields for primary family
  # use mother and father cells for SMSPhones
  # use cell, then home phone for Primary and Alternate
  # possible groups are Graduates, New Students, ELAC
  out.writerow([student_number, first_name, last_name, grade_level, language, gender,
    phones['home_phone'], phones['mother_work_phone'], phones['mother_cell'], '',
    phones['father_work_phone'], phones['father_cell'],
    sms_phone, sms_phone_2,
    primary_phone, additional_phone,
    mother_email, father_email, schoolid] + groups[:6])

  if verboseFlag > 2:
    sys.stderr.write('row written\n')

  phones2 = {
    'home_phone':        row[14],
    'mother_work_phone': row[15],
    'mother_cell':       row[16],
    'father_work_phone': row[17],
    'father_cell':       row[18]
  }

  if phones2['home_phone'] or phones2['mother_work_phone'] or phones2['mother_cell'] or phones2['father_work_phone'] or phones2['father_cell']:
    # for secondary family, reference code starts with 'NC'
    nc_reference = 'NC' + student_number
    primary_phone2, additional_phone2 = get_outreach_phones(phones2, student_phone_prefs)
    sms_phone2, sms_phone2_2 = get_outreach_phones(phones2, student_sms_phone_prefs)
    mother2_email    = row[19]
    father2_email    = row[20]

    # output a row that matches studentHeaders fields for secondary family
    out.writerow([nc_reference, first_name, last_name, grade_level, language, gender,
      phones2['home_phone'], phones2['mother_work_phone'], phones2['mother_cell'], '',
      phones2['father_work_phone'], phones2['father_cell'],
      sms_phone2, sms_phone2_2,
      primary_phone2, additional_phone2,
      mother2_email, father2_email, schoolid] + groups[:6])

    if verboseFlag > 2:
      sys.stderr.write('NC row written\n')

# Process a tab-delimited input file, calling rowfn on each row
# If headers are given, row ia a dict, otherwise row is a list
def readtab(fname, headers, rowfn, out, group):
  with open(os.path.join(sourceDir, fname), 'rb') as io:
    lno = 0
    calling = None
    if headers:
      lno = 1
      cin = csv.DictReader(io, fieldnames=headers,
        delimiter='\t', lineterminator='\n', quoting=csv.QUOTE_NONE)
    else:
      cin = csv.reader(io,
        delimiter='\t', lineterminator='\n', quoting=csv.QUOTE_NONE)
    for raw_row in cin:
      try:
        if headers:
          row = { }
          for key, value in raw_row.iteritems():
            row[key] = value.strip()
          rowfn(out, row, fname, lno, group)
        else:
          row = [value.strip() for value in raw_row]
          rowfn(out, row, fname, lno, group)
      except:
        if verboseFlag > 0:
          e = sys.exc_info()[0]
          sys.stderr.write('%s row %d invalid: %s\n' % (fname, lno, e))
          sys.stderr.write('%s\n' % raw_row)
          traceback.print_exc()
          break
      lno += 1

# Convert PowerSchool AutoSend files to csv format required by Blackboard Connect
def create_csv_file(psFile, csvFile, headers, rowfn, group):
  with open(os.path.join(uploadDir, csvFile), 'wb') as io:
    # write out with CRLF
    out = csv.writer(io,
      delimiter=',', lineterminator='\r\n', quoting=csv.QUOTE_ALL)
    out.writerow(headers)
    readtab(psFile, False, rowfn, out, group)

# used with curl command
cookieFile    = 'cookies.txt'
headerFile    = 'headers.txt'
libcurlFile   = 'curl.c'
traceFile     = 'trace.txt'
# libcurlLoaded = false

# headers to send for file upload
# copied from WinHttp.WinHttpRequest component defaults
# Connection: Keep-Alive is the key header!
# Expect: removes the Expext: 100-continue header
httpHeaders = [
  'Accept: */*',
  'User-Agent: Mozilla/4.0 (compatible; Win32; WinHttp.WinHttpRequest.5)',
  'Version: HTTP/1.1',
  'Connection: Keep-Alive',
  'Expect:'
]

# Destroy previous cookies
def clear_cookie_file():
  with open(os.path.join(uploadDir, cookieFile), 'wb') as c:
    c.write('# Netscape HTTP Cookie File\n')

# contactType: 'Student' or 'Staff'
# preserveData: true to remove records that aren't uploaded
def upload_file(uploadFile, contactType, preserveData):
  clear_cookie_file()

  resp_headers = StringIO()
  resp_body = StringIO()

  c = pycurl.Curl()
  c.setopt(c.HTTPHEADER, httpHeaders)
  c.setopt(c.COOKIEJAR, os.path.join(uploadDir, cookieFile))
  c.setopt(c.COOKIEFILE, os.path.join(uploadDir, cookieFile))
  c.setopt(c.FOLLOWLOCATION, True)
  # Use certifi package to provide SSL CA chain
  c.setopt(c.CAINFO , certifi.where());
  # c.setopt(autoreferer, True1)
  # need a post301 / post302 flag?

  postdata = [
    ('fNTIUser',      strUserName),
    ('fNTIPass',      strUserPass),
    ('fContactType',  contactType),
    ('fRefreshType',  contactType),
    ('fPreserveData', '1' if preserveData else '0'),
    ('fSubmit',       '1'),
    ('fFile', (
      c.FORM_FILE,        os.path.join(uploadDir, uploadFile),
      c.FORM_CONTENTTYPE, 'text/plain'
    ))
  ]

  # Sets request method to POST and data to list of tuples
  c.setopt(c.HTTPPOST, postdata)
  c.setopt(c.HEADERFUNCTION, resp_headers.write)
  c.setopt(c.WRITEFUNCTION, resp_body.write)
  c.setopt(c.URL, destURL)

  if verboseFlag > 0:
    sys.stderr.write('Posting to %s with data:\n%s\n' % (destURL, postdata))

  result = c.perform()
  code = c.getinfo(c.HTTP_CODE)
  resp = resp_body.getvalue()
  if verboseFlag > 0:
    sys.stderr.write('%s\n' % resp)
  responseFile = re.sub(r'[.].*$', '-response.html', uploadFile)
  with open(os.path.join(uploadDir, responseFile), 'wb') as io:
    io.write('%s' % resp)
  return (code, resp, result)

# process a staff or student job
# should mimic vbs script actions
def process_file(contactType, uploadFile, outputFile):
  if verboseFlag > 0:
    sys.stderr.write('Reading input file\n')

  slen = 0
  try:
    with open(os.path.join(uploadDir, uploadFile), 'rb') as io:
      c = io.read(100)
      if c is not None:
        slen = len(c)
  except:
    pass

  strResults = ''
  if slen == 0:
    strResults = 'Input file has no data.\n'
  else:
    try:
      code, resp, result = upload_file(uploadFile, contactType, True)
      if code == 200:
        strResults = 'Completed without errors'
      else:
        strResults = 'Status returned was %d' % code

      if resp:
        strResults += ('.\nResponse message:\n%s\n' % resp)
      else:
        strResults += ', with no response message.\n'
    except pycurl.error as e:
      strResults = 'Post failed with error: %s\n' % e

  if verboseFlag > 0:
    sys.stderr.write(strResults)

  with open(os.path.join(uploadDir, outputFile), 'w') as io:
    io.write(strResults)

  if verboseFlag > 0:
    sys.stderr.write('Job complete\n')

# Begin main script
def main():
  if allPreRegs:
    # convert pre-reg students
    create_csv_file('prereg-1617.txt', 'preregs.csv', studentNoRefreshHeaders, writestudentrow, None)
    process_file('Other', 'preregs.csv', 'preregs_output.txt')

  if allGraduates:
    # Convert graduating students
    create_csv_file('graduated-2016.txt', 'graduated-2016.csv', studentNoRefreshHeaders, writestudentrow, 'Graduated 2016')
    process_file('Other', 'graduated-2016.csv', 'graduated-2016_output.txt')

  if not allPreRegs and not allGraduates:
    # convert powerschool autosend files to BBC csv format
    create_csv_file('ps-staff.txt', 'staff.csv', staffHeaders, writestaffrow, None)
    create_csv_file('ps-students.txt', 'students.csv', studentHeaders, writestudentrow, None)

    # Upload converted files to BBC
    process_file('Staff', 'staff.csv', 'staff_output.txt')
    process_file('Student', 'students.csv', 'student_output.txt')

if __name__ == '__main__':
  main()
