// minimal RV32I implementation
`timescale 1ns/1ps

module simple_rv32i(
    input clk,
    input reset  
);

reg write_on;
reg [31:0] write_data;

reg [31:0] pc;
reg [31:0] inst_mem [0:255];
wire [31:0] inst;

// instruction fetch
assign inst = inst_mem[pc >> 2];

// decode format
// instruction wider than 16 bits (not RVC), therefore inst[1:0] is always 2'b11
// inst[6:2] for relevant opcodes
wire [4:0] opcode = inst[6:2];
reg [4:0] rd, rs1, rs2;
reg [2:0] funct3;
reg [6:0] funct7;
reg [31:0] imm;

reg [3:0] inst_type;

always @(*) begin
    case(opcode)
        5'b01100: begin // R-type
            rd = inst[11:7];
            funct3 = inst[14:12];
            rs1 = inst[19:15];
            rs2 = inst[24:20];
            funct7 = inst[31:25];
            inst_type = 4'b0000;
        end
        5'b00100: begin // I-type arithmetic/logic immediate
            rd = inst[11:7];
            funct3 = inst[14:12];
            rs1 = inst[19:15];
            imm = {{21{inst[31]}},inst[30:20]};
            inst_type = 4'b0001;
        end
        5'b00000: begin // I-type load
            rd = inst[11:7];
            funct3 = inst[14:12];
            rs1 = inst[19:15];
            imm = {{21{inst[31]}},inst[30:20]};
            inst_type = 4'b0010;
        end
        5'b01000: begin // S-type
            funct3 = inst[14:12];
            rs1 = inst[19:15];
            imm = {{21{inst[31]}},inst[30:25],inst[11:7]};
            inst_type = 4'b0011;
        end
        5'b01101: begin // U-type LUI
            rd = inst[11:7];
            imm = {inst[31:12], 12'b0};
            inst_type = 4'b0100;
        end
        5'b00101: begin // U-type AUIPC
            rd = inst[11:7];
            imm = {inst[31:12], 12'b0};
            inst_type = 4'b0101;
        end
        5'b11000: begin // B-type
            funct3 = inst[14:12];
            rs1 = inst[19:15];
            rs2 = inst[24:20];
            imm = {{20{inst[31]}},inst[7],inst[30:25],inst[11:8],1'b0};
            inst_type = 4'b0110;
        end
        5'b11011: begin // J-type JAL
            rd = inst[11:7];
            imm = {{12{inst[31]}},inst[19:12],inst[20],inst[30:21],1'b0};
            inst_type = 4'b0111;
        end
        5'b11001: begin // J-type JALR
            rd = inst[11:7];
            imm = {{12{inst[31]}},inst[19:12],inst[20],inst[30:21],1'b0};
            inst_type = 4'b1000;
        end
        default: begin
            inst_type = 4'b1111; // invalid for this core
        end
    endcase
end

// register file
reg [31:0] reg_file [31:0];
always @(posedge clk) begin
    if (write_on && rd != 0)
        reg_file[rd] <= write_data;
end

// ALU
reg [31:0] alu_oper1, alu_oper2;
reg [31:0] alu_result;

always @(*) begin
    alu_oper1 = 32'b0;
    alu_oper2 = 32'b0;
    alu_result = 32'b0;
    write_data = 32'b0;
    write_on = 0;

    if (inst_type == 4'b0000 || inst_type == 4'b0001) begin
        alu_oper1 = reg_file[rs1];
        alu_oper2 = (inst_type == 4'b0001) ? imm : reg_file[rs2];

        case(funct3)
            3'b000: alu_result = (funct7 == 7'b0100000) ? 
                (alu_oper1 - alu_oper2) : // SUB
                (alu_oper1 + alu_oper2); // ADD
            3'b111: alu_result = alu_oper1 & alu_oper2; // AND and ANDI
            3'b110: alu_result = alu_oper1 | alu_oper2; // OR and ORI
            3'b100: alu_result = alu_oper1 ^ alu_oper2; // XOR and XORI
            3'b010: alu_result = ($signed(alu_oper1) < $signed(alu_oper2)) ? 32'b1 : 32'b0; // SLT and SLTI
            3'b011: alu_result = (alu_oper1 < alu_oper2) ? 32'b1 : 32'b0; // SLTU and SLTIU
            3'b001: alu_result = alu_oper1 << alu_oper2[4:0]; // SLL and SLLI
            3'b101: alu_result = (funct7 == 7'b0100000) ? 
                ($signed(alu_oper1) >>> alu_oper2[4:0]) : // SRA and SRAI
                (alu_oper1 >> alu_oper2[4:0]); // SRL and SRLI
            default: begin
                alu_result = 32'b0;
            end
        endcase

        write_data = alu_result;
        write_on = 1;
    end
    else if (inst_type == 4'b0100) begin // LUI
        write_data = imm;
        write_on = 1;
    end
    else if (inst_type == 4'b0101) begin // AUIPC
        write_data = pc + imm;
        write_on = 1;
    end
end

// branches
reg branched;

always @(*) begin
    branched = 1'b0;

    if (inst_type == 4'b0110) begin
        case(funct3)
            3'b000: branched = (reg_file[rs1] == reg_file[rs2]); // BEQ
            3'b001: branched = (reg_file[rs1] != reg_file[rs2]); // BNE
            3'b100: branched = ($signed(reg_file[rs1]) < $signed(reg_file[rs2])); // BLT
            3'b101: branched = ($signed(reg_file[rs1]) >= $signed(reg_file[rs2])); // BGE
        endcase
    end
end

// load/store
// not implemented yet, will go here

// single-cycle, no cache
always @(posedge clk or posedge reset) begin
    if (reset) begin
        pc <= 0;
    end else begin
        if (inst_type == 4'b0111) begin // JAL
            if (rd != 0) reg_file[rd] <= pc + 4;
            pc <= pc + imm;
        end else if (inst_type == 4'b1000) begin // JALR
            if (rd != 0) begin
                reg_file[rd] <= pc + 4;
            end
            pc <= (reg_file[rs1] + imm) & ~1;
        end else if (inst_type == 4'b0110 && branched) begin // Branches
            pc <= pc + imm;
        end else begin
            pc <= pc + 4; // normal count
        end
    end
end

endmodule
