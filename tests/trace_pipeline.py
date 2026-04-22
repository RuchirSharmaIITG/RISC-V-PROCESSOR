import sys

vcd_path = 'tb_uart_soc.vcd'

# Decode hex instructions
instructions = [
    (0x00, 0x05400513, "li a0, 'T'"),
    (0x04, 0x0d0000ef, "jal ra, print_char"),
    (0x08, 0x00a00e13, "li t3, 10"),
    (0x0c, 0x01400e93, "li t4, 20"),
    (0x10, 0x01de0f33, "add t5, t3, t4"),
    (0x14, 0x01e00f93, "li t6, 30"),
    (0x18, 0x01ff0663, "beq t5, t6, add_pass"),
    (0x1c, 0x04600513, "li a0, 'F'"),
    (0x20, 0x0080006f, "j add_print"),
    (0x24, 0x05000513, "li a0, 'P'"),
    (0x28, 0x0ac000ef, "jal ra, print_char"),
    (0x2c, 0x00a00e13, "li t3, 10 (MUL)"),
    (0x30, 0x01400e93, "li t4, 20"),
    (0x34, 0x03de0f33, "mul t5, t3, t4"),
    (0x38, 0x0c800f93, "li t6, 200"),
    (0x3c, 0x01ff0663, "beq t5, t6, mul_pass"),
    (0x40, 0x05800513, "li a0, 'X'"),
    (0x44, 0x0080006f, "j mul_print"),
    (0x48, 0x05000513, "li a0, 'P'"),
    (0x4c, 0x088000ef, "jal ra, print_char"),
]

inst_map = {addr: (h, desc) for addr, h, desc in instructions}

vars = { 'ex_pc': None, 'id_pc': None, 'if_pc_out': None, 'id_instruction': None }

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
        
        if 400000 <= time <= 810000 and line.startswith('#') and time % 10000 == 5000:
            ex_pc = safe_int(state['ex_pc'])
            id_pc = safe_int(state['id_pc'])
            if_pc = safe_int(state['if_pc_out'])
            id_inst = safe_int(state['id_instruction'])
            
            ex_desc = inst_map.get(ex_pc, (0, f"?"))[1] if ex_pc >= 0 else "?"
            id_desc = inst_map.get(id_pc, (0, f"?"))[1] if id_pc >= 0 else "?"
            
            print(f"T={time}: IF={if_pc}(0x{if_pc:02x}) ID={id_pc}(0x{id_pc:02x})[{id_desc}] EX={ex_pc}(0x{ex_pc:02x})[{ex_desc}] id_inst=0x{id_inst:08x}")
