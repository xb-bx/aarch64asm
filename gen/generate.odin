package gen
import "core:encoding/json"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:fmt"
import "core:io"
import "core:bufio"
import "core:os"
Field :: struct {
    name:  string,
    start: int,
    width: int,
    type:  string,
}

Instruction :: struct {
    id:       string,
    opcode:   u32,      
    fields:   []Field,
    mnemonic: string,
}

read_line :: proc(reader: ^bufio.Reader) -> (string, bool) {
    l, b := bufio.reader_read_string(reader, '\n')
    l = strings.trim_space(l)
    return l, b == .None
}
atoi :: proc(s: string) -> int {
    v, _ := strconv.parse_int(s)
    return v
}
ones := "1111111111111111111111111111111111111111111111111";
generate_instruction :: proc(instr: Instruction, dir: string, mnemonics: ^map[string][dynamic]string) {
    if i, ok := mnemonics[instr.mnemonic]; ok {
        append(&mnemonics[instr.mnemonic], instr.id)
    } else {
        mnemonics[instr.mnemonic] = make([dynamic]string)
        append(&mnemonics[instr.mnemonic], instr.id)
    }
    is_sf := instr.fields[0].name == "sf"
    flds := is_sf ? instr.fields[1:] : instr.fields
    is_opc := flds[0].name == "opc"
    flds = is_opc ? flds[1:] : flds
    is_float := flds[0].name == "type"
    flds = is_float ? flds[1:] : flds
    fd, err := os.open(fmt.aprintf("%s/%s.gen.odin", dir, instr.id), os.O_CREATE | os.O_TRUNC | os.O_WRONLY, 0o644)
    fmt.fprintln(fd, "package aarch64")
    fmt.fprintln(fd, "@private")
    fmt.fprintf(fd, "%s :: #force_inline proc(a: ^Assembler,", instr.id)
    decld := false
    for fld in flds {
        type: string = ""
        name: string = ""
        if fld.name == "shift" {
            name = "shift"
            type = "Shift = .LSL"
        } else if fld.name == "shiftbool" {
            name = "shiftbool"
            type = "bool = false"
        } else if strings.starts_with(fld.name, "R") {
            name = fld.name
            if is_opc {
                type = decld ? "$T2" : "$T1"
            } else if is_sf && is_float {
                type = decld ? "$T2" : "$T1"
            } else {
                type = is_sf ? decld ? "T" : "$T" : "XReg"
                type = is_float ? decld ? "T" : "$T" : type
            }
            decld = true
        } else if strings.starts_with(fld.name, "imm") {
            name = fld.name
            type = "i32 = 0"
        } else if strings.starts_with(fld.name, "option") {
            name = fld.name
            type = "Extend"
        } else if strings.starts_with(fld.name, "label") {
            name = fld.name
            type = "Label"
        } else if strings.starts_with(fld.name, "cond") {
            name = fld.name
            type = "Cond"
        } else if strings.starts_with(fld.name, "hw") {
            name = fld.name
            type = "i8 = 0"
        } else {
            fmt.println(fld)
            fmt.println(instr.fields, instr.mnemonic)
            panic("todo")
        }
        fmt.fprintf(fd, "%s: %s, ", name, type)
    }
    rd := Field {}
    for i in flds {
        if i.name == "Rd" {
            rd = i
            break
        }
    }
    if is_sf && is_float {
        if rd.type == "GP" {
            fmt.fprintln(fd, ") where (T1 == XReg || T1 == WReg) && (T2 == DReg || T2 == SReg || T2 == HReg) {")
        } else {
            fmt.fprintln(fd, ") where (T2 == XReg || T2 == WReg) && (T1 == DReg || T1 == SReg || T1 == HReg) {")
        }
    } else if is_opc {
        fmt.fprintln(fd, ") where (T1 == DReg || T1 == SReg || T1 == HReg) && (T2 == DReg || T2 == SReg || T2 == HReg) && T1 != T2 {")
    } else if is_sf {
        fmt.fprintln(fd, ") where T == XReg || T == WReg {")
    } else if is_float {
        fmt.fprintln(fd, ") where T == DReg || T == SReg || T == HReg {")
    } else {
        fmt.fprintln(fd, ") {")
    }
    fmt.fprintfln(fd, "result: u32 = 0x%4X", instr.opcode)
    for fld in flds {
        if fld.name == "label" {
                fmt.fprintfln(fd, "append(&a.labelplaces, Labelplace {{ %s.id, len(a.bytes), %i, %i })", fld.name, fld.start, fld.width) 
        } else {
            fmt.fprintfln(fd, "result |= ((u32(%s) & 0b%s) << %i)", fld.name, ones[:fld.width], fld.start)
        }
    }
    if is_sf && is_float {
        if rd.type == "GP" {
            fmt.fprintfln(fd, "when T1 == XReg {{ result |= ((0b01) << %i) }", instr.fields[0].start)
            fmt.fprintfln(fd, "when T2 == HReg {{ result |= ((0b11) << %i) }", instr.fields[1].start)
            fmt.fprintfln(fd, "when T2 == DReg {{ result |= ((0b01) << %i) }", instr.fields[1].start)
        } else {
            fmt.fprintfln(fd, "when T2 == XReg {{ result |= ((0b01) << %i) }", instr.fields[0].start)
            fmt.fprintfln(fd, "when T1 == HReg {{ result |= ((0b11) << %i) }", instr.fields[1].start)
            fmt.fprintfln(fd, "when T1 == DReg {{ result |= ((0b01) << %i) }", instr.fields[1].start)
        }
    } else if is_sf {
        fmt.fprintfln(fd, "when T == XReg {{ result |= ((1) << %i) }", instr.fields[0].start)
    } else if is_float {
        if is_opc {
            fmt.fprintfln(fd, "when T1 == HReg {{ result |= ((0b11) << %i) }", instr.fields[0].start)
            fmt.fprintfln(fd, "when T1 == DReg {{ result |= ((0b01) << %i) }", instr.fields[0].start)
            fmt.fprintfln(fd, "when T2 == HReg {{ result |= ((0b11) << %i) }", instr.fields[1].start)
            fmt.fprintfln(fd, "when T2 == DReg {{ result |= ((0b01) << %i) }", instr.fields[1].start)
        } else {
            fmt.fprintfln(fd, "when T == HReg {{ result |= ((0b11) << %i) }", instr.fields[0].start)
            fmt.fprintfln(fd, "when T == DReg {{ result |= ((0b01) << %i) }", instr.fields[0].start)
        }
    }
    fmt.fprintln(fd, "append(&a.bytes, result)")
    fmt.fprintln(fd, "}")

} 
main :: proc() {
    data, ok := os.read_entire_file(os.args[1])
    if !ok do os.exit(1)
    instrs: []Instruction = nil
    err := json.unmarshal(data, &instrs)
    assert(err == nil)
    mnemonics := make(map[string][dynamic]string)
    for &instr in instrs {
        generate_instruction(instr, os.args[2], &mnemonics)
    }
    for k, v in mnemonics {
        fd, er := os.open(fmt.aprintf("%s/%s.gen.odin", os.args[2], strings.to_lower(k)), os.O_CREATE | os.O_TRUNC | os.O_WRONLY, 0o644)
        fmt.fprintln(fd, "package aarch64")
        fmt.fprintfln(fd, "%s :: proc {{ ", strings.to_lower(k))
        for i in v {
            fmt.fprintfln(fd, "%s,", i)
        }
        fmt.fprintln(fd, "}")
    }
    fmt.println(mnemonics)
}
