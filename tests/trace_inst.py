import sys

vcd_path = 'tb_uart_soc.vcd'
vars = { 'if_id_inst': None, 'id_ex_inst': None }

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
                if 740000 <= time <= 800000:
                    print(f"Time {time}: {var} changed to {val} ({hex(int(val,2)) if val else '0'})")
