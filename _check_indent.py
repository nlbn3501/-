path = r"C:\Users\spg\Desktop\mms_structure\project-260409\Global.gd"
with open(path, "rb") as f:
    data = f.read()
lines = data.split(b"\n")
for i in [42, 43, 44, 86, 87, 88, 107, 108, 109]:
    line = lines[i]
    tabs = line.count(b"\t")
    spaces = line.count(b" ")
    leading = b""
    for b in line:
        if b == 9:
            leading += b"T"
        elif b == 32:
            leading += b"S"
        else:
            break
    print(f"Line {i+1}: tabs={tabs} spaces={spaces} leading={leading.decode()}")
