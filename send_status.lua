smtp = require("socket.smtp")
mime = require("mime")
ltn12 = require("ltn12")
lfs = require("lfs")
require("app_config")

mtime = lfs.attributes("student_output.txt", "modification")
stutime = os.date("%b %d %Y %H:%M:%S", mtime)
mtime = lfs.attributes("staff_output.txt", "modification")
stftime = os.date("%b %d %Y %H:%M:%S", mtime)

txt = string.format("student_output.txt created %s\nstaff_output.txt created %s",
  stutime, stftime)

msg = smtp.message {
  headers = {
    from = mailfrom,
  to = mailto,
  subject = "Blackboard Connect upload status"
  },
  body = {
    preamble = "This message contains attachments.",
  [1] = {
    headers = {
      ["content-type"] = 'text/plain'
    },
    body = txt
  },
  [2] = {
    headers = {
      ["content-type"] = 'text/plain; name="student_output.txt"',
    ["content-disposition"] = 'attachment; filename="student_output.txt"',
    },
    body = ltn12.source.file(io.open("student_output.txt", "r"))
  },
  [3] = {
    headers = {
      ["content-type"] = 'text/plain; name="staff_output.txt"',
    ["content-disposition"] = 'attachment; filename="staff_output.txt"',
    },
    body = ltn12.source.file(io.open("staff_output.txt", "r"))
  }
  }
}

status, err = smtp.send {
  from = mailfrom,
  rcpt = mailto,
  source = msg,
  server = smtphost,
  port = smtpport
}

