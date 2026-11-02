"""FPGA 划弦的独立整数参考语义，坐标0..1023。"""
CENTERS = ([102,307,512,717,922], [73,219,366,512,658,805,951])
LINES = (256,512,768)

def position(weights, mask):
    result=[]
    for start, centers in ((0,CENTERS[0]),(5,CENTERS[1])):
        selected=[i for i in range(len(centers)) if mask & (1<<(start+i))]
        if not selected or selected[-1]-selected[0]+1!=len(selected): return None
        values=[max(1,weights[start+i]) for i in selected]
        result.append(sum(centers[i]*w for i,w in zip(selected,values))//sum(values))
    return tuple(result)

class Detector:
    def __init__(self):
        self.sides=[0]*6; self.last=[-1000]*6; self.previous=None
    def update(self, point, ms):
        if point is None:
            self.sides=[0]*6; self.previous=None; return 0
        fresh=self.previous is not None and 0<=ms-self.previous<=40
        mask=0
        for axis,value in enumerate(point):
            for slot,line in enumerate(LINES):
                n=axis*3+slot
                side=-1 if value<line-20 else 1 if value>line+20 else 0
                if side:
                    if fresh and self.sides[n] and side!=self.sides[n] and ms-self.last[n]>=12:
                        mask |= 1<<n; self.last[n]=ms
                    self.sides[n]=side
                elif not fresh: self.sides[n]=0
        self.previous=ms
        return mask

if __name__=='__main__':
    d=Detector()
    assert d.update((102,512),0)==0
    assert d.update((922,512),4)==7
    assert d.update((102,512),20)==7
    assert d.update(None,21)==0
    assert d.update((922,512),24)==0
    assert position([20]*12,0x101)==(102,512)
    assert position([20]*12,0x105) is None
    print('PASS integer centroid, three-string sweep, reverse, lift, separated clusters')
