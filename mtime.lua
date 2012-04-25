
lfs = require("lfs")
mtime = lfs.attributes("student_output.txt", "modification")
stime = os.date("%b %d %Y %H:%M:%S", mtime)
print(stime)


