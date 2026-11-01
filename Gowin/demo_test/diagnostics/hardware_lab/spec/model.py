"""整行仲裁和带宽的独立参考合同。"""
from collections import deque

class Arbiter:
    def __init__(self): self.next=0;self.priority_next=0;self.urgent_run=0
    def select(self,pending,urgent):
        normal=[i for i in range(5) if pending[i] and not urgent[i]]
        priority=[i for i in range(5) if pending[i] and urgent[i]]
        group=priority if priority and (self.urgent_run<3 or not normal) else normal
        if not group:return None
        cursor=self.priority_next if group is priority else self.next
        chosen=next((cursor+j)%5 for j in range(5) if (cursor+j)%5 in group)
        if group is priority:self.priority_next=(chosen+1)%5
        else:self.next=(chosen+1)%5
        self.urgent_run=min(3,self.urgent_run+1) if urgent[chosen] else 0
        return chosen

if __name__=='__main__':
    a=Arbiter();selected=[a.select([True]*5,[True,False,False,True,False]) for _ in range(32)]
    assert all(i in selected for i in range(5))
    assert all(any(i in (1,2,4) for i in selected[j:j+4]) for j in range(29))
    budget=10*(32*9+23+37)+10*5*34+20*21+20*(100+37)+4*15
    assert budget==8400 and budget<115200/10
    print('PASS five-source bounded-priority fairness; idle telemetry8400B/s of11520B/s')
