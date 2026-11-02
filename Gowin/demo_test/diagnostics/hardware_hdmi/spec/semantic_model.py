"""Reference raster and telemetry field checks, independent of RTL."""
def raster(x,y):
    return x<1280 and y<720, 1390<=x<1430, 725<=y<730
assert sum(raster(x,0)[0] for x in range(1650)) == 1280
assert sum(raster(x,0)[1] for x in range(1650)) == 40
assert sum(raster(0,y)[2] for y in range(750)) == 5
assert abs(50_000_000*22/15/1650/750-59.2592592593)<1e-6
def key(line):
    assert len(line)==9 and line[0]=="K" and line[3]==":" and line[-2:]=="\r\n"
    return int(line[1:3])-1,int(line[4:7],16)
assert key("K32:ABC\r\n")== (31,2748)
print("PASS semantic model")
