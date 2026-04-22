import sys

vcd_path = 'tb_uart_soc.vcd'
vars = {
    'mult_div_en_i': None,
    'mult_div_busy': None,
    'mult_div_ready': None,
    'rs1_data': None,
    'rs2_data': None,
    'result': None,
    'start': None
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
                state[id_to_var[parts[1]]] = val
                if id_to_var[parts[1]] == 'result':
                    print(f"Time {time}: result changed to {val} (integer: {int(val,2)})")
        elif line.strip() in [f"0{v}" for v in id_to_var] or line.strip() in [f"1{v}" for v in id_to_var]:
            val = line[0]
            var = id_to_var[line[1:].strip()]
            state[var] = val
            if var in ['mult_div_busy', 'mult_div_ready', 'mult_div_en_i', 'start']:
                print(f"Time {time}: {var} changed to {val}. r1={state['rs1_data']}, r2={state['rs2_data']}")
