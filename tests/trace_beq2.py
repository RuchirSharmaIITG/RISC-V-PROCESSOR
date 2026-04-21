import sys

vcd_path = 'tb_uart_soc.vcd'

vars = {
    'ex_pc': None,
    'fw_operand1': None,
    'fw_operand2': None,
    'forward_a': None,
    'forward_b': None,
    'id_ex_rs1': None,
    'id_ex_rs2': None,
    'ex_result_calc': None,
    'mem_ex_result': None,
    'wb_result': None,
    'branch_taken': None,
    'ex_mem_rd': None,
    'mem_wb_rd': None,
    'ex_mult_div_en': None,
    'branch_i': None,
    'alu_operand1': None,
    'alu_operand2': None,
    'immediate_sel_i': None,
}

with open(vcd_path, 'r') as f:
    for line in f:
        if '$var' in line:
            parts = line.split()
            for v in vars:
                if f' {v} ' in line and vars[v] is None:
                    vars[v] = parts[3]
        if '$enddefinitions' in line: break

id_to_var = {v: k for k, v in vars.items() if v}
state = {k: '0' for k in vars}

def safe_int(s):
    try: return int(s, 2)
    except: return -1

with open(vcd_path, 'r') as f:
    time = 0
    for line in f:
        if line.startswith('#'):
            time = int(line[1:].strip())
        elif line.startswith('b'):
            parts = line.strip().split()
            if len(parts) == 2 and parts[1] in id_to_var:
                state[id_to_var[parts[1]]] = parts[0][1:]
        elif len(line.strip()) >= 2:
            bit = line.strip()[0]
            var_id = line.strip()[1:]
            if var_id in id_to_var and bit in ('0', '1'):
                state[id_to_var[var_id]] = bit
        
        # BEQ is at PC=60 in EX. Should be around T=785000
        if time in [775000, 785000, 795000] and line.startswith('#'):
            pc = safe_int(state['ex_pc'])
            print(f"\n=== T={time} EX_PC={pc}(0x{pc:02x}) ===")
            print(f"  rs1={safe_int(state['id_ex_rs1'])} rs2={safe_int(state['id_ex_rs2'])}")
            print(f"  fw_op1={safe_int(state['fw_operand1'])} fw_op2={safe_int(state['fw_operand2'])}")
            print(f"  fwd_a={safe_int(state['forward_a'])} fwd_b={safe_int(state['forward_b'])}")
            print(f"  alu_op1={safe_int(state['alu_operand1'])} alu_op2={safe_int(state['alu_operand2'])}")
            print(f"  imm_sel={state['immediate_sel_i']}")
            print(f"  ex_result={safe_int(state['ex_result_calc'])} mem_res={safe_int(state['mem_ex_result'])} wb_res={safe_int(state['wb_result'])}")
            print(f"  em_rd={safe_int(state['ex_mem_rd'])} mw_rd={safe_int(state['mem_wb_rd'])}")
            print(f"  branch_i={state['branch_i']} branch_taken={state['branch_taken']}")
            print(f"  mult_div_en={state['ex_mult_div_en']}")
