import sys

vcd_path = 'tb_uart_soc.vcd'
vars = { 'if_pc_out': None, 'id_pc': None, 'ex_pc': None }

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
        elif line.strip() in [f"0{v}" for v in id_to_var] or line.strip() in [f"1{v}" for v in id_to_var]:
            val = line[0]
            var = id_to_var[line[1:].strip()]
            state[var] = val
            
        if 740000 <= time <= 770000 and line.startswith('#'):
            if time % 5000 == 0:
                print(f"Time {time}: if_pc={int(state['if_pc_out'],2)} id_pc={int(state['id_pc'],2) if state['id_pc'] else 0} ex_pc={int(state['ex_pc'],2) if state['ex_pc'] else 0}")
