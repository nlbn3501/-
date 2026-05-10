path = r"C:\Users\spg\Desktop\mms_structure\project-260409\Global.gd"
with open(path, "rb") as f:
    data = f.read()
print(f"File size: {len(data)} bytes")
print(f"First 20 bytes: {data[:20]}")
print(f"Has BOM: {data.startswith(bytes([0xEF, 0xBB, 0xBF]))}")
if b"\r\n" in data:
    print("Line ending: CRLF")
else:
    print("Line ending: LF")
print(f"Total tabs: {data.count(b'\t')}")
print(f"Total lines: {len(data.split(b'\n'))}")
