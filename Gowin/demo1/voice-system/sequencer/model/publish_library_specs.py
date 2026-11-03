"""只更新新增库页面/输入行为的既有合同，保留其他模块后续新增端口。"""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
changes = {
    'SynthDisplayControl':[
        'HDMI能力版本0x10001，支持0..7共八页；0x11参数8及以上拒绝，左右自然三位回绕。0..5兼容原页面，6为音序库，7为SD音色库。',
        '显示接口仍为0x10..0x13和1024字节文本RAM；不直接执行文件写入。库页面上的旋钮/确认语义由存储控制器接管，不可误应用算子草稿。'],
    'SynthDisplayVideo':[
        '资源生成器提供八页，总计88个唯一128字符行，仍使用11264×18位字符ROM（11块BSRAM）和原512项行指针。共享导航栏通过页标题标识当前页面。',
        '新库页面共用文本128..383显示8条列表，512..639显示库标题/操作说明/选择/状态；其余页面显示内容不变。未挂载时显示明确的SD未就绪状态，不显示伪造条目。'],
}
env=os.environ.copy()
env['PYTHONPATH']='C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
env['PYTHONIOENCODING']='utf-8'
for name,behavior in changes.items():
    path=ROOT/f'hdmi/spec/{name}_contract.json'
    contract=json.loads(path.read_text(encoding='utf-8'))
    module=contract['modules'][0]
    module['behavior']=[b.replace('six pages','eight pages') for b in module['behavior']]
    for text in behavior:
        if text not in module['behavior']:module['behavior'].append(text)
    module['verification_cases'].append('tb_display_control覆盖页面6/7、无效8、7→0和0→7回绕；显示资源88行不超原ROM；Rust库页面屏蔽算子编辑内容。')
    path.write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
    with (ROOT/f'reports/sequencer/{name}-library-spec.log').open('w',encoding='utf-8') as log:
        subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(ROOT/'hdmi'),'--language','zh'],env=env,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    print(name)
