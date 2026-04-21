import sys

vcd_path = 'tb_uart_soc.vcd'
vars = {
    'branch_taken': None,
    'fw_operand1': None,
    'fw_operand2': None,
    'id_ex_rs1': None,
    'id_ex_rs2': None,
    'forward_a': None,
    'forward_b': None,
    'mem_ex_result': None,
    'wb_result': None,
    'alu_operand1': None,
    'alu_operand2': None,
    'ex_alu_to_reg': None,
    'ex_mem_to_reg': None
}

with open(vcd_path, 'r') as f:
    for line in f:
        if '$var' in line:
            parts = line.split()
            for v in vars:
                if f' {v} ' in line:
                    vars[v] = parts[3]
        if '$enddefinitions' in line: break

id_to_var = {v: k for k, v in vars.items() if v}
state = {k: '0' for k in vars}

with open(vcd_path, 'r') as f:
    time = 0
    for line in f:
        if line.startswith('#'):
            time = int(line[1:].strip())
        elif line.startswith('b'):
            parts = line.strip().split()
            if len(parts) == 2 and parts[1] in id_to_var:
                val = parts[0][1:]
                var = id_to_var[parts[1]]
                state[var] = val
        elif line.strip() in [f"0{v}" for v in id_to_var] or line.strip() in [f"1{v}" for v in id_to_var]:
            val = line[0]
            var = id_to_var[line[1:].strip()]
            state[var] = val
            
        if time == 765000:
            if line.startswith('#'):
                print(f"Time {time}:")
                print(f"fw1={state['fw_operand1']} ({int(state['fw_operand1'],2) if state['fw_operand1'] else 'X'})")
                print(f"fw2={state['fw_operand2']} ({int(state['fw_operand2'],2) if state['fw_operand2'] else 'X'})")
                print(f"rs1={state['id_ex_rs1']}, rs2={state['id_ex_rs2']}")
                print(f"fA={state['forward_a']}, fB={state['forward_b']}")
                print(f"mem_res={state['mem_ex_result']} ({int(state['mem_ex_result'], 2) if state['mem_ex_result'] else 'X'})")
                print(f"wb_res={state['wb_result']} ({int(state['wb_result'], 2) if state['wb_result'] else 'X'})")
                print(f"alu_to_reg={state['ex_alu_to_reg']}")
                print(f"branch_taken={state['branch_taken']}")
