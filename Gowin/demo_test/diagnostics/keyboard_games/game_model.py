"""Independent, deterministic rules oracle used to plan RTL game test cases."""
CONTROLS={22,29,30,31}
SCORES={1:10,2:30,3:20}
PALETTE={0:0x000000,1:0x200000,2:0x002000,3:0x200020}

def snake_step(body,direction,apple):
    row,col=divmod(body[0],8)
    dr,dc=((-1,0),(1,0),(0,-1),(0,1))[direction]
    row,col=row+dr,col+dc
    if not 0<=row<4 or not 0<=col<8 or row*8+col in CONTROLS:return body,1,False
    head=row*8+col;grow=head==apple
    if head in (body if grow else body[:-1]):return body,2,False
    return [head]+(body if grow else body[:-1]),0,grow

def piano_step(notes,mask):
    bottom=(mask>>24)&255
    if bottom==0:return notes,0,False
    if bottom!=1<<notes[3]:return notes,3,False
    return [None]+notes[:3],0,True

def whack_score(targets,press_mask):
    return sum(SCORES[color] for key,color in targets.items() if press_mask>>key&1)

if __name__=='__main__':
    assert snake_step([10,9,8],3,11)==([11,10,9,8],0,True)
    assert snake_step([10,9,8],0,0)==([2,10,9],0,False)
    assert snake_step([2,10,9],0,0)[1]==1
    assert snake_step([9,10,18,17],1,0)==([17,9,10,18],0,False)
    assert snake_step([9,10,18,17],3,0)[1]==2
    assert piano_step([0,3,5,2],1<<26)==([None,0,3,5],0,True)
    assert piano_step([0,3,5,2],(1<<26)|(1<<25))[1]==3
    assert whack_score({0:1,5:2,20:3},(1<<0)|(1<<20))==30
    print('PASS independent game rule cases')
