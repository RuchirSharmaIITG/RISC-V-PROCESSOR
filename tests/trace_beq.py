import sys

vcd_path = 'tb_uart_soc.vcd'

# We need to find:
# - What values are being compared at the BEQ after MUL (PC=0x40=64)
# - fw_operand1 and fw_operand2 when BEQ is in EX
# 
# The BEQ at PC 64 compares t5 (reg 30) and t6 (reg 31)
# MUL writes to t5=30 (rd), li t6,200 writes to t6=31

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
    'ex_alu_to_reg': None,
    'mem_alu_to_reg': None,
    'wb_alu_to_reg': None
}

with open(vcd_path, 'r') as f:
    for line in f:
        if '$var' in line:
            parts = line.split()
            for v in vars:
                if f' {v} ' in line and vars[v] is None:
                    vars[v] = parts[3]
        if '$enddefinitions' in line:
            break

id_to_var = {v: k for k, v in vars.items() if v}
state = {k: '0' for k in vars}

def safe_int(s):
    try:
        return int(s, 2)
    except:
        return -1

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
        
        # Print around when BEQ (PC=64=0x40) is in EX stage
        # From traces, MUL at PC=56 finishes around T=765000
        # BEQ would be a few cycles after
        if 770000 <= time <= 810000 and line.startswith('#') and time % 10000 == 5000:
            pc = safe_int(state['ex_pc'])
            print(f"T={time} PC={pc}(0x{pc:x}) | rs1={safe_int(state['id_ex_rs1'])} rs2={safe_int(state['id_ex_rs2'])} | " +
                  f"fw1={safe_int(state['fw_operand1'])} fw2={safe_int(state['fw_operand2'])} | " +
                  f"fA={safe_int(state['forward_a'])} fB={safe_int(state['forward_b'])} | " +
                  f"ex_res={safe_int(state['ex_result_calc'])} mem_res={safe_int(state['mem_ex_result'])} wb_res={safe_int(state['wb_result'])} | " +
                  f"em_rd={safe_int(state['ex_mem_rd'])} mw_rd={safe_int(state['mem_wb_rd'])} | " +
                  f"br={state['branch_taken']}")
