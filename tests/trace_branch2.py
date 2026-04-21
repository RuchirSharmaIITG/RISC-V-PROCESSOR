import sys

vcd_path = 'tb_uart_soc.vcd'
vars = {
    'branch_taken': None,
    'fw_operand1': None,
    'fw_operand2': None,
    'id_ex_rs1': None,
    'id_ex_rs2': None,
    'forward_a': None,
    'forward_b': None
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
                if 740000 <= time <= 800000 and var == 'branch_taken':
                    print(f"Time {time}: branch_taken = {val}. fw1={state['fw_operand1']}, fw2={state['fw_operand2']}, rs1={state['id_ex_rs1']}, rs2={state['id_ex_rs2']}, fA={state['forward_a']}, fB={state['forward_b']}")
        elif line.strip() in [f"0{v}" for v in id_to_var] or line.strip() in [f"1{v}" for v in id_to_var]:
            val = line[0]
            var = id_to_var[line[1:].strip()]
            state[var] = val
            if 740000 <= time <= 800000 and var == 'branch_taken':
                print(f"Time {time}: branch_taken = {val}. fw1={state['fw_operand1']}, fw2={state['fw_operand2']}, rs1={state['id_ex_rs1']}, rs2={state['id_ex_rs2']}, fA={state['forward_a']}, fB={state['forward_b']}")
