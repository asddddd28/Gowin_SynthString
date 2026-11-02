"""Pure named-port wrapper built from the explicit AXI endpoint contract."""
import json
from fx_contracts import ROOT
module=json.loads((ROOT/'spec/AxiSynthEndpoint_contract.json').read_text(encoding='utf-8'))['modules'][0]
ports=module['interfaces']['ports']
declarations=[]
for port in ports:
    width='' if port['width']==1 else f"[{port['width']-1}:0] "
    declarations.append(f"    {port['direction']} {width}{port['name']}")
text='''`timescale 1ns / 1ps
// Lean synthesis endpoint / 精简合成顶层. Contract: spec/AxiSynthEndpoint_spec.md.
// The legacy raw/context branch remains available through AxiVoiceEndpoint.
module AxiSynthEndpoint #(parameter C_DELAY_ADDR_BITS=15)(
'''+',\n'.join(declarations)+'\n);\n    AxiVoiceEndpoint #(.LEGACY_ENABLE(0),.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS)) Endpoint_Inst(\n'
text+=',\n'.join(f"        .{p['name']}({p['name']})" for p in ports)+'\n    );\nendmodule\n'
(ROOT/'rtl/AxiSynthEndpoint.v').write_text(text,encoding='utf-8')
