import sys

vcd_path = 'tb_uart_soc.vcd'
vars = { 'if_pc_out': None, 'id_pc': None, 'id_instruction': None }

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
                state[id_to_var[parts[1]]] = val
        if time in [715000, 725000, 735000, 745000] and line.startswith('#'):
            print(f"Time {time}: if_pc={int(state['if_pc_out'],2)} id_pc={int(state['id_pc'],2)} inst={hex(int(state['id_instruction'],2)) if state['id_instruction'] else 0}")
