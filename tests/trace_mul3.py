import sys

vcd_path = 'tb_uart_soc.vcd'
vars = {
    'mult_div_ready': None,
    'result': None,
    'ex_result_calc': None,
    'mem_ex_result': None,
    'write_data_out': None,
    'wb_result': None,
    'branch_taken': None
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
                if 745000 <= time <= 785000:
                    print(f"Time {time}: {var} = {val} ({int(val,2) if val and len(val) <= 32 else 'X'})")
        elif line.strip() in [f"0{v}" for v in id_to_var] or line.strip() in [f"1{v}" for v in id_to_var]:
            val = line[0]
            var = id_to_var[line[1:].strip()]
            state[var] = val
            if 745000 <= time <= 785000:
                print(f"Time {time}: {var} = {val}")
