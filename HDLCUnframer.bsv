import GetPut::*;
import FIFOF::*;
import Assert::*;

interface HDLCUnframer;
    interface Put#(Bit#(1)) in;
    interface Get#(Tuple2#(Bool, Bit#(8))) out;
endinterface

module mkHDLCUnframer(HDLCUnframer);
    FIFOF#(Tuple2#(Bool, Bit#(8))) fifo_out <- mkFIFOF;
    Reg#(Bool) start_of_frame <- mkReg(True);
    Bit#(9) octet_reset_value = 9'b1_0000_0000;
    Reg#(Bit#(9)) octet <- mkReg(octet_reset_value);
    Reg#(Bit#(6)) one_count <- mkReg(0); // Contador de 1s consecutivos
    Reg#(Bit#(7)) recent_bits <- mkReg(0);

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            // Shift os bits para a direita, adicionando o novo bit à esquerda
            octet <= (octet << 1) | zeroExtend(b);

            // Incrementa o contador de 1s consecutivos
            one_count <= one_count + b;

            // Verifica se recebeu uma sequência de flag HDLC (01111110)
            if (octet[7:0] == 8'b01111110) begin
                start_of_frame <= True;
                one_count <= 0;
            end else if (one_count == 6) begin
                // Verifica o bit stuffing (seis 1s consecutivos seguidos por 0)
                if (b == 0) begin
                    // Ignora o 0 adicionado por bit stuffing
                    one_count <= 0;
                end else begin
                    // Se o sétimo bit não for 0, houve erro de framing
                    octet <= (octet << 1) | zeroExtend(b);
                end
            end else if (octet[8]) begin
                // Byte completo recebido
                fifo_out.enq(tuple2(start_of_frame, octet[7:0]));
                start_of_frame <= False;
                octet <= octet_reset_value;
                one_count <= 0;
            end
        endmethod
    endinterface
endmodule
